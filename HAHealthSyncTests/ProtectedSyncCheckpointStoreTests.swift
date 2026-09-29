import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedSyncCheckpointStoreTests: XCTestCase {
  func testAtomicRoundTripReplacementAndReset() async throws {
    try await withStore { store, directoryURL in
      try await store.commit(anchor: Data([1]), for: .steps)
      try await store.commit(anchor: Data([2]), for: .bodyMass)
      try await store.commit(anchor: Data([3]), for: .steps)

      let stepsAnchor = try await store.anchor(for: .steps)
      let bodyAnchor = try await store.anchor(for: .bodyMass)
      XCTAssertEqual(stepsAnchor, Data([3]))
      XCTAssertEqual(bodyAnchor, Data([2]))
      let files = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
      )
      XCTAssertEqual(files.map(\.lastPathComponent), ["healthkit-anchors-v1.json"])

      try await store.reset(metric: .steps)
      let resetStepsAnchor = try await store.anchor(for: .steps)
      let retainedBodyAnchor = try await store.anchor(for: .bodyMass)
      XCTAssertNil(resetStepsAnchor)
      XCTAssertEqual(retainedBodyAnchor, Data([2]))
      try await store.resetAll()
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
        _ = try await store.anchor(for: .steps)
        XCTFail("Expected corrupted data")
      } catch {
        XCTAssertEqual(error as? SyncCheckpointStoreError, .corruptedData)
      }
      do {
        try await store.commit(anchor: Data([1]), for: .steps)
        XCTFail("Expected corrupted data")
      } catch {
        XCTAssertEqual(error as? SyncCheckpointStoreError, .corruptedData)
      }
      XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }
  }

  func testCancelledCommitDoesNotCreateAFile() async throws {
    try await withStore { store, _ in
      let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        try await store.commit(anchor: Data([1]), for: .steps)
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

  func testFileIsExcludedFromBackup() async throws {
    try await withStore { store, _ in
      try await store.commit(anchor: Data([1]), for: .steps)
      let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true)
    }
  }

  func testDeclaresExactFileProtectionOptions() {
    XCTAssertEqual(
      ProtectedSyncCheckpointStore.fileProtection,
      .completeUntilFirstUserAuthentication
    )
    XCTAssertTrue(
      ProtectedSyncCheckpointStore.writingOptions.contains(
        .completeFileProtectionUntilFirstUserAuthentication
      )
    )
    XCTAssertTrue(ProtectedSyncCheckpointStore.writingOptions.contains(.atomic))
  }

  func testFilesystemReportsExactProtectionWhenSupported() async throws {
    try await withStore { store, _ in
      try await store.commit(anchor: Data([1]), for: .steps)
      let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
      guard let protection = attributes[.protectionKey] as? FileProtectionType else {
        throw XCTSkip("CoreSimulator does not report iOS data-protection metadata")
      }
      XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }
  }

  private func withStore(
    operation: (ProtectedSyncCheckpointStore, URL) async throws -> Void
  ) async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "HAHealthSyncAnchorTests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = ProtectedSyncCheckpointStore(directoryURL: directoryURL)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try await operation(store, directoryURL)
  }
}
