import Flutter
import Foundation
import StoreKit
import UIKit

enum StoreUpdates {
  static func info(_ result: @escaping FlutterResult) {
    let bundle = Bundle.main
    guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      let packageName = bundle.bundleIdentifier,
      !version.isEmpty, !build.isEmpty, !packageName.isEmpty
    else {
      result(FlutterError(code: "package_info", message: "Installed app information is unavailable.", details: nil))
      return
    }
    #if DEBUG || targetEnvironment(simulator)
    let development = true
    #else
    let development = false
    #endif
    let receipt = bundle.appStoreReceiptURL
    let storeInstallation = installationSource(
      development: development,
      receiptName: receipt?.lastPathComponent,
      receiptExists: receipt.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    )
    var info: [String: Any] = [
      "version": version,
      "build": build,
      "packageName": packageName,
      "platform": "ios",
      "osVersion": UIDevice.current.systemVersion,
    ]
    if let storeInstallation { info["storeInstallation"] = storeInstallation }
    result(info)
  }

  static func country(_ result: @escaping FlutterResult) {
    // The Apple account's storefront is authoritative; device language/region is not.
    // Storefront.current avoids SKPaymentQueue.storefront's blocking main-thread access.
    Task { @MainActor in
      let storefront = await Storefront.current
      result(storefront.flatMap { StorefrontCountry.alpha2($0.countryCode) })
    }
  }

  static func installationSource(
    development: Bool,
    receiptName: String?,
    receiptExists: Bool
  ) -> Bool? {
    if development || receiptName == "sandboxReceipt" { return false }
    if receiptName == "receipt" && receiptExists { return true }
    // A missing receipt can occur even for an App Store download. Keep this unknown;
    // do not refresh receipts or prompt for an Apple account merely to check updates.
    return nil
  }
}
