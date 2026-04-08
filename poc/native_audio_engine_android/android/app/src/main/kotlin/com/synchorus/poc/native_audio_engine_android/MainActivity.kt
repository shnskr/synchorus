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
                                "ok" to (arr[2] == 1L),
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
