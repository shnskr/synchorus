package com.synchorus.synchorus

object NativeAudio {
    init {
        System.loadLibrary("oboe_engine")
    }

    external fun nativeStart(): Boolean
    external fun nativeStop(): Boolean
    external fun nativeGetTimestamp(): LongArray
    external fun nativeSeekToFrame(newFrame: Long): Boolean
    external fun nativeGetVirtualFrame(): Long
}
