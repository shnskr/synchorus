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

    func start() -> Bool {
        if isEngineRunning { return true }
        guard let file = audioFile else {
            print("[AudioEngine] start: no file loaded")
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            let hwRate = session.sampleRate
            print("[AudioEngine] hw sr=\(hwRate), file sr=\(sampleRate), ioBuf=\(session.ioBufferDuration), outLatency=\(session.outputLatency)")

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

    @discardableResult
    func stop() -> Bool {
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
        guard let node = playerNode,
              let lastRenderTime = engine.outputNode.lastRenderTime,
              lastRenderTime.isSampleTimeValid,
              lastRenderTime.isHostTimeValid
        else {
            return ["ok": false]
        }

        let session = AVAudioSession.sharedInstance()
        let outputLatency = session.outputLatency
        let ioBufDuration = session.ioBufferDuration
        let nodeLatency = node.latency
            + engine.mainMixerNode.latency
            + engine.outputNode.latency
        let totalLatency = outputLatency + ioBufDuration + nodeLatency

        let hostTime = lastRenderTime.hostTime
        let info = Self.timebaseInfo
        let timeNs = Int64(hostTime) * Int64(info.numer) / Int64(info.denom)

        let monoNowNs = Int64(mach_absolute_time()) * Int64(info.numer) / Int64(info.denom)
        let wallNowNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let wallAtFramePosNs = wallNowNs - (monoNowNs - timeNs)

        let vf = getVirtualFrame()
        let totalFrames = Int64(audioFile?.length ?? 0)

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
        if isEngineRunning { stop() }
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
