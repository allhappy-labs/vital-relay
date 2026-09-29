import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ConnectionFormPolicyTests: XCTestCase {
  func testSettingsDraftPreservesNonConnectionConfiguration() {
    let existing = AppConfiguration(
      baseURL: "https://old.example.test",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "old-user",
      selectedMetrics: [.steps],
      backgroundSyncEnabled: true,
      backgroundSyncFrequency: .batterySaver,
      experimentalBackfillEnabled: true,
      medicationSyncEnabled: true
    )
    let draft = ConnectionDraft(
      baseURL: "https://new.example.test",
      userID: "new-user",
      webhookSecret: "",
      accessToken: "",
      allowsLocalHTTP: false
    )

    let updated = draft.configuration(preserving: existing)

    XCTAssertEqual(updated.baseURL, "https://new.example.test")
    XCTAssertEqual(updated.selectedMetrics, [.steps])
    XCTAssertTrue(updated.backgroundSyncEnabled)
    XCTAssertEqual(updated.backgroundSyncFrequency, .batterySaver)
    XCTAssertTrue(updated.experimentalBackfillEnabled)
    XCTAssertTrue(updated.medicationSyncEnabled)
  }

  func testClearingSecretsDoesNotClearNonSecretFields() {
    var draft = ConnectionDraft(
      baseURL: "https://example.test",
      userID: "example-user",
      webhookSecret: "webhook-value",
      accessToken: "token-value",
      allowsLocalHTTP: false
    )
    draft.clearSecrets()
    XCTAssertEqual(draft.webhookSecret, "")
    XCTAssertEqual(draft.accessToken, "")
    XCTAssertEqual(draft.baseURL, "https://example.test")
    XCTAssertEqual(draft.userID, "example-user")
  }

  func testOnboardingRequiresBothConnectionTestsToSucceed() {
    XCTAssertFalse(
      ConnectionFormPolicy.canSave(
        mode: .onboarding,
        baseURL: "https://ha.example.com",
        userID: "oleh",
        webhookSecret: "secret",
        accessToken: "token",
        webhookState: .failed(.offline),
        authenticatedState: .succeeded
      )
    )
    XCTAssertFalse(
      ConnectionFormPolicy.canSave(
        mode: .onboarding,
        baseURL: "https://ha.example.com",
        userID: "oleh",
        webhookSecret: "secret",
        accessToken: "token",
        webhookState: .succeeded,
        authenticatedState: .failed(.unauthorized)
      )
    )
    XCTAssertTrue(
      ConnectionFormPolicy.canSave(
        mode: .onboarding,
        baseURL: "https://ha.example.com",
        userID: "oleh",
        webhookSecret: "secret",
        accessToken: "token",
        webhookState: .succeeded,
        authenticatedState: .succeeded
      )
    )
  }

  func testSettingsCanSaveWithoutRepeatingConnectionTests() {
    XCTAssertTrue(
      ConnectionFormPolicy.canSave(
        mode: .settings,
        baseURL: "https://ha.example.com",
        userID: "oleh",
        webhookSecret: "",
        accessToken: "",
        webhookState: .notTested,
        authenticatedState: .notTested
      )
    )
  }

  func testNetworkAndTokenFailuresHaveDistinctMessages() {
    XCTAssertEqual(
      ConnectionFailurePresentation.message(for: .offline, context: .authenticatedAPI),
      "Network error: This iPhone is offline."
    )
    XCTAssertEqual(
      ConnectionFailurePresentation.message(for: .unauthorized, context: .authenticatedAPI),
      "Token error: Home Assistant rejected the long-lived access token."
    )
    XCTAssertEqual(
      ConnectionFailurePresentation.message(for: .unauthorized, context: .webhook),
      "Webhook secret error: Health Bridge rejected the webhook secret."
    )
  }
}
