import Foundation

public enum BackgroundUnavailableReason: String, Codable, Sendable, Equatable {
  case healthDataUnavailable
  case unsupportedType
  case backgroundDeliveryUnavailable
}

public enum BackgroundRegistrationState: Codable, Sendable, Equatable {
  case disabled
  case registered(at: Date)
  case failed(category: SyncFailureCategory, at: Date)
  case unavailable(reason: BackgroundUnavailableReason)
}

public enum SyncProcessLaunch {
  public static let id = UUID()
}

public enum SyncEventOutcome: String, Codable, Sendable, Equatable {
  case completed
  case interrupted
}

public struct SyncRunContext: Codable, Sendable, Equatable {
  public enum BackgroundRefresh: String, Codable, Sendable, Equatable {
    case available
    case denied
    case restricted
  }

  public let backgroundRefresh: BackgroundRefresh
  public let lowPowerMode: Bool
  public let protectedDataAvailable: Bool

  public init(
    backgroundRefresh: BackgroundRefresh,
    lowPowerMode: Bool,
    protectedDataAvailable: Bool
  ) {
    self.backgroundRefresh = backgroundRefresh
    self.lowPowerMode = lowPowerMode
    self.protectedDataAvailable = protectedDataAvailable
  }
}

public struct SyncInFlightAttempt: Codable, Sendable, Equatable {
  public let trigger: SyncTrigger
  public let startedAt: Date
  public let launchID: UUID?

  public init(trigger: SyncTrigger, startedAt: Date, launchID: UUID?) {
    self.trigger = trigger
    self.startedAt = startedAt
    self.launchID = launchID
  }
}

public struct SyncStatusFailure: Codable, Sendable, Equatable {
  public let metricID: MetricID?
  public let category: SyncFailureCategory
  public let at: Date

  public init(metricID: MetricID?, category: SyncFailureCategory, at: Date) {
    self.metricID = metricID
    self.category = category
    self.at = at
  }
}

public struct SyncStatusEvent: Codable, Sendable, Equatable {
  public let trigger: SyncTrigger
  public let attemptedMetrics: Int
  public let synchronizedMetrics: Int
  public let skippedMetrics: Int
  public let attemptedPairings: Int
  public let savedPairings: Int
  public let skippedPairings: Int
  public let failureCategories: [SyncFailureCategory]
  public let finishedAt: Date
  public let startedAt: Date?
  public let outcome: SyncEventOutcome
  public let requestCount: Int?
  public let throttledWakesBefore: Int
  public let context: SyncRunContext?
  /// The run's `SyncScopeReason` raw value, `nil` for a run no scope was resolved for.
  public let scopeReason: String?
  /// What the run set out to cover and what it managed to look at.
  public let requestedMetrics: Int?
  public let collectedMetrics: Int?
  /// How many metrics the run left for the next one because the budget was down to the send
  /// reserve. Non-zero is truncation, not failure — without it a run that was cut short and a run
  /// that had nothing to do read identically.
  public let deferredMetrics: Int?
  /// Seconds spent collecting and seconds spent sending, so a truncated run can be told apart
  /// from a slow one.
  public let collectSeconds: Double?
  public let sendSeconds: Double?
  /// How many changed types the run was scoped from. `nil` means the caller named no set at
  /// all, which the policy treats as an unknown change; `0` means it named an empty one.
  public let changedTypes: Int?
  /// Selected metrics that had gone unchecked for longer than the starvation interval when this
  /// full sweep started. Zero in a healthy system; `nil` on a run that was not a full sweep.
  public let starvedMetrics: Int?

  public init(report: SyncReport, throttledWakesBefore: Int = 0) {
    trigger = report.trigger
    attemptedMetrics = report.attemptedMetrics
    synchronizedMetrics = report.synchronizedMetrics
    skippedMetrics = report.skippedMetrics
    attemptedPairings = 0
    savedPairings = 0
    skippedPairings = 0
    failureCategories = report.failures.map(\.category)
    finishedAt = report.finishedAt
    startedAt = report.startedAt
    outcome = .completed
    requestCount = report.requestCount
    self.throttledWakesBefore = throttledWakesBefore
    context = nil
    scopeReason = nil
    requestedMetrics = nil
    collectedMetrics = report.collectedMetrics
    deferredMetrics = report.deferredMetrics
    collectSeconds = report.collectSeconds
    sendSeconds = report.sendSeconds
    changedTypes = nil
    starvedMetrics = nil
  }

  public init(report: BidirectionalSyncReport, throttledWakesBefore: Int = 0) {
    trigger = report.trigger
    attemptedMetrics = report.outbound?.attemptedMetrics ?? 0
    synchronizedMetrics = report.outbound?.synchronizedMetrics ?? 0
    skippedMetrics = report.outbound?.skippedMetrics ?? 0
    attemptedPairings = report.inbound?.attemptedPairings ?? 0
    savedPairings = report.inbound?.savedPairings ?? 0
    skippedPairings = report.inbound?.skippedPairings ?? 0
    failureCategories = report.failureCategories
    finishedAt = report.finishedAt
    startedAt = report.startedAt
    outcome = .completed
    requestCount = report.outbound?.requestCount
    self.throttledWakesBefore = throttledWakesBefore
    context = report.context
    scopeReason = report.scopeReason?.rawValue
    requestedMetrics = report.requestedMetrics
    collectedMetrics = report.outbound?.collectedMetrics
    deferredMetrics = report.outbound?.deferredMetrics
    collectSeconds = report.outbound?.collectSeconds
    sendSeconds = report.outbound?.sendSeconds
    changedTypes = report.changedTypes
    starvedMetrics = report.starvedMetrics
  }

  public init(interrupted attempt: SyncInFlightAttempt, throttledWakesBefore: Int = 0) {
    trigger = attempt.trigger
    attemptedMetrics = 0
    synchronizedMetrics = 0
    skippedMetrics = 0
    attemptedPairings = 0
    savedPairings = 0
    skippedPairings = 0
    failureCategories = []
    finishedAt = attempt.startedAt
    startedAt = attempt.startedAt
    outcome = .interrupted
    requestCount = nil
    self.throttledWakesBefore = throttledWakesBefore
    context = nil
    scopeReason = nil
    requestedMetrics = nil
    collectedMetrics = nil
    deferredMetrics = nil
    collectSeconds = nil
    sendSeconds = nil
    changedTypes = nil
    starvedMetrics = nil
  }

  public var duration: TimeInterval? {
    startedAt.map { max(0, finishedAt.timeIntervalSince($0)) }
  }

  private enum CodingKeys: String, CodingKey {
    case trigger
    case attemptedMetrics
    case synchronizedMetrics
    case skippedMetrics
    case attemptedPairings
    case savedPairings
    case skippedPairings
    case failureCategories
    case finishedAt
    case startedAt
    case outcome
    case requestCount
    case throttledWakesBefore
    case context
    case scopeReason
    case requestedMetrics
    case collectedMetrics
    case deferredMetrics
    case collectSeconds
    case sendSeconds
    case changedTypes
    case starvedMetrics
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    trigger = try container.decode(SyncTrigger.self, forKey: .trigger)
    attemptedMetrics = try container.decode(Int.self, forKey: .attemptedMetrics)
    synchronizedMetrics = try container.decode(Int.self, forKey: .synchronizedMetrics)
    skippedMetrics = try container.decode(Int.self, forKey: .skippedMetrics)
    attemptedPairings = try container.decodeIfPresent(Int.self, forKey: .attemptedPairings) ?? 0
    savedPairings = try container.decodeIfPresent(Int.self, forKey: .savedPairings) ?? 0
    skippedPairings = try container.decodeIfPresent(Int.self, forKey: .skippedPairings) ?? 0
    failureCategories = try container.decode(
      [SyncFailureCategory].self,
      forKey: .failureCategories
    )
    finishedAt = try container.decode(Date.self, forKey: .finishedAt)
    startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
    outcome = try container.decodeIfPresent(SyncEventOutcome.self, forKey: .outcome) ?? .completed
    requestCount = try container.decodeIfPresent(Int.self, forKey: .requestCount)
    throttledWakesBefore =
      try container.decodeIfPresent(Int.self, forKey: .throttledWakesBefore) ?? 0
    context = try container.decodeIfPresent(SyncRunContext.self, forKey: .context)
    scopeReason = try container.decodeIfPresent(String.self, forKey: .scopeReason)
    requestedMetrics = try container.decodeIfPresent(Int.self, forKey: .requestedMetrics)
    collectedMetrics = try container.decodeIfPresent(Int.self, forKey: .collectedMetrics)
    deferredMetrics = try container.decodeIfPresent(Int.self, forKey: .deferredMetrics)
    collectSeconds = try container.decodeIfPresent(Double.self, forKey: .collectSeconds)
    sendSeconds = try container.decodeIfPresent(Double.self, forKey: .sendSeconds)
    changedTypes = try container.decodeIfPresent(Int.self, forKey: .changedTypes)
    starvedMetrics = try container.decodeIfPresent(Int.self, forKey: .starvedMetrics)
  }
}

public struct SyncStatusSnapshot: Codable, Sendable, Equatable {
  public static let maximumRecentEvents = 100

  public var lastAttemptedAt: Date?
  public var lastSuccessfulAt: Date?
  public var lastFailure: SyncStatusFailure?
  public var registrations: [MetricID: BackgroundRegistrationState]
  public var recentEvents: [SyncStatusEvent]
  public var inFlightAttempt: SyncInFlightAttempt?
  public var pendingThrottledWakes: Int

  public init(
    lastAttemptedAt: Date? = nil,
    lastSuccessfulAt: Date? = nil,
    lastFailure: SyncStatusFailure? = nil,
    registrations: [MetricID: BackgroundRegistrationState] = [:],
    recentEvents: [SyncStatusEvent] = [],
    inFlightAttempt: SyncInFlightAttempt? = nil,
    pendingThrottledWakes: Int = 0
  ) {
    self.lastAttemptedAt = lastAttemptedAt
    self.lastSuccessfulAt = lastSuccessfulAt
    self.lastFailure = lastFailure
    self.registrations = registrations
    self.recentEvents = Array(recentEvents.suffix(Self.maximumRecentEvents))
    self.inFlightAttempt = inFlightAttempt
    self.pendingThrottledWakes = pendingThrottledWakes
  }

  private enum CodingKeys: String, CodingKey {
    case lastAttemptedAt
    case lastSuccessfulAt
    case lastFailure
    case registrations
    case recentEvents
    case inFlightAttempt
    case pendingThrottledWakes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    lastAttemptedAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptedAt)
    lastSuccessfulAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt)
    lastFailure = try container.decodeIfPresent(SyncStatusFailure.self, forKey: .lastFailure)
    registrations = try container.decode(
      [MetricID: BackgroundRegistrationState].self,
      forKey: .registrations
    )
    recentEvents = try container.decode([SyncStatusEvent].self, forKey: .recentEvents)
    inFlightAttempt = try container.decodeIfPresent(
      SyncInFlightAttempt.self,
      forKey: .inFlightAttempt
    )
    pendingThrottledWakes =
      try container.decodeIfPresent(Int.self, forKey: .pendingThrottledWakes) ?? 0
  }
}
