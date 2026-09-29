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

public struct ArchiveImportReport: Sendable, Equatable {
  public var archiveState: ArchiveImportState = .idle
  public var archivedSamples = 0
  public var archivedDeletions = 0
  public var metricEarliestDates: [MetricID: Date] = [:]
  public var noReadableMetrics: Set<MetricID> = []
  public var projectionStates: [MetricID: ArchiveProjectionState] = [:]
  public var failures: [ArchiveImportFailure] = []
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
