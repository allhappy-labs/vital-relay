import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedArchiveCheckpointStoreTests: XCTestCase {
  func testAtomicProtectedArchiveCoexistsWithLegacyAndResetRemovesOnlyArchive() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "archive-store-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacy = ProtectedBackfillCheckpointStore(directoryURL: directory)
    try await legacy.save(BackfillState(capability: .temporarilyUnavailable))
    let legacyData = try Data(contentsOf: legacy.fileURL)
    let store = ProtectedArchiveCheckpointStore(directoryURL: directory)
    var state = ArchiveImportCheckpoint()
    state.userID = "fixture-user"
    try await store.save(state)
    let loaded = try await store.load()
    XCTAssertEqual(loaded, state)
    #if targetEnvironment(simulator)
      // Simulator does not expose NSFileProtectionKey; the real-device branch checks it.
      XCTAssertTrue(
        ProtectedArchiveCheckpointStore.writingOptions.contains(.completeFileProtection))
    #else
      let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
      XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
    #endif
    XCTAssertEqual(
      try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
      true)
    XCTAssertTrue(ProtectedArchiveCheckpointStore.writingOptions.contains(.atomic))
    try await store.reset()
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    XCTAssertEqual(try Data(contentsOf: legacy.fileURL), legacyData)
  }

  func testCorruptArchiveIsNotSilentlyReset() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "archive-corrupt-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProtectedArchiveCheckpointStore(directoryURL: directory)
    try await store.save(ArchiveImportCheckpoint())
    try Data("corrupted".utf8).write(to: store.fileURL)
    do {
      _ = try await store.load()
      XCTFail("Expected corruption")
    } catch { XCTAssertEqual(error as? ArchiveCheckpointStoreError, .corruptedData) }
    XCTAssertEqual(try Data(contentsOf: store.fileURL), Data("corrupted".utf8))
  }

  func testLockedStoreDoesNotReadOrOverwritePendingData() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "archive-lock-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let unlocked = ProtectedArchiveCheckpointStore(
      directoryURL: directory, protectedDataAvailable: { true })
    var state = ArchiveImportCheckpoint()
    state.userID = "preserved"
    try await unlocked.save(state)
    let original = try Data(contentsOf: unlocked.fileURL)
    let locked = ProtectedArchiveCheckpointStore(
      directoryURL: directory, protectedDataAvailable: { false })
    do {
      _ = try await locked.load()
      XCTFail("Read while locked")
    } catch { XCTAssertEqual(error as? ArchiveQueryError, .deviceLocked) }
    do {
      try await locked.save(ArchiveImportCheckpoint())
      XCTFail("Write while locked")
    } catch { XCTAssertEqual(error as? ArchiveQueryError, .deviceLocked) }
    XCTAssertEqual(try Data(contentsOf: unlocked.fileURL), original)
  }

  @MainActor
  func testBothMaintenanceActionsRemoveArchiveProgress() async throws {
    for deleteAll in [false, true] {
      var state = ArchiveImportCheckpoint()
      state.userID = "old-user"
      let store = InMemoryArchiveCheckpointStore(state: state)
      let model = AppModel(bidirectionalSyncCoordinator: nil, archiveCheckpointStore: store)
      if deleteAll {
        await model.deleteAllLocalApplicationData()
      } else {
        await model.resetSynchronizationState()
      }
      let reset = try await store.load()
      XCTAssertEqual(reset, ArchiveImportCheckpoint())
    }
  }
}
