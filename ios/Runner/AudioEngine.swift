import AVFoundation

/// AVAudioEngine + AVAudioPlayerNode 기반 오디오 파일 재생.
/// step 1-1(비프 생성)에서 step 1-2(파일 재생)으로 전환.
class AudioEngine {
    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?

    // §H Transpose 노드. node → timePitch → mainMixer.
    private let timePitch = AVAudioUnitTimePitch()
    private var timePitchAttached = false
    private var pitchCents: Int = 0
    private var playbackSpeedX1000: Int = 1000

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

        // §H/§I 파일 변경 시 transpose/speed default 강제 reset (HISTORY (110)).
        // 호출 측이 reset 잊더라도 native가 깨끗한 default로 시작 — 안전망.
        // AVAudioUnitTimePitch.pitch/rate도 직접 0/1.0으로 강제.
        pitchCents = 0
        playbackSpeedX1000 = 1000
        timePitch.pitch = 0
        timePitch.rate = 1.0

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
            if !timePitchAttached {
                engine.attach(timePitch)
                timePitchAttached = true
            }
            engine.connect(node, to: timePitch, format: file.processingFormat)
            engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
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
        // v0.0.114: Android(oboe)와 달리 vf(getVirtualFrame=playerNode lastRenderTime)와
        // framePos/timeNs(outputNode lastRenderTime)가 같은 렌더 사이클 시각이라 시점
        // 정합됨 → Android의 virtualFrame→timeNs 정렬 보정이 iOS엔 불필요(vfDiff 톱니 무발생).
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

        // v0.0.115 monotonic 전환: timeNs를 BOOTTIME 대응(mach_continuous_time) 도메인으로.
        // AVAudioTime.hostTime은 mach_absolute_time(sleep 멈춤) 고정이라, sleep 누적분
        // (continuous - absolute)을 더해 continuous로 올린다 → Android의 timeNs(CLOCK_BOOTTIME)와
        // 같은 의미. 재생 중엔 sleep 없어 bootDelta가 안정 상수. wall(REALTIME)은 NTP 점프에
        // 취약(측정3 root cause)이라 정렬 기준에서 빼고 검증 대조용으로만 병행 출력.
        // 상세: docs/SYNC_REDESIGN.md (130).
        let hostTime = lastRenderTime.hostTime
        let info = Self.timebaseInfo
        let absNowTicks = mach_absolute_time()
        let contNowTicks = mach_continuous_time()
        // sleep 누적분(ns). contNow >= absNow 항상이라 &-는 안전.
        let bootDeltaNs = Int64(contNowTicks &- absNowTicks) * Int64(info.numer) / Int64(info.denom)
        // hostTime(absolute @ framePos)을 ns로 변환 후 continuous 도메인으로 올림.
        let timeNs = Int64(hostTime) * Int64(info.numer) / Int64(info.denom) + bootDeltaNs

        // 검증 병행 wall. bootNow·timeNs 둘 다 continuous라 (bootNow-timeNs)는 순수 HAL 지연
        // → wallNow에서 빼 wall 시각 역산(대조용). 게스트 정렬은 timeNs(continuous) 직접 사용.
        let bootNowNs = Int64(contNowTicks) * Int64(info.numer) / Int64(info.denom)
        let wallAtFramePosNs = wallNowNs - (bootNowNs - timeNs)

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

    /// §H Transpose: cents 단위 pitch shift. ±2400 cents 범위.
    func setSemitoneCents(_ cents: Int) {
        let clamped = max(-2400, min(2400, cents))
        pitchCents = clamped
        timePitch.pitch = Float(clamped)
    }

    func getSemitoneCents() -> Int {
        return pitchCents
    }

    /// §I 속도. 정수 x1000 (500~2000 = 0.5x~2.0x). pitch 유지.
    func setPlaybackSpeedX1000(_ speedX1000: Int) {
        let clamped = max(500, min(2000, speedX1000))
        playbackSpeedX1000 = clamped
        timePitch.rate = Float(clamped) / 1000.0
    }

    func getPlaybackSpeedX1000() -> Int {
        return playbackSpeedX1000
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
