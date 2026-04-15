package com.synchorus.synchorus

import android.media.AudioManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 기존: 오디오 지연 측정 채널 (v2 legacy)
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

        // v3: 네이티브 Oboe 오디오 엔진 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.synchorus/native_audio")
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
