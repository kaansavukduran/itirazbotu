import Flutter
import Foundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Geçmiş ve içe aktarılan modeller App Support içindedir. Cihazın sistem
    // yedeklemesi de bu verileri iCloud'a taşımamalı.
    do {
      var support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try support.setResourceValues(values)
    } catch {
      NSLog("İtiraz Botu: yerel veri dizininin yedekleme tercihi ayarlanamadı.")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
