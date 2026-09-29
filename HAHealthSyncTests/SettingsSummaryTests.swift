import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class SettingsSummaryTests: XCTestCase {
  func testConfiguredConnectionUsesHostWithoutCredentialsOrPath() {
    let configuration = AppConfiguration(
      baseURL: "https://home.example.test:8123/api/private",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps],
      backgroundSyncEnabled: true
    )

    XCTAssertEqual(SettingsSummary.connectionStatus(configuration), "Configured")
    XCTAssertEqual(SettingsSummary.server(configuration), "home.example.test")
  }

  func testDirectionSummariesUseOnlyCountsAndFeatureState() {
    XCTAssertEqual(
      SettingsSummary.export(selectedMetrics: 3, medicationEnabled: true),
      "3 metrics · Medications on"
    )
    XCTAssertEqual(SettingsSummary.importSummary(pairingCount: 2), "2 pairings")
    XCTAssertEqual(SettingsSummary.importSummary(pairingCount: 1), "1 pairing")
  }

  func testBlankAndMalformedConnectionsRemainNonSensitive() {
    XCTAssertEqual(SettingsSummary.connectionStatus(.default), "Not configured")
    var malformed = AppConfiguration.default
    malformed.baseURL = "not a URL"
    malformed.healthBridgeUserID = "example-user"
    XCTAssertEqual(SettingsSummary.server(malformed), "Server unavailable")
  }
}
