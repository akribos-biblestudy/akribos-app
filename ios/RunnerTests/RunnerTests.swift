import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testStorefrontUsesActualCountryInsteadOfLanguage() {
    for (source, expected) in [
      "DEU": "DE", "AUT": "AT", "CHE": "CH", "USA": "US",
      "GBR": "GB", "JPN": "JP", "KOR": "KR", "XKS": "XK",
    ] {
      XCTAssertEqual(StorefrontCountry.alpha2(source), expected)
    }
    XCTAssertNil(StorefrontCountry.alpha2("DDD"))
    XCTAssertNil(StorefrontCountry.alpha2("de-DE"))
    XCTAssertNil(StorefrontCountry.alpha2(""))
  }

  func testSandboxAndDevelopmentDoNotAdvertisePublicStoreUpdates() {
    XCTAssertEqual(StoreUpdates.installationSource(
      development: true, receiptName: "receipt", receiptExists: true
    ), false)
    XCTAssertEqual(StoreUpdates.installationSource(
      development: false, receiptName: "sandboxReceipt", receiptExists: true
    ), false)
    XCTAssertEqual(StoreUpdates.installationSource(
      development: false, receiptName: "receipt", receiptExists: true
    ), true)
    XCTAssertNil(StoreUpdates.installationSource(
      development: false, receiptName: nil, receiptExists: false
    ))
    XCTAssertNil(StoreUpdates.installationSource(
      development: false, receiptName: "receipt", receiptExists: false
    ))
  }

}
