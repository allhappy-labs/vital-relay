import Foundation

/// Absence of readable samples never diagnoses HealthKit read permission.
public enum ReadableHistory: Sendable, Equatable {
  case readable(earliest: Date, authorizationBoundary: Date?)
  case noReadableSamples(authorizationBoundary: Date?)
}

public struct ArchiveHistoryDiscovery: Sendable, Equatable {
  public let types: [HealthObjectTypeID: ReadableHistory]
  public let metrics: [MetricID: ReadableHistory]

  public init(types: [HealthObjectTypeID: ReadableHistory], metrics: [MetricID: ReadableHistory]) {
    self.types = types
    self.metrics = metrics
  }
}

/// Bound to one type and requested interval. Persist only after archive acknowledgement.
public struct ArchiveScanCursor: Codable, Sendable, Equatable {
  public let type: HealthObjectTypeID
  public let interval: DateInterval
  public let windowStart: Date
  public let windowEnd: Date
  public let anchor: Data?

  public init(
    type: HealthObjectTypeID, interval: DateInterval, windowStart: Date, windowEnd: Date,
    anchor: Data?
  ) {
    self.type = type
    self.interval = interval
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.anchor = anchor
  }
}

public struct ArchiveSamplePage: Sendable, Equatable {
  public let samples: [ArchiveSample]
  public let deletedSampleIDs: [UUID]
  /// Candidate window only: durable coverage requires completion, reconciliation, and archive receipts.
  public let coveredInterval: DateInterval
  public let isWindowComplete: Bool
  public let nextCursor: ArchiveScanCursor?

  public init(
    samples: [ArchiveSample], deletedSampleIDs: [UUID], coveredInterval: DateInterval,
    isWindowComplete: Bool, nextCursor: ArchiveScanCursor?
  ) {
    self.samples = samples
    self.deletedSampleIDs = deletedSampleIDs
    self.coveredInterval = coveredInterval
    self.isWindowComplete = isWindowComplete
    self.nextCursor = nextCursor
  }
}

public struct ArchiveChangePage: Sendable, Equatable {
  public let samples: [ArchiveSample]
  public let deletedSampleIDs: [UUID]
  public let candidateAnchor: Data
  public let hasMore: Bool

  public init(
    samples: [ArchiveSample], deletedSampleIDs: [UUID], candidateAnchor: Data, hasMore: Bool
  ) {
    self.samples = samples
    self.deletedSampleIDs = deletedSampleIDs
    self.candidateAnchor = candidateAnchor
    self.hasMore = hasMore
  }
}

public protocol HealthArchiveQuerying: Sendable {
  func discover(types: Set<HealthObjectTypeID>) async throws -> [HealthObjectTypeID:
    ReadableHistory]
  func discover(metrics: [MetricDefinition]) async throws -> ArchiveHistoryDiscovery
  /// The caller clamps the interval to the independently discovered authorization boundary.
  /// Window predicates overlap; consumers deduplicate by type/UUID rather than timestamp.
  func page(
    type: HealthObjectTypeID, interval: DateInterval, cursor: ArchiveScanCursor?, limit: Int
  ) async throws -> ArchiveSamplePage
  func changes(type: HealthObjectTypeID, anchor: Data?) async throws -> ArchiveChangePage
}
