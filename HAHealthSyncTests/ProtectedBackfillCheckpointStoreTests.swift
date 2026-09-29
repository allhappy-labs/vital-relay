import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedBackfillCheckpointStoreTests: XCTestCase {
  func testPersistsCapabilityAndValueFreeCheckpointThenResets() async throws {
    try await withStore { store in
      let state = BackfillState(
        capability: .available(protocolVersion: 1),
        checkpoints: [
          .steps: BackfillCheckpoint(
            metricID: .steps,
            windowStart: Date(timeIntervalSince1970: 100),
            committedThrough: Date(timeIntervalSince1970: 200),
            requestID: "backfill.01234567"
          )
        ]
      )
      try await store.save(state)
      let loaded = try await store.load()
      XCTAssertEqual(loaded, state)
      let text = try XCTUnwrap(String(data: Data(contentsOf: store.fileURL), encoding: .utf8))
      XCTAssertFalse(text.contains("fixture-secret"))
      XCTAssertFalse(text.contains("8421"))
      try await store.reset()
      let reset = try await store.load()
      XCTAssertEqual(reset, BackfillState())
    }
  }

  func testUsesProtectedAtomicBackupExcludedPolicy() async throws {
    XCTAssertEqual(
      ProtectedBackfillCheckpointStore.fileProtection,
      .completeUntilFirstUserAuthentication
    )
    XCTAssertTrue(
      ProtectedBackfillCheckpointStore.writingOptions.contains(
        .completeFileProtectionUntilFirstUserAuthentication
      )
    )
    XCTAssertTrue(ProtectedBackfillCheckpointStore.writingOptions.contains(.atomic))
    try await withStore { store in
      try await store.save(BackfillState(capability: .temporarilyUnavailable))
      let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true)
    }
  }

  private func withStore(
    operation: (ProtectedBackfillCheckpointStore) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "backfill-store-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try await operation(ProtectedBackfillCheckpointStore(directoryURL: directory))
  }
}
