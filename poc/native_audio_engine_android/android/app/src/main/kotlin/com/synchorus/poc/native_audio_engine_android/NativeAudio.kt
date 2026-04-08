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
}
