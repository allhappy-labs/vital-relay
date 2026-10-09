import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class SyncStatusSummaryTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_790_000_000)

  private func make(
    syncing: Bool = false, error: SyncFailureCategory? = nil, last: Date? = nil
  ) -> SyncStatusSummary {
    SyncStatusSummary.make(
      isSyncing: syncing, currentError: error, lastSuccessfulSync: last,
      formatLastSync: { _ in "29 Sep 2026 at 14:02" })
  }

  func testSyncedShowsAbsoluteLastSync() {
    let summary = make(last: date)
    XCTAssertEqual(summary.tone, .synced)
    XCTAssertEqual(summary.title, "All synced")
    XCTAssertEqual(summary.detail, "Last sync: 29 Sep 2026 at 14:02")
  }

  func testNeverSynced() {
    let summary = make()
    XCTAssertEqual(summary.tone, .attention)
    XCTAssertEqual(summary.title, "Not synced yet")
    XCTAssertEqual(summary.detail, "Last sync: Never")
  }

  func testErrorWinsOverEarlierSuccess() {
    let summary = make(error: .unauthorized, last: date)
    XCTAssertEqual(summary.tone, .attention)
    XCTAssertEqual(summary.title, "Sync issue: unauthorized")
    XCTAssertEqual(summary.detail, "Last sync: 29 Sep 2026 at 14:02")
  }

  func testSyncingWinsOverEverything() {
    let summary = make(syncing: true, error: .offline, last: date)
    XCTAssertEqual(summary.tone, .syncing)
    XCTAssertEqual(summary.title, "Syncing…")
  }
}
