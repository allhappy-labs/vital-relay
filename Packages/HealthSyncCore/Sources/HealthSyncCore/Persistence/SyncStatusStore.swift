import Foundation

public enum SyncStatusStoreError: Error, Equatable, Sendable {
  case unsupportedVersion
  case corruptedData
}

public protocol SyncStatusStore: Sendable {
  func snapshot() async throws -> SyncStatusSnapshot
  func recordAttempt(trigger: SyncTrigger, at: Date) async throws
  func record(report: SyncReport) async throws
  func record(report: BidirectionalSyncReport) async throws
  func recordInterruptedAttemptIfNeeded() async throws -> SyncStatusEvent?
  func recordThrottledWake() async throws
  func setRegistration(
    _ state: BackgroundRegistrationState,
    for metric: MetricID
  ) async throws
  func reset() async throws
}

public enum SyncStatusCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ snapshot: SyncStatusSnapshot) throws -> Data {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(Document(version: currentVersion, snapshot: snapshot))
    } catch {
      throw SyncStatusStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> SyncStatusSnapshot {
    do {
      let decoder = JSONDecoder()
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw SyncStatusStoreError.unsupportedVersion
      }
      let document = try decoder.decode(Document.self, from: data)
      guard document.snapshot.recentEvents.count <= SyncStatusSnapshot.maximumRecentEvents else {
        throw SyncStatusStoreError.corruptedData
      }
      return document.snapshot
    } catch let error as SyncStatusStoreError {
      throw error
    } catch {
      throw SyncStatusStoreError.corruptedData
    }
  }

  private struct Header: Decodable {
    let version: Int
  }

  private struct Document: Codable {
    let version: Int
    let snapshot: SyncStatusSnapshot
  }
}

public actor InMemorySyncStatusStore: SyncStatusStore {
  private var storedSnapshot: SyncStatusSnapshot

  public init(snapshot: SyncStatusSnapshot = SyncStatusSnapshot()) {
    storedSnapshot = snapshot
  }

  public func snapshot() -> SyncStatusSnapshot {
    storedSnapshot
  }

  public func recordAttempt(trigger: SyncTrigger, at: Date) throws {
    try Task.checkCancellation()
    storedSnapshot.beginAttempt(trigger: trigger, at: at, launchID: SyncProcessLaunch.id)
  }

  public func record(report: SyncReport) throws {
    storedSnapshot.apply(report)
  }

  public func record(report: BidirectionalSyncReport) throws {
    storedSnapshot.apply(report)
  }

  public func recordInterruptedAttemptIfNeeded() throws -> SyncStatusEvent? {
    storedSnapshot.recordInterruptedAttemptIfNeeded(currentLaunchID: SyncProcessLaunch.id)
  }

  public func recordThrottledWake() throws {
    storedSnapshot.recordThrottledWake()
  }

  public func setRegistration(
    _ state: BackgroundRegistrationState,
    for metric: MetricID
  ) throws {
    try Task.checkCancellation()
    storedSnapshot.registrations[metric] = state
  }

  public func reset() throws {
    try Task.checkCancellation()
    storedSnapshot = SyncStatusSnapshot()
  }
}
