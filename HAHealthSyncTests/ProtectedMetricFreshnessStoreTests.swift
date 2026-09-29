import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedMetricFreshnessStoreTests: XCTestCase {
  private static let referenceDate = Date(timeIntervalSince1970: 1_788_035_400)
  private static let selection: Set<MetricID> = [.steps, .bodyMass]

  private static func update(
    checked: Set<MetricID> = [],
    sent: Set<MetricID> = [],
    at date: Date = ProtectedMetricFreshnessStoreTests.referenceDate,
    selected: Set<MetricID> = ProtectedMetricFreshnessStoreTests.selection,
    rotationOffset: Int? = nil,
    completedSweepAt: Date? = nil
  ) -> MetricFreshnessUpdate {
    MetricFreshnessUpdate(
      checked: checked,
      sent: sent,
      at: date,
      selected: selected,
      rotationOffset: rotationOffset,
      completedSweepAt: completedSweepAt
    )
  }

  func testRoundTripPersistsAndResetRemovesFile() async throws {
    try await withStore { store, directoryURL in
      try await store.record(Self.update(checked: [.steps, .bodyMass]))
      try await store.record(
        Self.update(
          sent: [.steps],
          at: Self.referenceDate.addingTimeInterval(60),
          rotationOffset: 2,
          completedSweepAt: Self.referenceDate
        )
      )

      let snapshot = try await store.snapshot()
      XCTAssertEqual(
        snapshot.lastCheckedAt,
        [.steps: Self.referenceDate, .bodyMass: Self.referenceDate]
      )
      XCTAssertEqual(snapshot.lastSentAt, [.steps: Self.referenceDate.addingTimeInterval(60)])
      XCTAssertEqual(snapshot.lastFullSweepAt, Self.referenceDate)
      XCTAssertEqual(snapshot.rotationOffset, 2)

      let files = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
      )
      XCTAssertEqual(files.map(\.lastPathComponent), ["metric-freshness-v1.json"])

      try await store.reset()
      XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
      let resetSnapshot = try await store.snapshot()
      XCTAssertEqual(resetSnapshot, MetricFreshnessSnapshot())
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
        XCTAssertEqual(error as? MetricFreshnessStoreError, .corruptedData)
      }
      do {
        try await store.record(Self.update(checked: [.steps]))
        XCTFail("Expected corrupted data")
      } catch {
        XCTAssertEqual(error as? MetricFreshnessStoreError, .corruptedData)
      }
      XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }
  }

  func testFileIsExcludedFromBackup() async throws {
    try await withStore { store, _ in
      try await store.record(Self.update(checked: [.steps]))
      let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true)
    }
  }

  func testDeclaresExactFileProtectionOptions() {
    XCTAssertEqual(
      ProtectedMetricFreshnessStore.fileProtection,
      .completeUntilFirstUserAuthentication
    )
    XCTAssertTrue(
      ProtectedMetricFreshnessStore.writingOptions.contains(
        .completeFileProtectionUntilFirstUserAuthentication
      )
    )
    XCTAssertTrue(ProtectedMetricFreshnessStore.writingOptions.contains(.atomic))
  }

  func testFilesystemReportsExactProtectionWhenSupported() async throws {
    try await withStore { store, _ in
      try await store.record(Self.update(checked: [.steps]))
      let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
      guard let protection = attributes[.protectionKey] as? FileProtectionType else {
        throw XCTSkip("CoreSimulator does not report iOS data-protection metadata")
      }
      XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }
  }

  private func withStore(
    operation: (ProtectedMetricFreshnessStore, URL) async throws -> Void
  ) async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "HAHealthSyncFreshnessTests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = ProtectedMetricFreshnessStore(directoryURL: directoryURL)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try await operation(store, directoryURL)
  }
}
