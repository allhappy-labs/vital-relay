import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedPairingCheckpointStoreTests: XCTestCase {
  private let pairingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

  func testCommitReplaceResetAndCorruption() async throws {
    try await withStore { store in
      let initial = checkpoint(value: 70)
      let replacement = checkpoint(value: 71)
      try await store.commit(initial)
      try await store.commit(replacement)
      let loaded = try await store.checkpoint(for: pairingID)
      XCTAssertEqual(loaded, replacement)

      try Data("invalid".utf8).write(to: store.fileURL)
      do {
        _ = try await store.checkpoint(for: pairingID)
        XCTFail("Expected corruptedData")
      } catch {
        XCTAssertEqual(error as? PairingCheckpointStoreError, .corruptedData)
      }
    }
  }

  func testFileIsBackupExcludedAndResetIsIdempotent() async throws {
    try await withStore { store in
      try await store.commit(checkpoint(value: 70))
      let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true)
      try await store.reset(pairingID: pairingID)
      try await store.reset(pairingID: pairingID)
      try await store.resetAll()
      let loaded = try await store.checkpoint(for: pairingID)
      XCTAssertNil(loaded)
    }
  }

  func testDeclaresExactFileProtectionOptions() {
    XCTAssertEqual(
      ProtectedPairingCheckpointStore.fileProtection,
      .completeUntilFirstUserAuthentication
    )
    XCTAssertTrue(
      ProtectedPairingCheckpointStore.writingOptions.contains(
        .completeFileProtectionUntilFirstUserAuthentication
      )
    )
    XCTAssertTrue(ProtectedPairingCheckpointStore.writingOptions.contains(.atomic))
  }

  func testFilesystemReportsExactProtectionWhenSupported() async throws {
    try await withStore { store in
      try await store.commit(checkpoint(value: 70))
      let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
      guard let protection = attributes[.protectionKey] as? FileProtectionType else {
        throw XCTSkip("CoreSimulator does not report iOS data-protection metadata")
      }
      XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }
  }

  private func checkpoint(value: Double) -> PairingCheckpoint {
    let date = Date(timeIntervalSince1970: 1_788_052_801)
    let identity = SyncIdentity.make(
      pairingID: pairingID,
      entityID: "sensor.body_mass",
      homeAssistantUpdatedAt: date,
      normalizedValue: value,
      destination: .bodyMass
    )
    return PairingCheckpoint(
      pairingID: pairingID,
      entityID: "sensor.body_mass",
      homeAssistantUpdatedAt: date,
      normalizedValue: value,
      destination: .bodyMass,
      syncIdentifier: identity.identifier,
      syncVersion: identity.version
    )
  }

  private func withStore(
    operation: (ProtectedPairingCheckpointStore) async throws -> Void
  ) async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "HAHealthSyncTests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = ProtectedPairingCheckpointStore(directoryURL: directoryURL)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try await operation(store)
  }
}
