import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class AppIntentPrivacyTests: XCTestCase {
  func testSuccessDialogueContainsOnlyMetricCount() {
    let text = AppIntentResultMessage.text(
      for: .init(succeeded: true, synchronizedMetricCount: 12, failureCategory: nil)
    )

    XCTAssertEqual(text, "Synced 12 metrics.")
    assertPrivateFixtureDataAbsent(from: text)
  }

  func testSuccessDialogueIncludesOnlyPairingCount() {
    let text = AppIntentResultMessage.text(
      for: .init(
        succeeded: true,
        synchronizedMetricCount: 2,
        synchronizedPairingCount: 1,
        failureCategory: nil
      )
    )

    XCTAssertEqual(text, "Synced 2 metrics and 1 pairing.")
    assertPrivateFixtureDataAbsent(from: text)
  }

  func testFailureDialogueUsesOnlyPublicCategory() {
    let text = AppIntentResultMessage.text(
      for: .init(
        succeeded: false,
        synchronizedMetricCount: 0,
        failureCategory: .unauthorized
      )
    )

    XCTAssertEqual(text, "Sync failed: Home Assistant authentication.")
    assertPrivateFixtureDataAbsent(from: text)
  }

  func testNothingNewIsACalmSuccess() {
    let text = AppIntentResultMessage.text(
      for: .init(succeeded: true, synchronizedMetricCount: 0, failureCategory: nil)
    )

    XCTAssertEqual(text, "Nothing new to sync.")
  }

  func testLockedDeviceExplainsUnlockAndImports() {
    XCTAssertEqual(
      AppIntentResultMessage.text(
        for: .init(succeeded: false, synchronizedMetricCount: 0, failureCategory: .deviceLocked)
      ),
      "Unlock iPhone to read Apple Health."
    )
    XCTAssertEqual(
      AppIntentResultMessage.text(
        for: .init(
          succeeded: false,
          synchronizedMetricCount: 0,
          synchronizedPairingCount: 2,
          failureCategory: .deviceLocked
        )
      ),
      "Unlock iPhone to read Apple Health. Home Assistant imports still ran."
    )
  }

  func testPurchaseRequiredDialogueNamesInAppUnlockWithoutPrivateData() {
    let text = AppIntentResultMessage.text(
      for: .init(
        succeeded: false, synchronizedMetricCount: 0, failureCategory: nil,
        requiresPurchase: true
      )
    )

    XCTAssertTrue(text.localizedCaseInsensitiveContains("unlock"))
    XCTAssertTrue(text.localizedCaseInsensitiveContains("app"))
    assertPrivateFixtureDataAbsent(from: text)
  }

  private func assertPrivateFixtureDataAbsent(from text: String) {
    XCTAssertFalse(text.contains("fixture-secret"))
    XCTAssertFalse(text.contains("fixture-token"))
    XCTAssertFalse(text.contains("ha.example.com"))
    XCTAssertFalse(text.contains("8421"))
  }
}
