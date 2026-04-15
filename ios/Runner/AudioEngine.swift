import AVFoundation
import os

/// AVAudioEngine wrapper — PoC에서 검증 완료, 본체 앱으로 이식.
/// 현재: 음계 비프 생성. 추후: 오디오 파일 디코딩 재생으로 교체.
class AudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private var sampleRate: Double = 48000
    private var _virtualFrame: Int64 = 0
    private let lockPtr: UnsafeMutablePointer<os_unfair_lock>

    private static let noteFrequencies: [Float] = [
        261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88, 523.25,
    ]
    private static let beepPeriodSec: Float = 1.0
    private static let beepDurationSec: Float = 0.1
    private static let beepFadeSec: Float = 0.005
    private static let amplitude: Float = 0.3

    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    init() {
        lockPtr = .allocate(capacity: 1)
        lockPtr.initialize(to: os_unfair_lock())
    }

    deinit {
        lockPtr.deinitialize(count: 1)
        lockPtr.deallocate()
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(lockPtr)
        defer { os_unfair_lock_unlock(lockPtr) }
        return body()
    }

    func start() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            let hwRate = session.sampleRate
            sampleRate = hwRate
            print("[AudioEngine] hw sampleRate=\(hwRate), ioBufferDuration=\(session.ioBufferDuration), outputLatency=\(session.outputLatency)")

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: hwRate, channels: 2
            ) else { return false }

            let beepPeriodFrames = Int(Self.beepPeriodSec * Float(sampleRate))
            let beepDurationFrames = Int(Self.beepDurationSec * Float(sampleRate))
            let beepFadeFrames = Int(Self.beepFadeSec * Float(sampleRate))
            let noteFreqs = Self.noteFrequencies
            let amp = Self.amplitude
            let sr = Float(sampleRate)

            sourceNode = AVAudioSourceNode(format: format) {
                [weak self] isSilence, _, frameCount, audioBufferList -> OSStatus in

                guard let self = self else {
                    let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                    for buffer in abl { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
                    isSilence.pointee = ObjCBool(true)
                    return noErr
                }

                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)

                os_unfair_lock_lock(self.lockPtr)
                var vf = self._virtualFrame
                os_unfair_lock_unlock(self.lockPtr)

                for frame in 0..<Int(frameCount) {
                    let currentVf = vf + Int64(frame)
                    let mod = Int(currentVf % Int64(beepPeriodFrames))

                    var sample: Float = 0.0
                    if mod < beepDurationFrames {
                        let beatIndex = Int(
                            (currentVf - Int64(mod)) / Int64(beepPeriodFrames))
                        let noteIdx = beatIndex % 8
                        let freq = noteFreqs[noteIdx]
                        let phase = 2.0 * Float.pi * freq * Float(mod) / sr

                        var env: Float = 1.0
                        if mod < beepFadeFrames {
                            env = Float(mod) / Float(beepFadeFrames)
                        } else if mod >= beepDurationFrames - beepFadeFrames {
                            env = Float(beepDurationFrames - mod) / Float(beepFadeFrames)
                        }
                        sample = sinf(phase) * amp * env
                    }

                    for buffer in abl {
                        buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = sample
                    }
                }

                os_unfair_lock_lock(self.lockPtr)
                self._virtualFrame = vf + Int64(frameCount)
                os_unfair_lock_unlock(self.lockPtr)

                return noErr
            }

            engine.attach(sourceNode!)
            engine.connect(sourceNode!, to: engine.mainMixerNode, format: format)

            withLock { _virtualFrame = 0 }

            try engine.start()
            return true
        } catch {
            print("[AudioEngine] start error: \(error)")
            return false
        }
    }

    func stop() -> Bool {
        engine.stop()
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }
        return true
    }

    func getTimestamp() -> [String: Any] {
        guard let lastRenderTime = engine.outputNode.lastRenderTime,
              lastRenderTime.isSampleTimeValid,
              lastRenderTime.isHostTimeValid
        else {
            return ["ok": false]
        }

        let session = AVAudioSession.sharedInstance()
        let outputLatency = session.outputLatency
        let ioBufDuration = session.ioBufferDuration
        let nodeLatency = (sourceNode?.latency ?? 0)
            + engine.mainMixerNode.latency
            + engine.outputNode.latency
        let totalLatency = outputLatency + ioBufDuration + nodeLatency
        let latencyFrames = Int64(totalLatency * sampleRate)
        let framePos = lastRenderTime.sampleTime - latencyFrames

        let hostTime = lastRenderTime.hostTime

        let info = Self.timebaseInfo
        let timeNs =
            Int64(hostTime) * Int64(info.numer) / Int64(info.denom)

        let monoNowNs =
            Int64(mach_absolute_time()) * Int64(info.numer) / Int64(info.denom)
        let wallNowNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let wallAtFramePosNs = wallNowNs - (monoNowNs - timeNs)

        let vf = withLock { _virtualFrame }

        return [
            "framePos": framePos,
            "timeNs": timeNs,
            "wallAtFramePosNs": wallAtFramePosNs,
            "ok": true,
            "virtualFrame": vf,
            "sampleRate": sampleRate,
            "outputLatencyMs": outputLatency * 1000,
            "nodeLatencyMs": nodeLatency * 1000,
            "totalLatencyMs": totalLatency * 1000,
            "ioBufferDurationMs": ioBufDuration * 1000,
        ]
    }

    func seekToFrame(_ newFrame: Int64) -> Bool {
        withLock { _virtualFrame = newFrame }
        return true
    }

    func getVirtualFrame() -> Int64 {
        return withLock { _virtualFrame }
    }
}
