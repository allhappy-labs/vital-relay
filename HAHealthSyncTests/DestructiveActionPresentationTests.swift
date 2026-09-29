import XCTest

@testable import HAHealthSync

final class DestructiveActionPresentationTests: XCTestCase {
  func testResetScopeDistinguishesRemovedAndPreservedData() {
    XCTAssertEqual(
      DestructiveActionPresentation.reset.removed,
      [
        "Apple Health query anchors",
        "Home Assistant import checkpoints",
        "Historical import checkpoints",
        "Local archive import checkpoint and pending upload",
        "Medication checkpoints",
        "Metric freshness records",
        "Recent sync status",
      ]
    )
    XCTAssertEqual(
      DestructiveActionPresentation.reset.preserved,
      [
        "Connection settings and Keychain credentials",
        "Device-only archive uploader credential",
        "Selected metrics and entity pairings",
        "Apple Health samples and Home Assistant data",
        "Home Assistant health archive",
      ]
    )
  }

  func testDeleteAllStillPreservesExternalHealthAndHomeAssistantData() {
    XCTAssertTrue(
      DestructiveActionPresentation.deleteAll.preserved.contains(
        "Apple Health samples and Home Assistant data"
      )
    )
  }
}
