import Foundation
import HealthSyncCore

enum ProtectedSyncStatusStoreError: Error, Equatable, Sendable {
  case applicationSupportUnavailable
  case operationFailed
}

actor ProtectedSyncStatusStore: SyncStatusStore {
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
    fileURL = directoryURL.appending(path: "sync-status-v1.json", directoryHint: .notDirectory)
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ProtectedSyncStatusStoreError.applicationSupportUnavailable
    }
    directoryURL = applicationSupportURL.appending(
      path: "com.olhapi.HAHealthSync",
      directoryHint: .isDirectory
    )
    self.fileManager = fileManager
    fileURL = directoryURL.appending(path: "sync-status-v1.json", directoryHint: .notDirectory)
  }

  func snapshot() throws -> SyncStatusSnapshot {
    try load()
  }

  func recordAttempt(trigger: SyncTrigger, at: Date) throws {
    try Task.checkCancellation()
    var status = try load()
    status.beginAttempt(trigger: trigger, at: at, launchID: SyncProcessLaunch.id)
    try write(status)
  }

  func record(report: SyncReport) throws {
    var status = try load()
    status.apply(report)
    try write(status)
  }

  func record(report: BidirectionalSyncReport) throws {
    var status = try load()
    status.apply(report)
    try write(status)
  }

  func recordInterruptedAttemptIfNeeded() throws -> SyncStatusEvent? {
    var status = try load()
    guard
      let event = status.recordInterruptedAttemptIfNeeded(
        currentLaunchID: SyncProcessLaunch.id
      )
    else {
      return nil
    }
    try write(status)
    return event
  }

  func recordThrottledWake() throws {
    var status = try load()
    status.recordThrottledWake()
    try write(status)
  }

  func setRegistration(
    _ state: BackgroundRegistrationState,
    for metric: MetricID
  ) throws {
    try Task.checkCancellation()
    var status = try load()
    status.registrations[metric] = state
    try write(status)
  }

  func reset() throws {
    try Task.checkCancellation()
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw ProtectedSyncStatusStoreError.operationFailed
    }
  }

  private func load() throws -> SyncStatusSnapshot {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return SyncStatusSnapshot()
    }
    do {
      return try SyncStatusCodec.decode(Data(contentsOf: fileURL))
    } catch let error as SyncStatusStoreError {
      throw error
    } catch {
      throw ProtectedSyncStatusStoreError.operationFailed
    }
  }

  private func write(_ snapshot: SyncStatusSnapshot) throws {
    let data = try SyncStatusCodec.encode(snapshot)
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
      throw ProtectedSyncStatusStoreError.operationFailed
    }
  }
}
