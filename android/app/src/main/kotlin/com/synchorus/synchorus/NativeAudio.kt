package com.synchorus.synchorus

object NativeAudio {
    init {
        System.loadLibrary("oboe_engine")
    }

    external fun nativeLoadFile(path: String): Boolean
    external fun nativeGetLastError(): String
    external fun nativePrewarm(): Boolean
    external fun nativeCoolDown(): Boolean
    external fun nativeStart(): Boolean
    external fun nativeStop(): Boolean
    external fun nativeGetTimestamp(): LongArray
    external fun nativeSeekToFrame(newFrame: Long): Boolean
    external fun nativeGetVirtualFrame(): Long
    external fun nativeSetMuted(muted: Boolean)
    external fun nativeIsMuted(): Boolean
    external fun nativeUnload(): Boolean
    external fun nativeReopenStream(): Boolean
    external fun nativeSetDebugForceStuck(stuck: Boolean)
    external fun nativeSetSemitoneCents(cents: Int)
    external fun nativeGetSemitoneCents(): Int
    external fun nativeSetPlaybackSpeedX1000(speedX1000: Int)
    external fun nativeGetPlaybackSpeedX1000(): Int
}
