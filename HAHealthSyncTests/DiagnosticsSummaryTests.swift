import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class DiagnosticsSummaryTests: XCTestCase {
  func testIncludedRowsAreAllowlistedAndValueFree() {
    let rows = DiagnosticsSummary.included(
      DiagnosticsSummaryInput(
        appVersion: "1.0",
        buildVersion: "42",
        osVersion: "iOS 26.5",
        integrationVersion: "1.2.1",
        backgroundSyncEnabled: true,
        backgroundSyncFrequency: .balanced,
        historicalImportEnabled: false,
        medicationSyncEnabled: false,
        selectedMetricCount: 3,
        pairingCount: 2,
        registrationCount: 2,
        recentEventCount: 5,
        lastAttemptedAt: Date(timeIntervalSince1970: 1_788_035_400),
        lastSuccessfulAt: Date(timeIntervalSince1970: 1_788_035_400),
        failureCategories: [.offline]
      )
    )
    let text = rows.map { "\($0.label):\($0.value)" }.joined(separator: "\n")

    XCTAssertTrue(text.contains("Selected metrics:3"))
    XCTAssertTrue(text.contains("Background interval:Balanced"))
    XCTAssertFalse(text.contains("https://"))
    XCTAssertFalse(text.contains("sensor."))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("secret"))
    XCTAssertFalse(text.contains("8421"))
  }
}
