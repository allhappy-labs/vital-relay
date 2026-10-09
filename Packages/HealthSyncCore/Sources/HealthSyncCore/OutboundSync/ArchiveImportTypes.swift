import Foundation

public struct ArchiveImportSelection: Codable, Sendable, Equatable {
  public let metrics: Set<MetricID>
  /// Nil means all readable history, independently discovered for each source type.
  public let requestedStart: Date?
  public init(metrics: Set<MetricID>, requestedStart: Date? = nil) {
    self.metrics = metrics
    self.requestedStart = requestedStart
  }
}

public enum ArchiveImportState: String, Codable, Sendable {
  case idle, importing, archived, paused, failed
}
public enum ArchiveQueryError: Error, Sendable {
  case deviceLocked, anchorInvalidated, permissionRestricted
}
public enum ArchiveImportIssue: String, Codable, Sendable, Error {
  case purchaseRequired
  case reconciliationRequired, permissionRestricted, noReadableSamples, destinationChanged
  case inventoryTooDense, authorizationUnproven, inventoryUnstable
  case ownerRequired, ownerPending, ownerChanged, checkpointOwnerMismatch
}

public struct ArchiveImportFailure: Sendable, Equatable {
  public let type: HealthObjectTypeID?
  public let category: SyncFailureCategory
  public let issue: ArchiveImportIssue?
  public init(
    type: HealthObjectTypeID? = nil, category: SyncFailureCategory, issue: ArchiveImportIssue? = nil
  ) {
    self.type = type
    self.category = category
    self.issue = issue
  }
}

/// What the import is doing now. Published through the progress callback; never persisted.
public enum ArchiveImportPhase: Sendable, Equatable {
  case idle
  /// Connection, capability and HealthKit discovery.
  case preparing
  /// Bounded interval scan and upload of one source type.
  case archiving(HealthObjectTypeID)
  /// Anchored reconciliation and inventory comparison of one source type.
  case checking(HealthObjectTypeID)
  /// Home Assistant asked for a pause (Retry-After). Resumes automatically.
  case waiting(until: Date)
}

/// Time-based progress of one source type: how much of its readable range Home Assistant has
/// acknowledged. Sample totals are deliberately not counted; that would need a full HealthKit pass.
public struct ArchiveTypeProgress: Sendable, Equatable {
  /// Nil when none of the type's selected metrics has a readable sample.
  public var range: DateInterval?
  public var fraction: Double
  public var isComplete: Bool
  public init(range: DateInterval?, fraction: Double, isComplete: Bool) {
    self.range = range
    self.fraction = fraction
    self.isComplete = isComplete
  }
}

public struct ArchiveImportReport: Sendable, Equatable {
  public var archiveState: ArchiveImportState = .idle
  public var archivedSamples = 0
  public var archivedDeletions = 0
  public var metricEarliestDates: [MetricID: Date] = [:]
  public var noReadableMetrics: Set<MetricID> = []
  public var projectionStates: [MetricID: ArchiveProjectionState] = [:]
  public var failures: [ArchiveImportFailure] = []
  public var phase: ArchiveImportPhase = .idle
  public var typeProgress: [HealthObjectTypeID: ArchiveTypeProgress] = [:]
  /// Mean of per-type fractions over types with readable history; nil when there are none.
  public var overallFraction: Double? {
    let readable = typeProgress.values.filter { $0.range != nil }.map(\.fraction)
    return readable.isEmpty ? nil : readable.reduce(0, +) / Double(readable.count)
  }
  public init() {}
}

public protocol ArchiveImportCoordinating: Sendable {
  func importHistory(selection: ArchiveImportSelection) async -> ArchiveImportReport
  func pause() async
  func resume() async -> ArchiveImportReport
  func refreshProjection() async -> ArchiveImportReport
}

/// Ephemeral credentials and negotiated capability, rebuilt from current configuration each run.
public struct ArchiveImportConnection: Sendable {
  public let baseURL: NormalizedBaseURL
  public let userID: String
  public let token: String
  public let capability: ArchiveCapability
  public let sender: any ArchiveBatchSending
  public let statusFetcher: any ArchiveStatusFetching
  public let inventoryFetcher: (any ArchiveInventoryFetching)?
  public let uploaderFingerprint: String?
  public init(
    baseURL: NormalizedBaseURL, userID: String, token: String, capability: ArchiveCapability,
    sender: any ArchiveBatchSending, statusFetcher: any ArchiveStatusFetching,
    inventoryFetcher: (any ArchiveInventoryFetching)? = nil,
    uploaderFingerprint: String? = nil
  ) {
    self.baseURL = baseURL
    self.userID = userID
    self.token = token
    self.capability = capability
    self.sender = sender
    self.statusFetcher = statusFetcher
    self.inventoryFetcher = inventoryFetcher ?? (sender as? any ArchiveInventoryFetching)
    self.uploaderFingerprint = uploaderFingerprint
  }
}
