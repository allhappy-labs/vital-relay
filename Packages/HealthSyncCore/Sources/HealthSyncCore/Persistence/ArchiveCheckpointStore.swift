import Foundation

/// Normalized half-open intervals; newest progress never hides an older gap.
public struct ArchiveIntervals: Codable, Sendable, Equatable {
  public private(set) var intervals: [DateInterval] = []
  public init() {}

  public mutating func insert(_ interval: DateInterval) {
    guard interval.duration > 0 else { return }
    var merged: [DateInterval] = []
    for value in (intervals + [interval]).sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, value.start <= last.end {
        merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, value.end))
      } else {
        merged.append(value)
      }
    }
    intervals = merged
  }

  public func gaps(in interval: DateInterval) -> [DateInterval] {
    var position = interval.start
    var result: [DateInterval] = []
    for value in intervals where value.end > position && value.start < interval.end {
      if value.start > position {
        result.append(DateInterval(start: position, end: min(value.start, interval.end)))
      }
      position = max(position, value.end)
    }
    if position < interval.end { result.append(DateInterval(start: position, end: interval.end)) }
    return result
  }
}

public struct ArchiveTypeCheckpoint: Codable, Sendable, Equatable {
  public var coverage = ArchiveIntervals()
  /// Acknowledged windows awaiting global reconciliation; never shown as complete.
  public var scanned = ArchiveIntervals()
  public var observedAuthorizationBoundary: Date?
  public var scanInterval: DateInterval?
  public var cursor: ArchiveScanCursor?
  public var anchor: Data?
  /// Observation boundary captured before the first scan, not acknowledged archive progress.
  /// Kept separately until the normal post-scan reconciliation commits an anchor.
  public var baselineAnchor: Data?
  public var lastCommittedBatchID: String?
  public var reconciliationRequired = false
  /// Original scope survives anchor loss even if the oldest originals disappear.
  public var reconciliationIntervals: ArchiveIntervals?
  /// Metadata only. A resumed comparison always rebuilds its ephemeral readable UUID set.
  public var inventoryComparison: ArchiveInventoryComparison?
  public init() {}
}

public struct ArchiveInventoryComparison: Codable, Sendable, Equatable {
  public let interval: DateInterval
  public let revision: Int64?
  public let cursor: String?
  public init(interval: DateInterval, revision: Int64? = nil, cursor: String? = nil) {
    self.interval = interval
    self.revision = revision
    self.cursor = cursor
  }
}

/// Only the bounded unacknowledged batch is journaled. No credentials or acknowledged originals.
public struct ArchivePendingBatch: Codable, Sendable, Equatable {
  public let type: HealthObjectTypeID
  public let batch: ArchiveBatch
  public let nextCheckpoint: ArchiveTypeCheckpoint

  public init(type: HealthObjectTypeID, batch: ArchiveBatch, nextCheckpoint: ArchiveTypeCheckpoint)
  {
    self.type = type
    self.batch = batch
    self.nextCheckpoint = nextCheckpoint
  }
}

public struct ArchiveImportCheckpoint: Codable, Sendable, Equatable {
  /// Non-secret device binding. A missing legacy binding requires an explicit rescan.
  public var uploaderFingerprint: String?
  /// Approval epoch. A credential approved again after transfer cannot reuse old work.
  public var ownerGeneration: Int?
  public var destination: String?
  public var userID: String?
  public var selection: ArchiveImportSelection?
  public var types: [HealthObjectTypeID: ArchiveTypeCheckpoint] = [:]
  public var metricEarliestDates: [MetricID: Date] = [:]
  public var pending: ArchivePendingBatch?
  public var archivedSamples = 0
  public var archivedDeletions = 0
  public init() {}

  public var hasPreviousWork: Bool {
    destination != nil || userID != nil || selection != nil || pending != nil
      || !types.isEmpty || archivedSamples != 0 || archivedDeletions != 0
  }
}

public enum ArchiveCheckpointStoreError: Error, Sendable, Equatable {
  case unsupportedVersion, corruptedData, unavailable
}

public protocol ArchiveCheckpointStore: Sendable {
  func load() async throws -> ArchiveImportCheckpoint
  func save(_ state: ArchiveImportCheckpoint) async throws
  func reset() async throws
}

public enum ArchiveCheckpointCodec {
  public static func encode(_ state: ArchiveImportCheckpoint) throws -> Data {
    try validate(state)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(Document(version: 1, archive: state))
  }

  public static func decode(_ data: Data) throws -> ArchiveImportCheckpoint {
    do {
      let decoder = JSONDecoder()
      guard try decoder.decode(Header.self, from: data).version == 1 else {
        throw ArchiveCheckpointStoreError.unsupportedVersion
      }
      let state = try decoder.decode(Document.self, from: data).archive
      try validate(state)
      return state
    } catch let error as ArchiveCheckpointStoreError { throw error } catch {
      throw ArchiveCheckpointStoreError.corruptedData
    }
  }

  private static func validate(_ state: ArchiveImportCheckpoint) throws {
    guard state.archivedSamples >= 0, state.archivedDeletions >= 0 else {
      throw ArchiveCheckpointStoreError.corruptedData
    }
    if let fingerprint = state.uploaderFingerprint {
      guard fingerprint.count == 12,
        fingerprint.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
      else { throw ArchiveCheckpointStoreError.corruptedData }
    }
    if let ownerGeneration = state.ownerGeneration, ownerGeneration < 1 {
      throw ArchiveCheckpointStoreError.corruptedData
    }
    for (type, checkpoint) in state.types {
      try validate(checkpoint, type: type)
    }
    if let pending = state.pending {
      do { try pending.batch.validate() } catch { throw ArchiveCheckpointStoreError.corruptedData }
      guard pending.type.rawValue == pending.batch.sampleType,
        state.userID == pending.batch.userID, state.destination != nil,
        state.types[pending.type] != nil
      else { throw ArchiveCheckpointStoreError.corruptedData }
      try validate(pending.nextCheckpoint, type: pending.type)
    }
  }

  private static func validate(_ checkpoint: ArchiveTypeCheckpoint, type: HealthObjectTypeID) throws
  {
    for intervals in [checkpoint.coverage, checkpoint.scanned]
      + [checkpoint.reconciliationIntervals].compactMap({ $0 })
    {
      var priorEnd: Date?
      for interval in intervals.intervals {
        guard interval.duration.isFinite, interval.duration > 0,
          interval.start.timeIntervalSince1970.isFinite,
          priorEnd == nil || priorEnd! < interval.start
        else { throw ArchiveCheckpointStoreError.corruptedData }
        priorEnd = interval.end
      }
    }
    if let comparison = checkpoint.inventoryComparison {
      guard checkpoint.reconciliationRequired,
        comparison.interval.start.timeIntervalSince1970.isFinite,
        comparison.interval.duration.isFinite, comparison.interval.duration > 0,
        comparison.revision.map({ $0 >= 0 }) ?? true,
        comparison.cursor.map({ ArchiveWire.validText($0, max: 2048) }) ?? true,
        comparison.cursor == nil || comparison.revision != nil
      else { throw ArchiveCheckpointStoreError.corruptedData }
    }
    if let cursor = checkpoint.cursor {
      guard cursor.type == type, cursor.interval == checkpoint.scanInterval,
        cursor.windowStart >= cursor.interval.start, cursor.windowStart < cursor.windowEnd,
        cursor.windowEnd <= cursor.interval.end
      else { throw ArchiveCheckpointStoreError.corruptedData }
    }
  }

  private struct Header: Decodable { let version: Int }
  private struct Document: Codable {
    let version: Int
    let archive: ArchiveImportCheckpoint
  }
}

public actor InMemoryArchiveCheckpointStore: ArchiveCheckpointStore {
  private var state: ArchiveImportCheckpoint
  public init(state: ArchiveImportCheckpoint = ArchiveImportCheckpoint()) { self.state = state }
  public func load() throws -> ArchiveImportCheckpoint {
    try Task.checkCancellation()
    return state
  }
  public func save(_ state: ArchiveImportCheckpoint) throws {
    try Task.checkCancellation()
    _ = try ArchiveCheckpointCodec.encode(state)
    self.state = state
  }
  public func reset() { state = ArchiveImportCheckpoint() }
}
