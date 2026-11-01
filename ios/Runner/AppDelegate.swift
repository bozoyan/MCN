import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DirectorStorage") else { return }
    let channel = FlutterMethodChannel(name: "ai.reveric.director/storage", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "availableBytes", let args = call.arguments as? [String: Any], let path = args["path"] as? String else { result(FlutterMethodNotImplemented); return }
      do {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
        guard let bytes = attrs[.systemFreeSize] as? NSNumber else { throw NSError(domain: "storage_probe_failed", code: 1) }
        result(bytes.int64Value)
      } catch { result(FlutterError(code: "storage_probe_failed", message: "Unable to query private volume", details: nil)) }
    }
  }
}
