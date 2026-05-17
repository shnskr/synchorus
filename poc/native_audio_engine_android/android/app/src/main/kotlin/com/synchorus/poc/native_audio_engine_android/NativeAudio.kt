package com.synchorus.poc.native_audio_engine_android

/**
 * PoC Phase 0: native Oboe 엔진 JNI 래퍼.
 * Flutter MethodChannel 핸들러(MainActivity)에서만 호출.
 */
object NativeAudio {
    init {
        System.loadLibrary("oboe_engine")
    }

    external fun nativeStart(): Boolean
    external fun nativeStop(): Boolean

    /**
     * [0]=framePos,
     * [1]=timeNanoseconds (CLOCK_MONOTONIC, Oboe 내부 DAC 타임스탬프),
     * [2]=wallAtFramePosNs (CLOCK_REALTIME, framePos가 DAC에 나간 순간의 wall clock),
     * [3]=ok (1|0)
     */
    external fun nativeGetTimestamp(): LongArray

    /** Phase 4: virtual playhead seek. 성공 시 true. */
    external fun nativeSeekToFrame(newFrame: Long): Boolean

    /** Phase 4: 현재 virtual playhead 값 (= "다음 콜백이 만들 프레임 번호"). */
    external fun nativeGetVirtualFrame(): Long

    // ─────────── §G G-1 RingBufferEngine (race 격리 검증용) ───────────
    /** Ring buffer 엔진 시작 (별도 stream, 기존 OboeEngine과 독립). */
    external fun nativeRingStart(): Boolean

    /** Ring buffer 엔진 정지 + decode thread join. */
    external fun nativeRingStop(): Boolean

    /** Ring buffer seek. v0.0.76 race 모델 그대로 (큐 모델 fix 전). */
    external fun nativeRingSeek(newFrame: Long): Boolean

    /**
     * Ring buffer 진단 stats.
     * [0]=vf, [1]=ringHead, [2]=ringTail, [3]=silentCount, [4]=decodedCount, [5]=seekCount
     * silent/decoded = onAudioReady에서 매 frame read마다 누적. ratio로 무음 비율 판정.
     */
    external fun nativeRingGetStats(): LongArray

    /** Race(v0.0.76) vs 큐 모델 fix 토글. true=fix, false=race. */
    external fun nativeRingSetQueueFix(enabled: Boolean)

    /** 현재 큐 모델 fix 활성화 여부 반환. */
    external fun nativeRingGetQueueFix(): Boolean
}
