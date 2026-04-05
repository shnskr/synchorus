import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let controller = controller {
      let channel = FlutterMethodChannel(
        name: "com.synchorus/audio_latency",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        if call.method == "getOutputLatency" {
          let session = AVAudioSession.sharedInstance()
          let outputLatencySec = session.outputLatency
          let bufferDurationSec = session.ioBufferDuration
          let outputLatencyMs = Int(outputLatencySec * 1000)
          let bufferMs = Int(bufferDurationSec * 1000)

          result([
            "outputLatencyMs": outputLatencyMs,
            "bufferMs": bufferMs,
            "totalMs": outputLatencyMs + bufferMs
          ])
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
