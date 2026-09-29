import Foundation
import HealthSyncCore
import UIKit

/// Contains only progress plus one unacknowledged batch, protected even after first unlock.
actor ProtectedArchiveCheckpointStore: ArchiveCheckpointStore {
  nonisolated static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
  nonisolated let fileURL: URL
  private let directoryURL: URL
  private let fileManager: FileManager
  private let protectedDataAvailable: @Sendable () async -> Bool

  init(
    directoryURL: URL, fileManager: FileManager = .default,
    protectedDataAvailable: @escaping @Sendable () async -> Bool = {
      await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
    }
  ) {
    self.directoryURL = directoryURL
    self.fileManager = fileManager
    self.protectedDataAvailable = protectedDataAvailable
    fileURL = directoryURL.appending(path: "archive-checkpoints-v1.json")
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      throw ArchiveCheckpointStoreError.unavailable
    }
    directoryURL = support.appending(path: "com.olhapi.HAHealthSync", directoryHint: .isDirectory)
    self.fileManager = fileManager
    fileURL = directoryURL.appending(path: "archive-checkpoints-v1.json")
    protectedDataAvailable = {
      await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
    }
  }

  func load() async throws -> ArchiveImportCheckpoint {
    try Task.checkCancellation()
    guard await protectedDataAvailable() else { throw ArchiveQueryError.deviceLocked }
    guard fileManager.fileExists(atPath: fileURL.path) else { return ArchiveImportCheckpoint() }
    let data: Data
    do { data = try Data(contentsOf: fileURL) } catch {
      throw ArchiveCheckpointStoreError.unavailable
    }
    return try ArchiveCheckpointCodec.decode(data)
  }

  func save(_ state: ArchiveImportCheckpoint) async throws {
    try Task.checkCancellation()
    guard await protectedDataAvailable() else { throw ArchiveQueryError.deviceLocked }
    let data = try ArchiveCheckpointCodec.encode(state)
    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      try data.write(to: fileURL, options: Self.writingOptions)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var url = fileURL
      try url.setResourceValues(values)
    } catch { throw ArchiveCheckpointStoreError.unavailable }
  }

  func reset() async throws {
    try Task.checkCancellation()
    guard await protectedDataAvailable() else { throw ArchiveQueryError.deviceLocked }
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    do { try fileManager.removeItem(at: fileURL) } catch {
      throw ArchiveCheckpointStoreError.unavailable
    }
  }
}
