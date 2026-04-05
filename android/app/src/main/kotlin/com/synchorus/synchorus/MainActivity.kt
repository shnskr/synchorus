package com.synchorus.synchorus

import android.media.AudioManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.synchorus/audio_latency")
            .setMethodCallHandler { call, result ->
                if (call.method == "getOutputLatency") {
                    val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
                    val latencyStr = audioManager.getProperty("android.media.property.OUTPUT_LATENCY")
                    val framesStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
                    val sampleRateStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)

                    val latencyMs = latencyStr?.toIntOrNull() ?: 0
                    val framesPerBuffer = framesStr?.toIntOrNull() ?: 0
                    val sampleRate = sampleRateStr?.toIntOrNull() ?: 44100

                    // 버퍼 레이턴시 = framesPerBuffer / sampleRate * 1000
                    val bufferMs = if (sampleRate > 0) (framesPerBuffer * 1000.0 / sampleRate).toInt() else 0

                    result.success(mapOf(
                        "outputLatencyMs" to latencyMs,
                        "bufferMs" to bufferMs,
                        "totalMs" to (latencyMs + bufferMs)
                    ))
                } else {
                    result.notImplemented()
                }
            }
    }
}
