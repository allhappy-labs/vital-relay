import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Background schedule policy")
struct BackgroundSchedulePolicyTests {
  private let start = Date(timeIntervalSince1970: 1_788_035_400)

  @Test(
    "Tolerance is twenty percent capped at ten minutes",
    arguments: [
      (BackgroundSyncFrequency.responsive, 60.0, 240.0),
      (.balanced, 180, 720),
      (.batterySaver, 600, 3_000),
      (.daily, 600, 85_800),
    ]
  )
  func tolerance(frequency: BackgroundSyncFrequency, tolerance: Double, eligibleAfter: Double) {
    let policy = BackgroundSchedulePolicy(frequency: frequency)
    #expect(policy.tolerance == tolerance)
    #expect(policy.eligibleAt(lastAttemptedAt: start) == start.addingTimeInterval(eligibleAfter))
    #expect(policy.eligibleAt(lastAttemptedAt: nil) == nil)
  }

  @Test("Retry interval is fifteen minutes capped by the interval")
  func retryInterval() {
    #expect(BackgroundSchedulePolicy(frequency: .responsive).retryInterval == 300)
    #expect(BackgroundSchedulePolicy(frequency: .balanced).retryInterval == 900)
    #expect(BackgroundSchedulePolicy(frequency: .batterySaver).retryInterval == 900)
    #expect(BackgroundSchedulePolicy(frequency: .daily).retryInterval == 900)
  }

  @Test("Only automatic triggers inside the allowance are throttled")
  func gate() {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let early = start.addingTimeInterval(2_999)
    let eligible = start.addingTimeInterval(3_000)

    for trigger in [SyncTrigger.healthKitObserver, .appRefresh, .background] {
      #expect(
        policy.shouldThrottle(
          trigger: trigger, lastAttemptedAt: start, lastFailure: nil, now: early)
          == eligible
      )
      #expect(
        policy.shouldThrottle(
          trigger: trigger, lastAttemptedAt: start, lastFailure: nil, now: eligible)
          == nil
      )
    }
    for trigger in [SyncTrigger.manual, .pullToRefresh, .shortcut] {
      #expect(
        policy.shouldThrottle(
          trigger: trigger, lastAttemptedAt: start, lastFailure: nil, now: early)
          == nil
      )
    }
    #expect(
      policy.shouldThrottle(
        trigger: .appRefresh, lastAttemptedAt: nil, lastFailure: nil, now: early)
        == nil
    )
  }

  @Test("A locked-device failure never throttles the next automatic trigger")
  func lockedBypass() {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let locked = SyncStatusFailure(metricID: nil, category: .deviceLocked, at: start)
    #expect(
      policy.shouldThrottle(
        trigger: .healthKitObserver,
        lastAttemptedAt: start,
        lastFailure: locked,
        now: start.addingTimeInterval(10)
      ) == nil
    )
  }

  @Test(
    "Transient failures make automatic triggers eligible at the retry allowance",
    arguments: [BackgroundSyncFrequency.batterySaver, .daily]
  )
  func transientFailureRetryAllowance(frequency: BackgroundSyncFrequency) {
    let policy = BackgroundSchedulePolicy(frequency: frequency)
    let offline = SyncStatusFailure(metricID: nil, category: .offline, at: start)
    let retryEligible = start.addingTimeInterval(720)

    #expect(
      policy.automaticEligibleAt(lastAttemptedAt: start, lastFailure: offline) == retryEligible)
    #expect(
      policy.shouldThrottle(
        trigger: .healthKitObserver,
        lastAttemptedAt: start,
        lastFailure: offline,
        now: start.addingTimeInterval(719)
      ) == retryEligible
    )
    #expect(
      policy.shouldThrottle(
        trigger: .appRefresh,
        lastAttemptedAt: start,
        lastFailure: offline,
        now: retryEligible
      ) == nil
    )

    let locked = SyncStatusFailure(metricID: nil, category: .deviceLocked, at: start)
    #expect(policy.automaticEligibleAt(lastAttemptedAt: start, lastFailure: locked) == nil)
    #expect(
      policy.shouldThrottle(
        trigger: .healthKitObserver,
        lastAttemptedAt: start,
        lastFailure: locked,
        now: start.addingTimeInterval(10)
      ) == nil
    )

    let unauthorized = SyncStatusFailure(metricID: nil, category: .unauthorized, at: start)
    #expect(
      policy.automaticEligibleAt(lastAttemptedAt: start, lastFailure: unauthorized)
        == policy.eligibleAt(lastAttemptedAt: start)
    )
    #expect(policy.automaticEligibleAt(lastAttemptedAt: nil, lastFailure: offline) == nil)
  }

  @Test("The retry allowance is never later than normal eligibility")
  func retryAllowanceCap() {
    let policy = BackgroundSchedulePolicy(frequency: .responsive)
    let offline = SyncStatusFailure(metricID: nil, category: .timeout, at: start)
    #expect(
      policy.automaticEligibleAt(lastAttemptedAt: start, lastFailure: offline)
        == start.addingTimeInterval(240)
    )
  }

  @Test("Throttled outcomes reschedule at eligibility")
  func throttledNextRefresh() {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let next = start.addingTimeInterval(1_234)
    #expect(policy.nextRefreshDate(after: .throttled(nextEligibleAt: next), now: start) == next)
  }

  @Test(
    "Retryable failures reschedule after the retry interval",
    arguments: [
      SyncFailureCategory.deviceLocked, .offline, .timeout, .dnsFailure, .connectionLost,
      .deadlineExceeded,
    ])
  func retryNextRefresh(category: SyncFailureCategory) {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let report = report(startedAt: start, outboundFailure: category)
    let now = start.addingTimeInterval(20)
    #expect(
      policy.nextRefreshDate(after: .performed(report), now: now) == now.addingTimeInterval(900))
  }

  @Test("Cancelled runs reschedule after the retry interval without bypassing the gate")
  func cancelledNextRefresh() {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let cancelled = BidirectionalSyncReport(
      trigger: .appRefresh,
      outbound: nil,
      inbound: nil,
      setupFailureCategory: .cancelled,
      startedAt: start,
      finishedAt: start
    )
    let now = start.addingTimeInterval(20)
    #expect(
      policy.nextRefreshDate(after: .performed(cancelled), now: now)
        == now.addingTimeInterval(900))
    #expect(!BackgroundSchedulePolicy.retryCategories.contains(.cancelled))
  }

  @Test("A cancelled last failure makes automatic triggers eligible at the retry allowance")
  func cancelledFailureRetryAllowance() {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let cancelled = SyncStatusFailure(metricID: nil, category: .cancelled, at: start)
    let retryEligible = start.addingTimeInterval(720)

    #expect(
      policy.automaticEligibleAt(lastAttemptedAt: start, lastFailure: cancelled) == retryEligible)
    #expect(
      policy.shouldThrottle(
        trigger: .healthKitObserver,
        lastAttemptedAt: start,
        lastFailure: cancelled,
        now: start.addingTimeInterval(60)
      ) == retryEligible
    )
    #expect(
      policy.shouldThrottle(
        trigger: .healthKitObserver,
        lastAttemptedAt: start,
        lastFailure: cancelled,
        now: retryEligible
      ) == nil
    )
    #expect(
      policy.initialRefreshDate(
        lastAttemptedAt: start, lastFailure: cancelled, now: start.addingTimeInterval(60)
      ) == start.addingTimeInterval(60).addingTimeInterval(900)
    )
  }

  @Test("Other performed outcomes reschedule at eligibility from the run start")
  func performedNextRefresh() {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let success = report(startedAt: start, outboundFailure: nil)
    let failed = report(startedAt: start, outboundFailure: .unauthorized)
    let now = start.addingTimeInterval(20)
    #expect(
      policy.nextRefreshDate(after: .performed(success), now: now)
        == start.addingTimeInterval(3_000))
    #expect(
      policy.nextRefreshDate(after: .performed(failed), now: now) == start.addingTimeInterval(3_000)
    )
    let late = start.addingTimeInterval(4_000)
    #expect(policy.nextRefreshDate(after: .performed(success), now: late) == late)
  }

  @Test("Initial refresh follows the persisted attempt and failure")
  func initialRefresh() {
    let policy = BackgroundSchedulePolicy(frequency: .batterySaver)
    let now = start.addingTimeInterval(60)
    #expect(
      policy.initialRefreshDate(lastAttemptedAt: nil, lastFailure: nil, now: now)
        == now.addingTimeInterval(900))
    #expect(
      policy.initialRefreshDate(lastAttemptedAt: start, lastFailure: nil, now: now)
        == start.addingTimeInterval(3_000)
    )
    let offline = SyncStatusFailure(metricID: nil, category: .offline, at: start)
    #expect(
      policy.initialRefreshDate(lastAttemptedAt: start, lastFailure: offline, now: now)
        == now.addingTimeInterval(900)
    )
  }

  @Test("Report failure categories include setup, outbound and inbound")
  func reportCategories() {
    let report = BidirectionalSyncReport(
      trigger: .appRefresh,
      outbound: SyncReport(
        trigger: .appRefresh, attemptedMetrics: 1, synchronizedMetrics: 0, skippedMetrics: 0,
        failures: [.init(metricID: .steps, category: .offline)], startedAt: start, finishedAt: start
      ),
      inbound: InboundSyncReport(
        trigger: .appRefresh, attemptedPairings: 1, savedPairings: 0, skippedPairings: 0,
        failures: [.init(pairingID: nil, category: .validation)], startedAt: start,
        finishedAt: start
      ),
      setupFailureCategory: .cancelled,
      startedAt: start,
      finishedAt: start
    )
    #expect(report.failureCategories == [.cancelled, .offline, .validation])
  }

  private func report(startedAt: Date, outboundFailure: SyncFailureCategory?)
    -> BidirectionalSyncReport
  {
    BidirectionalSyncReport(
      trigger: .appRefresh,
      outbound: SyncReport(
        trigger: .appRefresh,
        attemptedMetrics: 1,
        synchronizedMetrics: outboundFailure == nil ? 1 : 0,
        skippedMetrics: 0,
        failures: outboundFailure.map { [.init(metricID: nil, category: $0)] } ?? [],
        startedAt: startedAt,
        finishedAt: startedAt
      ),
      inbound: nil,
      startedAt: startedAt,
      finishedAt: startedAt
    )
  }
}
