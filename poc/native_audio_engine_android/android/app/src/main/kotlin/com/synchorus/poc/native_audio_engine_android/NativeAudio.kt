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
}
