import Flutter
import AppIntents
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WakeMyPcSiriSetup") {
      registrar.register(SiriSetupButtonFactory(), withId: "wake_my_pc/siri_setup_button")
    }
    SiriBridge.shared.attach(to: engineBridge.applicationRegistrar.messenger())
    if #available(iOS 16.0, *) {
      PcAppShortcuts.updateAppShortcutParameters()
    }
  }
}
