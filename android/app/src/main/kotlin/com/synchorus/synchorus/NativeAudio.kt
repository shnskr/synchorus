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
    external fun nativeScheduleStart(wallEpochMs: Long, fromFrame: Long): Boolean
    external fun nativeCancelSchedule(): Boolean
    external fun nativeGetTimestamp(): LongArray
    external fun nativeSeekToFrame(newFrame: Long): Boolean
    external fun nativeGetVirtualFrame(): Long
    external fun nativeSetMuted(muted: Boolean)
    external fun nativeIsMuted(): Boolean
    external fun nativeUnload(): Boolean
}
