import Foundation
import HealthSyncCore

enum ProtectedMetricFreshnessStoreError: Error, Equatable, Sendable {
  case applicationSupportUnavailable
  case operationFailed
}

actor ProtectedMetricFreshnessStore: MetricFreshnessStore {
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
      path: "metric-freshness-v1.json", directoryHint: .notDirectory)
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ProtectedMetricFreshnessStoreError.applicationSupportUnavailable
    }
    directoryURL = applicationSupportURL.appending(
      path: "com.olhapi.HAHealthSync",
      directoryHint: .isDirectory
    )
    self.fileManager = fileManager
    fileURL = directoryURL.appending(
      path: "metric-freshness-v1.json", directoryHint: .notDirectory)
  }

  func snapshot() throws -> MetricFreshnessSnapshot {
    try Task.checkCancellation()
    return try load()
  }

  /// Deliberately runs to completion on a cancelled task: see `MetricFreshnessStore.record(_:)`.
  func record(_ update: MetricFreshnessUpdate) throws {
    var snapshot = try load()
    snapshot.apply(update)
    try write(snapshot)
  }

  func reset() throws {
    try Task.checkCancellation()
    try removeFile()
  }

  private func load() throws -> MetricFreshnessSnapshot {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return MetricFreshnessSnapshot()
    }
    do {
      return try MetricFreshnessCodec.decode(Data(contentsOf: fileURL))
    } catch let error as MetricFreshnessStoreError {
      throw error
    } catch {
      throw ProtectedMetricFreshnessStoreError.operationFailed
    }
  }

  private func write(_ snapshot: MetricFreshnessSnapshot) throws {
    let data = try MetricFreshnessCodec.encode(snapshot)
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
      var protectedFileURL = fileURL
      try protectedFileURL.setResourceValues(values)
    } catch {
      throw ProtectedMetricFreshnessStoreError.operationFailed
    }
  }

  private func removeFile() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return
    }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw ProtectedMetricFreshnessStoreError.operationFailed
    }
  }
}
