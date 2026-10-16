import Flutter
import UIKit
import WebKit

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
    let channel = FlutterMethodChannel(
      name: "de.akribos.app/editor-session",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setSession" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
        let origin = arguments["origin"] as? String,
        let components = URLComponents(string: origin),
        let url = components.url, let host = components.host, !host.isEmpty
      else {
        result(FlutterError(code: "invalid_session", message: "Invalid editor session configuration.", details: nil))
        return
      }
      #if DEBUG
      let development = ["localhost", "127.0.0.1", "::1", "[::1]", "10.0.2.2"].contains(host)
      #else
      let development = false
      #endif
      let session = arguments["session"] as? String
      guard components.user == nil, components.password == nil,
        components.query == nil, components.fragment == nil,
        components.path.isEmpty || components.path == "/",
        components.scheme == "https" || (development && components.scheme == "http"),
        session == nil || (!session!.isEmpty && session!.unicodeScalars.allSatisfy {
          $0.value >= 0x21 && $0.value <= 0x7e && !"\";,\\".unicodeScalars.contains($0)
        })
      else {
        result(FlutterError(code: "invalid_session", message: "Invalid editor session configuration.", details: nil))
        return
      }
      let store = WKWebsiteDataStore.default()
      store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
        guard let session else {
          result(nil)
          return
        }
        // Parsing a Set-Cookie header against this exact URL omits Domain and
        // preserves host-only semantics; HttpOnly is never assigned in JavaScript.
        let secure = components.scheme == "https" ? "; Secure" : ""
        let header = "session=\(session); Path=/; HttpOnly; SameSite=Lax\(secure)"
        guard let cookie = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url).first,
          cookie.isHTTPOnly, cookie.path == "/", cookie.domain == host,
          cookie.isSecure == (components.scheme == "https")
        else {
          result(FlutterError(code: "session_rejected", message: "Editor session was not accepted.", details: nil))
          return
        }
        store.httpCookieStore.setCookie(cookie) {
          result(nil)
        }
      }
    }
  }
}
