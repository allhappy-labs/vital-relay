import Foundation

public enum SyncTrigger: String, Codable, Sendable {
  case manual
  case pullToRefresh
  case background
  case shortcut
  case healthKitObserver
  case appRefresh

  public var isAutomatic: Bool {
    switch self {
    case .background, .healthKitObserver, .appRefresh: true
    case .manual, .pullToRefresh, .shortcut: false
    }
  }

  /// Every trigger but an observer wake covers all selected metrics; only `.healthKitObserver`
  /// runs can be scoped to what changed.
  public var isFullSweepTrigger: Bool {
    self != .healthKitObserver
  }

  public var budget: TimeInterval? {
    switch self {
    case .appRefresh, .shortcut: 25
    case .healthKitObserver, .background: 18
    case .manual, .pullToRefresh: nil
    }
  }
}

public enum SyncFailureCategory: String, Codable, Sendable {
  case purchaseRequired
  case configuration
  case credential
  case healthKit
  case deviceLocked
  case cancelled
  case timeout
  case deadlineExceeded
  case dnsFailure
  case offline
  case connectionLost
  case tlsFailure
  case unauthorized
  case forbidden
  case notFound
  case validation
  case rateLimited
  case server
  case malformedResponse
  case protocolMismatch
  case transport
  case checkpoint
  case compatibility
  case unknown
}

public struct SyncFailureSummary: Codable, Sendable, Equatable {
  public let metricID: MetricID?
  public let category: SyncFailureCategory

  public init(metricID: MetricID?, category: SyncFailureCategory) {
    self.metricID = metricID
    self.category = category
  }
}

public struct SyncReport: Codable, Sendable, Equatable {
  public let trigger: SyncTrigger
  public let attemptedMetrics: Int
  public let synchronizedMetrics: Int
  public let skippedMetrics: Int
  public let failures: [SyncFailureSummary]
  public let startedAt: Date
  public let finishedAt: Date
  public let requestCount: Int
  /// How many metrics the run actually looked at. Not comparable with `attemptedMetrics`, which
  /// also counts medications and unsupported metrics — `deferredMetrics` is the truncation signal.
  public let collectedMetrics: Int
  /// How many metrics the run never looked at because the budget was down to the send reserve.
  /// A sweep is only complete when this is `0`.
  public let deferredMetrics: Int
  /// Seconds spent collecting metrics and seconds spent sending them, so a truncated run can be
  /// told apart from a slow one.
  public let collectSeconds: Double
  public let sendSeconds: Double
  /// Which metrics the run looked at without the query failing, whatever became of their values.
  /// This is how far the run got through the selection, which is what the rotation offset is
  /// computed from — not what it managed to resolve. A metric whose query failed is left out on
  /// purpose: it must stay stale so the next run retries it and the starvation audit can surface
  /// a metric that never succeeds.
  public let collectedMetricIDs: Set<MetricID>
  /// Which metrics Health Bridge accepted a value for in this run.
  public let synchronizedMetricIDs: Set<MetricID>
  /// Which metrics the run resolved: Health Bridge accepted a value, or the metric genuinely had
  /// nothing to send and whatever anchor that produced is committed.
  ///
  /// A metric collected with a value that never reached Health Bridge — the deadline abandoned
  /// the send, the request failed, the run ended before its chunk was tried — is collected but
  /// not resolved. Its data is still only on the phone, so it must stay stale for the next run:
  /// a check recorded for it would hide unsent data behind the freshness rule for the whole
  /// freshness interval, while its anchor is untouched and the changed-type ledger that would
  /// have covered it was drained by this very run.
  public let resolvedMetricIDs: Set<MetricID>

  public init(
    trigger: SyncTrigger,
    attemptedMetrics: Int,
    synchronizedMetrics: Int,
    skippedMetrics: Int,
    failures: [SyncFailureSummary],
    startedAt: Date,
    finishedAt: Date,
    requestCount: Int = 0,
    collectedMetrics: Int = 0,
    deferredMetrics: Int = 0,
    collectSeconds: Double = 0,
    sendSeconds: Double = 0,
    collectedMetricIDs: Set<MetricID> = [],
    synchronizedMetricIDs: Set<MetricID> = [],
    resolvedMetricIDs: Set<MetricID> = []
  ) {
    self.trigger = trigger
    self.attemptedMetrics = attemptedMetrics
    self.synchronizedMetrics = synchronizedMetrics
    self.skippedMetrics = skippedMetrics
    self.failures = failures
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.requestCount = requestCount
    self.collectedMetrics = collectedMetrics
    self.deferredMetrics = deferredMetrics
    self.collectSeconds = collectSeconds
    self.sendSeconds = sendSeconds
    self.collectedMetricIDs = collectedMetricIDs
    self.synchronizedMetricIDs = synchronizedMetricIDs
    self.resolvedMetricIDs = resolvedMetricIDs
  }
}
