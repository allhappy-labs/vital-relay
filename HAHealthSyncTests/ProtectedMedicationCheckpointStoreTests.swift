import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedMedicationCheckpointStoreTests: XCTestCase {
  func testPersistsOpaqueCheckpointThenResets() async throws {
    try await withStore { store in
      let medicationID = MedicationIdentifier.make(from: Data("fixture-medication".utf8))
      let checkpoint = MedicationCheckpoint(
        anchor: Data([1, 2, 3]),
        medicationIDs: [medicationID],
        sourceFingerprint: MedicationIdentifier.fingerprint([medicationID])
      )

      try await store.save(checkpoint)

      let loaded = try await store.load()
      XCTAssertEqual(loaded, checkpoint)
      let text = try XCTUnwrap(String(data: Data(contentsOf: store.fileURL), encoding: .utf8))
      XCTAssertFalse(text.contains("Metformin"))
      XCTAssertFalse(text.contains("500"))

      try await store.reset()
      let reset = try await store.load()
      XCTAssertNil(reset)
    }
  }

  func testUsesProtectedAtomicBackupExcludedPolicy() async throws {
    XCTAssertEqual(
      ProtectedMedicationCheckpointStore.fileProtection,
      .completeUntilFirstUserAuthentication
    )
    XCTAssertTrue(
      ProtectedMedicationCheckpointStore.writingOptions.contains(
        .completeFileProtectionUntilFirstUserAuthentication
      )
    )
    XCTAssertTrue(ProtectedMedicationCheckpointStore.writingOptions.contains(.atomic))

    try await withStore { store in
      let medicationID = MedicationIdentifier.make(from: Data("fixture-medication".utf8))
      try await store.save(
        MedicationCheckpoint(
          anchor: nil,
          medicationIDs: [medicationID],
          sourceFingerprint: MedicationIdentifier.fingerprint([medicationID])
        )
      )
      let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true)
    }
  }

  private func withStore(
    operation: (ProtectedMedicationCheckpointStore) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "medication-store-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try await operation(ProtectedMedicationCheckpointStore(directoryURL: directory))
  }
}
