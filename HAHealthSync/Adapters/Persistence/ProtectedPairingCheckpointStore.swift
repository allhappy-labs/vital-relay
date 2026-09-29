import Foundation
import HealthSyncCore

enum ProtectedPairingCheckpointStoreError: Error, Equatable, Sendable {
  case applicationSupportUnavailable
  case operationFailed
}

actor ProtectedPairingCheckpointStore: PairingCheckpointStore {
  nonisolated static let fileProtection =
    FileProtectionType.completeUntilFirstUserAuthentication
  nonisolated static let writingOptions: Data.WritingOptions = [
    .atomic, .completeFileProtectionUntilFirstUserAuthentication,
  ]

  nonisolated let fileURL: URL

  private let directoryURL: URL
  private let fileManager: FileManager

  init(directoryURL: URL, fileManager: FileManager = .default) {
    self.directoryURL = directoryURL
    self.fileManager = fileManager
    fileURL = directoryURL.appending(
      path: "pairing-checkpoints-v1.json",
      directoryHint: .notDirectory
    )
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ProtectedPairingCheckpointStoreError.applicationSupportUnavailable
    }
    directoryURL = applicationSupportURL.appending(
      path: "com.olhapi.HAHealthSync",
      directoryHint: .isDirectory
    )
    self.fileManager = fileManager
    fileURL = directoryURL.appending(
      path: "pairing-checkpoints-v1.json",
      directoryHint: .notDirectory
    )
  }

  func checkpoint(for pairingID: UUID) throws -> PairingCheckpoint? {
    try Task.checkCancellation()
    return try load()[pairingID]
  }

  func commit(_ checkpoint: PairingCheckpoint) throws {
    try Task.checkCancellation()
    var checkpoints = try load()
    checkpoints[checkpoint.pairingID] = checkpoint
    try write(checkpoints)
  }

  func reset(pairingID: UUID) throws {
    try Task.checkCancellation()
    var checkpoints = try load()
    checkpoints[pairingID] = nil
    if checkpoints.isEmpty {
      try removeFile()
    } else {
      try write(checkpoints)
    }
  }

  func resetAll() throws {
    try Task.checkCancellation()
    try removeFile()
  }

  private func load() throws -> [UUID: PairingCheckpoint] {
    guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
    do {
      return try PairingCheckpointCodec.decode(Data(contentsOf: fileURL))
    } catch let error as PairingCheckpointStoreError {
      throw error
    } catch {
      throw ProtectedPairingCheckpointStoreError.operationFailed
    }
  }

  private func write(_ checkpoints: [UUID: PairingCheckpoint]) throws {
    let data = try PairingCheckpointCodec.encode(checkpoints)
    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: Self.fileProtection]
      )
      try Task.checkCancellation()
      try data.write(to: fileURL, options: Self.writingOptions)
      try fileManager.setAttributes(
        [.protectionKey: Self.fileProtection],
        ofItemAtPath: fileURL.path
      )
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var protectedFileURL = fileURL
      try protectedFileURL.setResourceValues(values)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ProtectedPairingCheckpointStoreError.operationFailed
    }
  }

  private func removeFile() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw ProtectedPairingCheckpointStoreError.operationFailed
    }
  }
}
