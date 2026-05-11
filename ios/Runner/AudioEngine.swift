import AVFoundation

/// AVAudioEngine + AVAudioPlayerNode 기반 오디오 파일 재생.
/// step 1-1(비프 생성)에서 step 1-2(파일 재생)으로 전환.
class AudioEngine {
    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?

    private var sampleRate: Double = 48000
    private var seekFrameOffset: Int64 = 0
    private var isEngineRunning = false
    // prewarm: AVAudioSession + engine만 미리 데움. 노드는 attach만 하고 play X.
    // 다음 start()에서 scheduleAndPlay만 하면 BT codec/세션 워밍업이 이미 끝나
    // 있어 첫 재생 정착 시간 단축 (v0.0.44).
    private var sessionActivated = false

    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    // MARK: - Public API

    func loadFile(_ path: String) -> [String: Any] {
        if isEngineRunning { stop() }

        let url = URL(fileURLWithPath: path)
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            seekFrameOffset = 0
            print("[AudioEngine] loaded: sr=\(sampleRate), frames=\(file.length), ch=\(file.processingFormat.channelCount), path=\(path)")
            return [
                "ok": true,
                "totalFrames": file.length,
                "sampleRate": sampleRate,
            ]
        } catch {
            print("[AudioEngine] loadFile error: \(error)")
            return ["ok": false]
        }
    }

    /// AVAudioSession만 미리 active. **engine.start / 노드 attach는 start()에서**.
    /// 이유: engine을 prewarm에서 start하면 `outputNode.lastRenderTime.sampleTime`
    /// 이 prewarm 시점부터 누적되어 `getTimestamp().framePos`가 콘텐츠 frame과
    /// 분리됨 → anchor establish 시 호스트 콘텐츠 frame 외삽이 부정확 + 음향상
    /// ~5ms 어긋남 (v0.0.44 (40-1) 실측: guest fpVfDiff 54,467초 누적 확인).
    /// → setActive(true)까지만 미리 = BT routing/codec 워밍업 + outputLatency
    /// 측정 시작은 가능, framePos 누적은 차단 (v0.0.44 (40-2)).
    func prewarm() -> Bool {
        if isEngineRunning { return true }
        guard audioFile != nil else {
            print("[AudioEngine] prewarm: no file loaded")
            return false
        }
        if sessionActivated { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            sessionActivated = true
            print("[AudioEngine] prewarm: session active outLat=\(session.outputLatency)")
            return true
        } catch {
            print("[AudioEngine] prewarm error: \(error)")
            sessionActivated = false
            return false
        }
    }

    func start() -> Bool {
        if isEngineRunning {
            scheduleAndPlay(from: seekFrameOffset)
            return true
        }
        guard let file = audioFile else {
            print("[AudioEngine] start: no file loaded")
            return false
        }
        do {
            // prewarm이 setActive까지만 하므로 여기서 session 보장 + engine 가동.
            if !sessionActivated {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setPreferredSampleRate(sampleRate)
                try session.setPreferredIOBufferDuration(0.005)
                try session.setActive(true)
                sessionActivated = true
            }
            let session = AVAudioSession.sharedInstance()
            print("[AudioEngine] start: hw sr=\(session.sampleRate), file sr=\(sampleRate), ioBuf=\(session.ioBufferDuration), outLat=\(session.outputLatency)")

            let node = AVAudioPlayerNode()
            playerNode = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            try engine.start()
            isEngineRunning = true
            scheduleAndPlay(from: seekFrameOffset)
            return true
        } catch {
            print("[AudioEngine] start error: \(error)")
            return false
        }
    }

    /// idle 자동 해제용. engine + AVAudioSession을 내려 다른 앱 오디오를 풀어줌.
    /// audioFile은 유지 → 다음 prewarm/start 시 디코딩 재사용. (v0.0.44)
    @discardableResult
    func coolDown() -> Bool {
        if isEngineRunning { stop() }
        if sessionActivated {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation)
            } catch {
                print("[AudioEngine] coolDown deactivate error: \(error)")
            }
            sessionActivated = false
        }
        return true
    }

    @discardableResult
    func stop() -> Bool {
        // 정지 직전 위치를 seekFrameOffset에 누적 → 다음 start()의 scheduleAndPlay
        // 가 그 위치부터 재생. 안 하면 마지막 seek 위치(또는 0)부터 재생됨 (v0.0.43).
        if let node = playerNode,
           let nodeTime = node.lastRenderTime,
           nodeTime.isSampleTimeValid,
           let playerTime = node.playerTime(forNodeTime: nodeTime) {
            seekFrameOffset += Int64(playerTime.sampleTime)
            if let file = audioFile {
                seekFrameOffset = max(0, min(seekFrameOffset, file.length))
            }
        }
        isEngineRunning = false
        playerNode?.stop()
        engine.stop()
        if let node = playerNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            playerNode = nil
        }
        return true
    }

    /// NTP-style 예약 재생 (v0.0.47). wall clock ms → mach hostTime 변환 후
    /// `playerNode.play(at: AVAudioTime)`로 정확한 시각에 출력 시작.
    /// 양쪽 (호스트·게스트)가 같은 wallEpochMs를 약속해 동시 출력 → anchor 의존 제거.
    func scheduleStart(wallEpochMs: Int64, fromFrame: Int64) -> Bool {
        guard let file = audioFile else {
            print("[AudioEngine] scheduleStart: no file loaded")
            return false
        }
        // 세션·엔진 보장
        do {
            if !sessionActivated {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setPreferredSampleRate(sampleRate)
                try session.setPreferredIOBufferDuration(0.005)
                try session.setActive(true)
                sessionActivated = true
            }
            if !isEngineRunning {
                let node = AVAudioPlayerNode()
                playerNode = node
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
                try engine.start()
                isEngineRunning = true
            }
        } catch {
            print("[AudioEngine] scheduleStart engine setup error: \(error)")
            return false
        }
        guard let node = playerNode else { return false }

        // 이전 schedule/재생 취소
        node.stop()
        seekFrameOffset = max(0, min(fromFrame, Int64(file.length)))

        // 콘텐츠 segment schedule (즉시 큐만)
        let remaining = file.length - AVAudioFramePosition(seekFrameOffset)
        guard remaining > 0 else { return false }
        node.scheduleSegment(
            file,
            startingFrame: AVAudioFramePosition(seekFrameOffset),
            frameCount: AVAudioFrameCount(remaining),
            at: nil
        )

        // wall time → mach hostTime 변환
        let wallNowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let delayMs = wallEpochMs - wallNowMs
        let info = Self.timebaseInfo
        let nowHostTime = mach_absolute_time()
        // delay (ms) → host ticks: ms * 1e6 ns/ms * denom / numer
        let delayHostTicks: UInt64
        if delayMs > 0 {
            delayHostTicks = UInt64(delayMs) * 1_000_000 * UInt64(info.denom) / UInt64(info.numer)
        } else {
            delayHostTicks = 0
        }
        let scheduledHostTime = nowHostTime + delayHostTicks
        let avTime = AVAudioTime(hostTime: scheduledHostTime)

        node.play(at: avTime)
        print("[AudioEngine] scheduleStart: wallMs=\(wallEpochMs) delayMs=\(delayMs) fromFrame=\(seekFrameOffset)")
        return true
    }

    /// 진행 중인 schedule 취소 + 노드 정지. session·engine은 유지.
    func cancelSchedule() -> Bool {
        if let node = playerNode {
            // 정지 시점 vf를 seekFrameOffset에 누적 (v0.0.43 (38) 패턴)
            if let nodeTime = node.lastRenderTime,
               nodeTime.isSampleTimeValid,
               let playerTime = node.playerTime(forNodeTime: nodeTime) {
                seekFrameOffset += Int64(playerTime.sampleTime)
                if let file = audioFile {
                    seekFrameOffset = max(0, min(seekFrameOffset, file.length))
                }
            }
            node.stop()
        }
        return true
    }

    func seekToFrame(_ newFrame: Int64) -> Bool {
        guard let file = audioFile else { return false }
        seekFrameOffset = max(0, min(newFrame, Int64(file.length)))

        guard let node = playerNode, isEngineRunning else {
            return true
        }

        // prewarmed but not playing 상태에서 seek 호출 가능 (게스트 seek-notify).
        // 이때 reschedule하면 의도치 않게 재생 시작됨 → seekFrameOffset만 갱신,
        // 다음 start()가 새 위치에서 scheduleAndPlay. (v0.0.44)
        guard node.isPlaying else {
            return true
        }

        node.stop()
        scheduleAndPlay(from: seekFrameOffset)
        return true
    }

    func getVirtualFrame() -> Int64 {
        guard let node = playerNode,
              let nodeTime = node.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = node.playerTime(forNodeTime: nodeTime)
        else {
            return seekFrameOffset
        }
        return seekFrameOffset + Int64(playerTime.sampleTime)
    }

    func getTimestamp() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        let outputLatency = session.outputLatency
        let ioBufDuration = session.ioBufferDuration
        // 정지 또는 timestamp 무효 시에도 virtualFrame/sampleRate/totalFrames/wallMs는
        // 유효 → ok=false라도 반환해야 호스트 UI seek바·_skipSeconds 동작 + 게스트
        // 측 fallback alignment 가능 (v0.0.43, 이전엔 ok=false만 반환했음).
        let vf = getVirtualFrame()
        let totalFrames = Int64(audioFile?.length ?? 0)
        let wallNowNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let stoppedReturn: [String: Any] = [
            "ok": false,
            "virtualFrame": vf,
            "sampleRate": sampleRate,
            "totalFrames": totalFrames,
            "wallAtFramePosNs": wallNowNs,
            "outputLatencyMs": outputLatency * 1000,
        ]

        guard let node = playerNode,
              let lastRenderTime = engine.outputNode.lastRenderTime,
              lastRenderTime.isSampleTimeValid,
              lastRenderTime.isHostTimeValid
        else {
            return stoppedReturn
        }

        let nodeLatency = node.latency
            + engine.mainMixerNode.latency
            + engine.outputNode.latency
        let totalLatency = outputLatency + ioBufDuration + nodeLatency

        let hostTime = lastRenderTime.hostTime
        let info = Self.timebaseInfo
        let timeNs = Int64(hostTime) * Int64(info.numer) / Int64(info.denom)

        let monoNowNs = Int64(mach_absolute_time()) * Int64(info.numer) / Int64(info.denom)
        let wallAtFramePosNs = wallNowNs - (monoNowNs - timeNs)

        // outputNode의 sampleTime은 세션(hw) rate로 카운트될 수 있음.
        // VF/totalFrames/sampleRate와 일관되도록 파일 rate로 정규화.
        var framePos = lastRenderTime.sampleTime
        let hwRate = session.sampleRate
        if hwRate > 0 && sampleRate > 0 && abs(hwRate - sampleRate) > 1 {
            framePos = Int64(Double(framePos) * sampleRate / hwRate)
        }

        return [
            "framePos": framePos,
            "timeNs": timeNs,
            "wallAtFramePosNs": wallAtFramePosNs,
            "ok": true,
            "virtualFrame": vf,
            "sampleRate": sampleRate,
            "totalFrames": totalFrames,
            "outputLatencyMs": outputLatency * 1000,
            "nodeLatencyMs": nodeLatency * 1000,
            "totalLatencyMs": totalLatency * 1000,
            "ioBufferDurationMs": ioBufDuration * 1000,
        ]
    }

    func setMuted(_ muted: Bool) {
        engine.mainMixerNode.outputVolume = muted ? 0.0 : 1.0
    }

    func isMuted() -> Bool {
        return engine.mainMixerNode.outputVolume == 0.0
    }

    func unload() -> Bool {
        coolDown()
        audioFile = nil
        seekFrameOffset = 0
        return true
    }

    // MARK: - Private

    private func scheduleAndPlay(from frame: Int64) {
        guard let file = audioFile, let node = playerNode else { return }
        let remaining = file.length - AVAudioFramePosition(frame)
        guard remaining > 0 else { return }
        node.scheduleSegment(
            file,
            startingFrame: AVAudioFramePosition(frame),
            frameCount: AVAudioFrameCount(remaining),
            at: nil
        )
        node.play()
    }
}
