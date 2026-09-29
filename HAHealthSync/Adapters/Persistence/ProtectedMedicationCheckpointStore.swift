import Foundation
import HealthSyncCore

enum ProtectedMedicationCheckpointStoreError: Error, Sendable, Equatable {
  case applicationSupportUnavailable
  case operationFailed
}

actor ProtectedMedicationCheckpointStore: MedicationCheckpointStore {
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
    fileURL = directoryURL.appending(path: "medication-checkpoint-v1.json")
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else { throw ProtectedMedicationCheckpointStoreError.applicationSupportUnavailable }
    directoryURL = applicationSupportURL.appending(
      path: "com.olhapi.HAHealthSync",
      directoryHint: .isDirectory
    )
    self.fileManager = fileManager
    fileURL = directoryURL.appending(path: "medication-checkpoint-v1.json")
  }

  func load() throws -> MedicationCheckpoint? {
    try Task.checkCancellation()
    guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
    do {
      return try MedicationCheckpointCodec.decode(Data(contentsOf: fileURL))
    } catch let error as MedicationCheckpointStoreError {
      throw error
    } catch {
      throw ProtectedMedicationCheckpointStoreError.operationFailed
    }
  }

  func save(_ checkpoint: MedicationCheckpoint) throws {
    try Task.checkCancellation()
    let data = try MedicationCheckpointCodec.encode(checkpoint)
    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: Self.fileProtection]
      )
      try data.write(to: fileURL, options: Self.writingOptions)
      try fileManager.setAttributes(
        [.protectionKey: Self.fileProtection],
        ofItemAtPath: fileURL.path
      )
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var protectedURL = fileURL
      try protectedURL.setResourceValues(values)
    } catch {
      throw ProtectedMedicationCheckpointStoreError.operationFailed
    }
  }

  func reset() throws {
    try Task.checkCancellation()
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw ProtectedMedicationCheckpointStoreError.operationFailed
    }
  }
}
