package com.synchorus.transpose_engine

object NativeTranspose {
    init {
        System.loadLibrary("transpose_engine")
    }

    external fun nativeInit()
}
