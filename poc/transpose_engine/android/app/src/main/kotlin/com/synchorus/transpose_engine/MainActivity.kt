package com.synchorus.transpose_engine

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.synchorus/transpose")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        NativeTranspose.nativeInit()
                        result.success(null)
                    }
                    "start" -> result.success(NativeTranspose.nativeStart())
                    "stop" -> result.success(NativeTranspose.nativeStop())
                    "setCents" -> {
                        val cents = (call.arguments as? Number)?.toInt() ?: 0
                        NativeTranspose.nativeSetCents(cents)
                        result.success(null)
                    }
                    "getCents" -> result.success(NativeTranspose.nativeGetCents())
                    "getUnderrunCount" -> result.success(NativeTranspose.nativeGetUnderrunCount())
                    else -> result.notImplemented()
                }
            }
    }
}
