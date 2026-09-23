import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The Google Maps iOS SDK must receive its API key through
    // GMSServices.provideAPIKey before any GMSMapView exists. The Flutter
    // plugin (google_maps_flutter_ios) only calls +sharedServices, which
    // raises NSException when no key has been provided. The value is read
    // from the GMSApiKey Info.plist slot that .github/workflows/ios-release.yml
    // injects at build time from the GOOGLE_MAPS_API_KEY secret. Never
    // hardcode a real key here. An empty or missing key (e.g. a local dev
    // build without CI injection) skips initialization; the plugin then
    // surfaces its own missing-key error on the first map instead.
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsApiKey.isEmpty {
      GMSServices.provideAPIKey(mapsApiKey)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
