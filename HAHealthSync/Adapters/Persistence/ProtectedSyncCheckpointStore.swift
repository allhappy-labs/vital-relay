import Foundation
import HealthSyncCore

enum ProtectedSyncCheckpointStoreError: Error, Equatable, Sendable {
  case applicationSupportUnavailable
  case operationFailed
}

actor ProtectedSyncCheckpointStore: SyncCheckpointStore {
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
      path: "healthkit-anchors-v1.json", directoryHint: .notDirectory)
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ProtectedSyncCheckpointStoreError.applicationSupportUnavailable
    }
    directoryURL = applicationSupportURL.appending(
      path: "com.olhapi.HAHealthSync",
      directoryHint: .isDirectory
    )
    self.fileManager = fileManager
    fileURL = directoryURL.appending(
      path: "healthkit-anchors-v1.json", directoryHint: .notDirectory)
  }

  func anchor(for metric: MetricID) throws -> Data? {
    try Task.checkCancellation()
    return try loadAnchors()[metric]
  }

  func commit(anchor: Data, for metric: MetricID) throws {
    try Task.checkCancellation()
    guard !anchor.isEmpty else {
      throw SyncCheckpointStoreError.emptyAnchor
    }
    var anchors = try loadAnchors()
    anchors[metric] = anchor
    try write(anchors)
  }

  func reset(metric: MetricID) throws {
    try Task.checkCancellation()
    var anchors = try loadAnchors()
    anchors[metric] = nil
    if anchors.isEmpty {
      try removeFile()
    } else {
      try write(anchors)
    }
  }

  func resetAll() throws {
    try Task.checkCancellation()
    try removeFile()
  }

  private func loadAnchors() throws -> [MetricID: Data] {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return [:]
    }
    do {
      return try SyncCheckpointCodec.decode(Data(contentsOf: fileURL))
    } catch let error as SyncCheckpointStoreError {
      throw error
    } catch {
      throw ProtectedSyncCheckpointStoreError.operationFailed
    }
  }

  private func write(_ anchors: [MetricID: Data]) throws {
    let data = try SyncCheckpointCodec.encode(anchors)
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
      throw ProtectedSyncCheckpointStoreError.operationFailed
    }
  }

  private func removeFile() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return
    }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw ProtectedSyncCheckpointStoreError.operationFailed
    }
  }
}
