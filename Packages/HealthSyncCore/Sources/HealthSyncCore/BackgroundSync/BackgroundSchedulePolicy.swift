import Foundation

public struct BackgroundSchedulePolicy: Sendable, Equatable {
  public static let maximumTolerance: TimeInterval = 10 * 60
  public static let maximumRetryInterval: TimeInterval = 15 * 60
  public static let retryCategories: Set<SyncFailureCategory> = [
    .deviceLocked, .offline, .timeout, .dnsFailure, .connectionLost, .deadlineExceeded,
  ]

  public let frequency: BackgroundSyncFrequency

  public init(frequency: BackgroundSyncFrequency) {
    self.frequency = frequency
  }

  public var interval: TimeInterval { frequency.minimumInterval }
  public var tolerance: TimeInterval { min(Self.maximumTolerance, interval * 0.2) }
  public var retryInterval: TimeInterval { min(Self.maximumRetryInterval, interval) }

  public func eligibleAt(lastAttemptedAt: Date?) -> Date? {
    lastAttemptedAt?.addingTimeInterval(interval - tolerance)
  }

  var retryTolerance: TimeInterval { min(Self.maximumTolerance, retryInterval * 0.2) }

  /// The earliest date an automatic trigger may run, or `nil` when there has been no attempt or
  /// a locked-device failure bypasses the gate. After any other retry-category failure, or a
  /// cancelled/interrupted run, automatic triggers become eligible at the retry allowance,
  /// never later than normal.
  public func automaticEligibleAt(lastAttemptedAt: Date?, lastFailure: SyncStatusFailure?) -> Date?
  {
    guard let lastAttemptedAt, let normal = eligibleAt(lastAttemptedAt: lastAttemptedAt) else {
      return nil
    }
    guard let category = lastFailure?.category else { return normal }
    if category == .deviceLocked { return nil }
    guard Self.retryCategories.contains(category) || category == .cancelled else { return normal }
    return min(normal, lastAttemptedAt.addingTimeInterval(retryInterval - retryTolerance))
  }

  public func shouldThrottle(
    trigger: SyncTrigger,
    lastAttemptedAt: Date?,
    lastFailure: SyncStatusFailure?,
    now: Date
  ) -> Date? {
    guard trigger.isAutomatic,
      let eligibleAt = automaticEligibleAt(
        lastAttemptedAt: lastAttemptedAt, lastFailure: lastFailure),
      eligibleAt > now
    else {
      return nil
    }
    return eligibleAt
  }

  public func nextRefreshDate(after outcome: BidirectionalSyncOutcome, now: Date) -> Date {
    switch outcome {
    case .requiresPurchase:
      return now.addingTimeInterval(retryInterval)
    case .throttled(let nextEligibleAt):
      return max(now, nextEligibleAt)
    case .performed(let report):
      // A cancelled run retries like a transient failure. It never bypasses the gate.
      let categories = Set(report.failureCategories)
      if !Self.retryCategories.isDisjoint(with: categories) || categories.contains(.cancelled) {
        return now.addingTimeInterval(retryInterval)
      }
      return max(now, eligibleAt(lastAttemptedAt: report.startedAt) ?? now)
    }
  }

  public func initialRefreshDate(
    lastAttemptedAt: Date?,
    lastFailure: SyncStatusFailure?,
    now: Date
  ) -> Date {
    if let lastFailure,
      Self.retryCategories.contains(lastFailure.category) || lastFailure.category == .cancelled
    {
      return now.addingTimeInterval(retryInterval)
    }
    guard let eligibleAt = eligibleAt(lastAttemptedAt: lastAttemptedAt) else {
      return now.addingTimeInterval(retryInterval)
    }
    return max(now, eligibleAt)
  }
}
