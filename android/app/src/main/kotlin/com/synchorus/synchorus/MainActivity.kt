package com.synchorus.synchorus

import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // v3: 네이티브 Oboe 오디오 엔진 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.synchorus/native_audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "loadFile" -> {
                        val path = call.arguments as? String
                        if (path == null) {
                            result.error("ARG", "path must be a String", null)
                        } else {
                            // 백그라운드 스레드에서 디코딩 (메인 스레드 블로킹 방지)
                            val mainHandler = Handler(Looper.getMainLooper())
                            Thread {
                                val ok = NativeAudio.nativeLoadFile(path)
                                if (ok) {
                                    mainHandler.post { result.success(true) }
                                } else {
                                    val err = NativeAudio.nativeGetLastError()
                                    mainHandler.post { result.error("LOAD_FAILED", err, null) }
                                }
                            }.start()
                        }
                    }
                    "start" -> result.success(NativeAudio.nativeStart())
                    "stop" -> result.success(NativeAudio.nativeStop())
                    "getTimestamp" -> {
                        val arr = NativeAudio.nativeGetTimestamp()
                        // arr[7]는 outputLatencyMs를 micro 단위 long으로 인코딩한 값.
                        // -1L은 미지원/측정 불가 → null로 변환해 Dart sanity check에 위임.
                        val outLatMs: Double? =
                            if (arr[7] < 0) null else arr[7] / 1000.0
                        result.success(
                            mapOf(
                                "framePos" to arr[0],
                                "timeNs" to arr[1],
                                "wallAtFramePosNs" to arr[2],
                                "ok" to (arr[3] == 1L),
                                "virtualFrame" to arr[4],
                                "sampleRate" to arr[5],
                                "totalFrames" to arr[6],
                                "outputLatencyMs" to outLatMs,
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
                    "setMuted" -> {
                        val muted = call.arguments as? Boolean ?: false
                        NativeAudio.nativeSetMuted(muted)
                        result.success(null)
                    }
                    "isMuted" -> {
                        result.success(NativeAudio.nativeIsMuted())
                    }
                    "unload" -> result.success(NativeAudio.nativeUnload())
                    else -> result.notImplemented()
                }
            }
    }
}
