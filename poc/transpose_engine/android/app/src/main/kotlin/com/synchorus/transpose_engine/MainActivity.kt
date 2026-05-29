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
                    else -> result.notImplemented()
                }
            }
    }
}
