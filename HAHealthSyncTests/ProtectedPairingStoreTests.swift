import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedPairingStoreTests: XCTestCase {
  func testMissingFileIsEmptyAndSaveAtomicallyReplacesByID() async throws {
    try await withStore { store, directoryURL in
      let initiallyLoaded = try await store.all()
      XCTAssertEqual(initiallyLoaded, [])
      var pairing = self.pairing()
      try await store.save(pairing)
      pairing.isEnabled = false
      try await store.save(pairing)

      let loaded = try await store.all()
      XCTAssertEqual(loaded, [pairing])
      let files = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
      )
      XCTAssertEqual(files.map(\.lastPathComponent), ["pairings-v1.json"])
    }
  }

  func testDuplicateFailureLeavesOriginalDocumentUntouched() async throws {
    try await withStore { store, _ in
      let original = pairing()
      try await store.save(original)
      let duplicate = Pairing(
        entityID: original.entityID,
        destination: original.destination,
        sourceUnit: original.sourceUnit,
        destinationUnit: original.destinationUnit,
        transformation: .identity,
        isEnabled: true
      )

      do {
        try await store.save(duplicate)
        XCTFail("Expected duplicate validation failure")
      } catch {
        XCTAssertEqual(error as? PairingValidationError, .duplicateEnabledPairing)
      }
      let loaded = try await store.all()
      XCTAssertEqual(loaded, [original])
    }
  }

  func testDeleteAndDeleteAllAreIdempotent() async throws {
    try await withStore { store, _ in
      let pairing = pairing()
      try await store.save(pairing)
      try await store.delete(id: pairing.id)
      try await store.delete(id: pairing.id)
      try await store.deleteAll()
      let loaded = try await store.all()
      XCTAssertEqual(loaded, [])
    }
  }

  func testCorruptionFailsClosedAndFileIsExcludedFromBackup() async throws {
    try await withStore { store, _ in
      try await store.save(pairing())
      let resourceValues = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(resourceValues.isExcludedFromBackup, true)

      try Data("invalid".utf8).write(to: store.fileURL)
      do {
        _ = try await store.all()
        XCTFail("Expected corruptedData")
      } catch {
        XCTAssertEqual(error as? PairingStoreError, .corruptedData)
      }
    }
  }

  func testDeclaresExactFileProtectionOptions() {
    XCTAssertEqual(ProtectedPairingStore.fileProtection, .completeUntilFirstUserAuthentication)
    XCTAssertTrue(
      ProtectedPairingStore.writingOptions.contains(
        .completeFileProtectionUntilFirstUserAuthentication
      )
    )
    XCTAssertTrue(ProtectedPairingStore.writingOptions.contains(.atomic))
  }

  func testFilesystemReportsExactProtectionWhenSupported() async throws {
    try await withStore { store, _ in
      try await store.save(pairing())
      let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
      guard let protection = attributes[.protectionKey] as? FileProtectionType else {
        throw XCTSkip("CoreSimulator does not report iOS data-protection metadata")
      }
      XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }
  }

  private func pairing() -> Pairing {
    Pairing(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
      entityID: "sensor.body_mass",
      destination: .bodyMass,
      sourceUnit: .kilograms,
      destinationUnit: .kilograms,
      transformation: .identity,
      isEnabled: true
    )
  }

  private func withStore(
    operation: (ProtectedPairingStore, URL) async throws -> Void
  ) async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "HAHealthSyncTests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = ProtectedPairingStore(directoryURL: directoryURL)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try await operation(store, directoryURL)
  }
}
