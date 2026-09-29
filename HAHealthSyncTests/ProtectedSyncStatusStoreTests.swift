import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedSyncStatusStoreTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_788_035_400)

  func testCombinedReportRoundTrip() async throws {
    try await withStore { store, _ in
      let report = BidirectionalSyncReport(
        trigger: .background,
        outbound: SyncReport(
          trigger: .background,
          attemptedMetrics: 2,
          synchronizedMetrics: 1,
          skippedMetrics: 1,
          failures: [],
          startedAt: date,
          finishedAt: date.addingTimeInterval(1)
        ),
        inbound: InboundSyncReport(
          trigger: .background,
          attemptedPairings: 1,
          savedPairings: 1,
          skippedPairings: 0,
          failures: [],
          startedAt: date,
          finishedAt: date.addingTimeInterval(1)
        ),
        startedAt: date,
        finishedAt: date.addingTimeInterval(1)
      )

      try await store.record(report: report)

      let snapshot = try await store.snapshot()
      XCTAssertEqual(snapshot.lastSuccessfulAt, report.finishedAt)
      XCTAssertEqual(snapshot.recentEvents.last?.attemptedMetrics, 2)
      XCTAssertEqual(snapshot.recentEvents.last?.savedPairings, 1)
    }
  }

  func testSuccessfulNoChangeReportClearsLockedDefer() async throws {
    try await withStore { store, _ in
      try await store.record(
        report: SyncReport(
          trigger: .background,
          attemptedMetrics: 1,
          synchronizedMetrics: 0,
          skippedMetrics: 0,
          failures: [.init(metricID: nil, category: .deviceLocked)],
          startedAt: date,
          finishedAt: date
        )
      )

      let finishedAt = date.addingTimeInterval(1)
      try await store.record(
        report: BidirectionalSyncReport(
          trigger: .background,
          outbound: SyncReport(
            trigger: .background,
            attemptedMetrics: 1,
            synchronizedMetrics: 0,
            skippedMetrics: 1,
            failures: [],
            startedAt: date,
            finishedAt: finishedAt
          ),
          inbound: nil,
          startedAt: date,
          finishedAt: finishedAt
        )
      )

      let snapshot = try await store.snapshot()
      XCTAssertEqual(snapshot.lastSuccessfulAt, finishedAt)
      XCTAssertNil(snapshot.lastFailure)
    }
  }

  func testAtomicRoundTripRegistrationAndReset() async throws {
    try await withStore { store, directoryURL in
      try await store.recordAttempt(trigger: .background, at: date)
      try await store.setRegistration(.registered(at: date), for: .steps)

      let snapshot = try await store.snapshot()
      XCTAssertEqual(snapshot.lastAttemptedAt, date)
      XCTAssertEqual(snapshot.registrations[.steps], .registered(at: date))
      let files = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
      )
      XCTAssertEqual(files.map(\.lastPathComponent), ["sync-status-v1.json"])

      try await store.reset()
      let resetSnapshot = try await store.snapshot()
      XCTAssertEqual(resetSnapshot, SyncStatusSnapshot())
      XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }
  }

  func testCorruptedFileFailsClosedWithoutReplacement() async throws {
    try await withStore { store, _ in
      try FileManager.default.createDirectory(
        at: store.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let corrupt = Data("not-json".utf8)
      try corrupt.write(to: store.fileURL)

      do {
        _ = try await store.snapshot()
        XCTFail("Expected corrupted data")
      } catch {
        XCTAssertEqual(error as? SyncStatusStoreError, .corruptedData)
      }
      XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }
  }

  func testCancelledWriteDoesNotCreateAFile() async throws {
    try await withStore { store, _ in
      let cancellationDate = date
      let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        try await store.recordAttempt(trigger: .manual, at: cancellationDate)
      }
      do {
        try await task.value
        XCTFail("Expected cancellation")
      } catch is CancellationError {
        // Expected.
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }
  }

  func testFileSecurityOptions() async throws {
    try await withStore { store, _ in
      try await store.recordAttempt(trigger: .manual, at: date)
      let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true)
      XCTAssertEqual(
        ProtectedSyncStatusStore.fileProtection,
        .completeUntilFirstUserAuthentication
      )
      XCTAssertTrue(ProtectedSyncStatusStore.writingOptions.contains(.atomic))
      XCTAssertTrue(
        ProtectedSyncStatusStore.writingOptions.contains(
          .completeFileProtectionUntilFirstUserAuthentication
        )
      )
    }
  }

  func testFilesystemReportsExactProtectionWhenSupported() async throws {
    try await withStore { store, _ in
      try await store.recordAttempt(trigger: .manual, at: date)
      let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
      guard let protection = attributes[.protectionKey] as? FileProtectionType else {
        throw XCTSkip("CoreSimulator does not report iOS data-protection metadata")
      }
      XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }
  }

  func testCancelledTaskStillPersistsReportAndInterruptedMarkerRoundTrips() async throws {
    try await withStore { store, _ in
      try await store.recordAttempt(trigger: .appRefresh, at: date)
      let report = BidirectionalSyncReport(
        trigger: .appRefresh,
        outbound: nil,
        inbound: nil,
        setupFailureCategory: .cancelled,
        startedAt: date,
        finishedAt: date
      )
      let task = Task {
        try? await Task.sleep(for: .seconds(10))
        try await store.record(report: report)
      }
      task.cancel()
      try await task.value

      var snapshot = try await store.snapshot()
      XCTAssertEqual(snapshot.recentEvents.last?.failureCategories, [.cancelled])
      XCTAssertNil(snapshot.inFlightAttempt)

      try await store.recordThrottledWake()
      snapshot = try await store.snapshot()
      XCTAssertEqual(snapshot.pendingThrottledWakes, 1)
      let interrupted = try await store.recordInterruptedAttemptIfNeeded()
      XCTAssertNil(interrupted)
    }
  }

  private func withStore(
    operation: (ProtectedSyncStatusStore, URL) async throws -> Void
  ) async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "HAHealthSyncStatusTests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = ProtectedSyncStatusStore(directoryURL: directoryURL)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try await operation(store, directoryURL)
  }
}
