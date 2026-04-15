import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private let audioEngine = AudioEngine()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        let messenger = engineBridge.applicationRegistrar.messenger()
        let channel = FlutterMethodChannel(
            name: "com.synchorus/native_audio",
            binaryMessenger: messenger
        )

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "start":
                result(self.audioEngine.start())
            case "stop":
                result(self.audioEngine.stop())
            case "getTimestamp":
                result(self.audioEngine.getTimestamp())
            case "seekToFrame":
                guard let newFrame = (call.arguments as? NSNumber)?.int64Value
                else {
                    result(
                        FlutterError(
                            code: "BAD_ARGS", message: "newFrame required",
                            details: nil))
                    return
                }
                result(self.audioEngine.seekToFrame(newFrame))
            case "getVirtualFrame":
                result(self.audioEngine.getVirtualFrame())
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
