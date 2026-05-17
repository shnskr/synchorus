package com.synchorus.poc.native_audio_engine_android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.synchorus.poc/native_audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(NativeAudio.nativeStart())
                    "stop" -> result.success(NativeAudio.nativeStop())
                    "getTimestamp" -> {
                        val arr = NativeAudio.nativeGetTimestamp()
                        result.success(
                            mapOf(
                                "framePos" to arr[0],
                                "timeNs" to arr[1],
                                "wallAtFramePosNs" to arr[2],
                                "ok" to (arr[3] == 1L),
                                "virtualFrame" to arr[4],
                            )
                        )
                    }
                    "seekToFrame" -> {
                        val newFrame = (call.arguments as? Number)?.toLong()
                        if (newFrame == null) {
                            result.error("ARG", "newFrame must be a Number", null)
                        } else {
                            result.success(NativeAudio.nativeSeekToFrame(newFrame))
                        }
                    }
                    "getVirtualFrame" -> {
                        result.success(NativeAudio.nativeGetVirtualFrame())
                    }
                    // §G G-1 RingBufferEngine
                    "ringStart" -> result.success(NativeAudio.nativeRingStart())
                    "ringStop" -> result.success(NativeAudio.nativeRingStop())
                    "ringSeek" -> {
                        val newFrame = (call.arguments as? Number)?.toLong()
                        if (newFrame == null) {
                            result.error("ARG", "newFrame must be a Number", null)
                        } else {
                            result.success(NativeAudio.nativeRingSeek(newFrame))
                        }
                    }
                    "ringGetStats" -> {
                        val arr = NativeAudio.nativeRingGetStats()
                        result.success(
                            mapOf(
                                "vf" to arr[0],
                                "ringHead" to arr[1],
                                "ringTail" to arr[2],
                                "silentCount" to arr[3],
                                "decodedCount" to arr[4],
                                "seekCount" to arr[5],
                            )
                        )
                    }
                    "ringSetQueueFix" -> {
                        val enabled = (call.arguments as? Boolean) ?: true
                        NativeAudio.nativeRingSetQueueFix(enabled)
                        result.success(null)
                    }
                    "ringGetQueueFix" -> {
                        result.success(NativeAudio.nativeRingGetQueueFix())
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
