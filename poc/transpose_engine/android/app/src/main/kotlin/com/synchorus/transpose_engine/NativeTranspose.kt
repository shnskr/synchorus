package com.synchorus.transpose_engine

object NativeTranspose {
    init {
        System.loadLibrary("transpose_engine")
    }

    external fun nativeInit()
    external fun nativeStart(): Boolean
    external fun nativeStop(): Boolean
    external fun nativeSetCents(cents: Int)
    external fun nativeGetCents(): Int
    external fun nativeGetUnderrunCount(): Int
}
