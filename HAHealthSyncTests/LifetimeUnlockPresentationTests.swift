import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class LifetimeUnlockPresentationTests: XCTestCase {
  func testMissingProductOffersRetryWithoutRequiringRestore() {
    XCTAssertTrue(LifetimeUnlockPresentation(state: .unavailable, displayPrice: nil).offersRetry)
    XCTAssertFalse(LifetimeUnlockPresentation(state: .locked, displayPrice: "CHF 9.00").offersRetry)
  }
  func testLockedPresentationUsesOnlyStorePriceAndKeepsManualSyncFree() {
    let missing = LifetimeUnlockPresentation(state: .unavailable, displayPrice: nil)
    XCTAssertNil(missing.purchaseTitle)
    XCTAssertTrue(missing.status.contains("unavailable"))
    XCTAssertTrue(missing.freeFeatures.contains("Sync Now"))
    XCTAssertTrue(missing.paidFeatures.contains("Background sync"))
    XCTAssertTrue(missing.paidFeatures.contains("Shortcuts sync"))
    XCTAssertTrue(missing.paidFeatures.contains("Historical import"))
    XCTAssertTrue(missing.paidFeatures.contains("Original-sample archive (iOS 27)"))

    let available = LifetimeUnlockPresentation(state: .locked, displayPrice: "CHF 9.00")
    XCTAssertEqual(available.purchaseTitle, "Unlock for CHF 9.00")
  }

  func testPurchaseOutcomesDoNotPromiseAccessUntilVerified() {
    XCTAssertTrue((LifetimeUnlockPresentation.message(for: .cancelled) ?? "").contains("cancelled"))
    XCTAssertTrue((LifetimeUnlockPresentation.message(for: .pending) ?? "").contains("pending"))
    XCTAssertTrue((LifetimeUnlockPresentation.message(for: .unverified) ?? "").contains("verified"))
    XCTAssertTrue(
      (LifetimeUnlockPresentation.message(for: .unavailable) ?? "").contains("unavailable"))
    XCTAssertNil(LifetimeUnlockPresentation.message(for: .purchased))
  }

  func testUnlockedPresentationShowsAccessWithoutAnotherPurchase() {
    let presentation = LifetimeUnlockPresentation(state: .unlocked, displayPrice: "CHF 9.00")
    XCTAssertNil(presentation.purchaseTitle)
    XCTAssertTrue(presentation.status.contains("unlocked"))
  }

  func testDeveloperAccessIsLabeledAndDoesNotOfferStorePurchase() {
    let presentation = LifetimeUnlockPresentation(
      state: .unlocked, displayPrice: nil, isDeveloperAccess: true)

    XCTAssertTrue(presentation.status.contains("Developer"))
    XCTAssertNil(presentation.purchaseTitle)
    XCTAssertFalse(presentation.offersRetry)
  }
}
