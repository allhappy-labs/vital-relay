import Foundation

extension SyncStatusSnapshot {
  public mutating func beginAttempt(trigger: SyncTrigger, at date: Date, launchID: UUID) {
    lastAttemptedAt = date
    inFlightAttempt = SyncInFlightAttempt(trigger: trigger, startedAt: date, launchID: launchID)
  }

  public mutating func apply(_ report: SyncReport) {
    lastAttemptedAt = report.startedAt
    if report.failures.isEmpty {
      lastSuccessfulAt = report.finishedAt
      lastFailure = nil
    } else if let failure = report.failures.first {
      lastFailure = SyncStatusFailure(
        metricID: failure.metricID,
        category: failure.category,
        at: report.finishedAt
      )
    }
    append(SyncStatusEvent(report: report, throttledWakesBefore: consumeThrottledWakes()))
    inFlightAttempt = nil
  }

  public mutating func apply(_ report: BidirectionalSyncReport) {
    lastAttemptedAt = report.startedAt
    if report.succeeded {
      lastSuccessfulAt = report.finishedAt
      lastFailure = nil
    } else if let category = report.setupFailureCategory {
      lastFailure = SyncStatusFailure(metricID: nil, category: category, at: report.finishedAt)
    } else if let failure = report.outbound?.failures.first {
      lastFailure = SyncStatusFailure(
        metricID: failure.metricID,
        category: failure.category,
        at: report.finishedAt
      )
    } else if let failure = report.inbound?.failures.first {
      lastFailure = SyncStatusFailure(
        metricID: nil,
        category: failure.category,
        at: report.finishedAt
      )
    }
    append(SyncStatusEvent(report: report, throttledWakesBefore: consumeThrottledWakes()))
    inFlightAttempt = nil
  }

  public mutating func recordInterruptedAttemptIfNeeded(currentLaunchID: UUID) -> SyncStatusEvent? {
    guard let attempt = inFlightAttempt, attempt.launchID != currentLaunchID else {
      return nil
    }
    inFlightAttempt = nil
    lastFailure = SyncStatusFailure(metricID: nil, category: .cancelled, at: attempt.startedAt)
    let event = SyncStatusEvent(
      interrupted: attempt,
      throttledWakesBefore: consumeThrottledWakes()
    )
    append(event)
    return event
  }

  public mutating func recordThrottledWake() {
    pendingThrottledWakes += 1
  }

  private mutating func consumeThrottledWakes() -> Int {
    defer { pendingThrottledWakes = 0 }
    return pendingThrottledWakes
  }

  private mutating func append(_ event: SyncStatusEvent) {
    recentEvents.append(event)
    recentEvents = Array(recentEvents.suffix(Self.maximumRecentEvents))
  }
}
