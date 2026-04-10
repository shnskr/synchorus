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
                    else -> result.notImplemented()
                }
            }
    }
}
