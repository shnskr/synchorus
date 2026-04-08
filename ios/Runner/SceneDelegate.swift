import AVFoundation
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.synchorus/audio_latency",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        if call.method == "getOutputLatency" {
          let session = AVAudioSession.sharedInstance()
          // Android는 OS API 한계로 outputLatency를 못 잡고 buffer만 잡음.
          // 양쪽 측정 방식을 맞추기 위해 iOS도 bufferMs만 totalMs에 반영.
          // outputLatencyMs는 디버깅 표시용으로 함께 전송.
          let outputLatencySec = session.outputLatency
          let bufferDurationSec = session.ioBufferDuration
          let outputLatencyMs = Int(outputLatencySec * 1000)
          let bufferMs = Int(bufferDurationSec * 1000)

          result([
            "outputLatencyMs": outputLatencyMs,
            "bufferMs": bufferMs,
            "totalMs": bufferMs
          ])
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
