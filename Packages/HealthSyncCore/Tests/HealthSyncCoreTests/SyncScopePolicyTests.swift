import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sync scope policy")
struct SyncScopePolicyTests {
  /// 2026-09-19 20:30:00 UTC.
  private static let now = Date(timeIntervalSince1970: 1_788_035_400)
  private static let selected: Set<MetricID> = [.steps, .bodyMass, .restingHeartRate, .distance]
  /// `MetricRegistry.selectable` order, filtered to `selected`.
  private static let selectedOrder: [MetricID] = [.steps, .distance, .bodyMass, .restingHeartRate]
  private static let everythingFresh: [MetricID: TimeInterval] = [
    .steps: 60, .distance: 60, .bodyMass: 60, .restingHeartRate: 60,
  ]
  /// Stands in for the medication object type until `HealthObjectTypeID` gains one.
  private static let medicationObjectType = HealthObjectTypeID.insulinDelivery

  private let policy = SyncScopePolicy()
  private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private static func freshness(
    checkedAgo: [MetricID: TimeInterval] = [:],
    fullSweepAgo: TimeInterval? = nil,
    rotationOffset: Int = 0
  ) -> MetricFreshnessSnapshot {
    MetricFreshnessSnapshot(
      lastCheckedAt: checkedAgo.mapValues { now.addingTimeInterval(-$0) },
      lastFullSweepAt: fullSweepAgo.map { now.addingTimeInterval(-$0) },
      rotationOffset: rotationOffset
    )
  }

  private func scope(
    trigger: SyncTrigger = .healthKitObserver,
    selected: Set<MetricID> = SyncScopePolicyTests.selected,
    changedTypes: Set<HealthObjectTypeID> = [.stepCount],
    changedTypesKnown: Bool = true,
    freshness: MetricFreshnessSnapshot,
    frequency: BackgroundSyncFrequency = .balanced,
    now: Date = SyncScopePolicyTests.now,
    calendar: Calendar? = nil,
    policy: SyncScopePolicy? = nil
  ) -> SyncScope {
    (policy ?? self.policy).scope(
      trigger: trigger,
      selected: selected,
      changedTypes: changedTypes,
      changedTypesKnown: changedTypesKnown,
      freshness: freshness,
      frequency: frequency,
      now: now,
      calendar: calendar ?? utc
    )
  }

  @Test(
    "Full-sweep triggers cover every selected metric",
    arguments: [SyncTrigger.appRefresh, .manual, .pullToRefresh, .shortcut, .background]
  )
  func fullSweepTriggersCoverEverySelectedMetric(trigger: SyncTrigger) {
    #expect(trigger.isFullSweepTrigger)

    let scope = scope(
      trigger: trigger,
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 60)
    )

    #expect(scope.isFullSweep)
    #expect(scope.metrics == Self.selected)
    #expect(scope.orderedMetrics == Self.selectedOrder)
    #expect(scope.reason == .trigger)
    #expect(scope.includesMedications)
  }

  @Test("An observer wake is scoped, never a full-sweep trigger")
  func observerIsNotAFullSweepTrigger() {
    #expect(!SyncTrigger.healthKitObserver.isFullSweepTrigger)
  }

  @Test("The first observer run of a process is a full sweep")
  func firstRunAfterLaunchIsAFullSweep() {
    let scope = scope(
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: nil))

    #expect(scope.isFullSweep)
    #expect(scope.metrics == Self.selected)
    #expect(scope.reason == .firstRunAfterLaunch)
    #expect(scope.includesMedications)
  }

  @Test("An observer run sweeps once the sweep interval has elapsed")
  func sweepIsDueAfterTheSweepInterval() {
    let scope = scope(
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 3_600))

    #expect(scope.isFullSweep)
    #expect(scope.metrics == Self.selected)
    #expect(scope.reason == .sweepDue)
  }

  @Test("An observer run stays scoped just before the sweep interval elapses")
  func sweepIsNotDueJustBeforeTheSweepInterval() {
    let scope = scope(
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 3_599))

    #expect(!scope.isFullSweep)
    #expect(scope.metrics == [.steps])
    #expect(scope.reason == .changedTypes)
  }

  /// Four background cycles, floored at half an hour and capped at a day: Responsive's four
  /// cycles are 20 minutes, raised to the floor; Daily's are four days, cut to the ceiling.
  @Test(
    "The sweep interval is four background cycles, clamped at both ends",
    arguments: zip(
      BackgroundSyncFrequency.allCases,
      [30 * 60, 60 * 60, 4 * 60 * 60, 24 * 60 * 60] as [TimeInterval]
    )
  )
  func sweepIntervalIsFourBackgroundCycles(
    frequency: BackgroundSyncFrequency,
    expected: TimeInterval
  ) {
    #expect(policy.sweepInterval(for: frequency) == expected)
  }

  /// The same gap between wakes decides differently on different cadences, which is the whole
  /// point of deriving the interval: on a phone iOS wakes hours apart, a fixed hour made every
  /// wake a sweep and no scoped run ever happened.
  @Test(
    "A wake 90 minutes after the last sweep sweeps on Balanced and stays scoped on Battery Saver"
  )
  func theSweepCadenceFollowsTheConfiguredCadence() {
    let freshness = Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 90 * 60)

    let balanced = scope(freshness: freshness, frequency: .balanced)
    let batterySaver = scope(freshness: freshness, frequency: .batterySaver)

    #expect(balanced.isFullSweep)
    #expect(balanced.reason == .sweepDue)
    #expect(!batterySaver.isFullSweep)
    #expect(batterySaver.metrics == [.steps])
    #expect(batterySaver.reason == .changedTypes)
  }

  /// 45 minutes is past Responsive's floored half hour but short of Balanced's hour.
  @Test("A wake 45 minutes after the last sweep sweeps on Responsive and stays scoped on Balanced")
  func aShorterCadenceSweepsSooner() {
    let freshness = Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 45 * 60)

    let responsive = scope(freshness: freshness, frequency: .responsive)
    let balanced = scope(freshness: freshness, frequency: .balanced)

    #expect(responsive.isFullSweep)
    #expect(responsive.reason == .sweepDue)
    #expect(!balanced.isFullSweep)
    #expect(balanced.reason == .changedTypes)
  }

  @Test("A local day rollover forces a full sweep")
  func dayRolloverForcesAFullSweep() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
    let formatter = ISO8601DateFormatter()
    let lastFullSweepAt = try #require(formatter.date(from: "2026-09-18T23:30:00+02:00"))
    let now = try #require(formatter.date(from: "2026-09-19T00:10:00+02:00"))

    let scope = scope(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: Dictionary(
          uniqueKeysWithValues: Self.selected.map { ($0, now.addingTimeInterval(-300)) }),
        lastFullSweepAt: lastFullSweepAt
      ),
      now: now,
      calendar: calendar
    )

    #expect(scope.isFullSweep)
    #expect(scope.metrics == Self.selected)
    #expect(scope.reason == .dayRollover)
  }

  @Test("The day rollover is judged in the calendar's own time zone")
  func dayRolloverUsesTheCalendarTimeZone() throws {
    let formatter = ISO8601DateFormatter()
    let lastFullSweepAt = try #require(formatter.date(from: "2026-09-18T23:30:00+02:00"))
    let now = try #require(formatter.date(from: "2026-09-19T00:10:00+02:00"))

    // Both instants fall on 18 September in UTC, so no day has rolled over there.
    let scope = scope(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: Dictionary(
          uniqueKeysWithValues: Self.selected.map { ($0, now.addingTimeInterval(-300)) }),
        lastFullSweepAt: lastFullSweepAt
      ),
      now: now
    )

    #expect(!scope.isFullSweep)
    #expect(scope.metrics == [.steps])
    #expect(scope.reason == .changedTypes)
  }

  @Test("Sweep and freshness intervals measure elapsed time across a DST transition")
  func intervalsMeasureElapsedTimeAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
    let formatter = ISO8601DateFormatter()
    // Zurich clocks jump 02:00 → 03:00, so these wall times are forty minutes apart.
    let lastFullSweepAt = try #require(formatter.date(from: "2026-03-29T01:30:00+01:00"))
    let now = try #require(formatter.date(from: "2026-03-29T03:10:00+02:00"))

    let scope = scope(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: Dictionary(
          uniqueKeysWithValues: Self.selected.map { ($0, lastFullSweepAt) }),
        lastFullSweepAt: lastFullSweepAt
      ),
      now: now,
      calendar: calendar
    )

    #expect(!scope.isFullSweep)
    #expect(scope.metrics == [.steps])
    #expect(scope.reason == .changedTypes)
  }

  @Test(
    "A change signal that names no usable type forces a full sweep",
    arguments: [(false, Set<HealthObjectTypeID>([.stepCount])), (true, Set())]
  )
  func unusableChangeSignalForcesAFullSweep(
    changedTypesKnown: Bool, changedTypes: Set<HealthObjectTypeID>
  ) {
    let scope = scope(
      changedTypes: changedTypes,
      changedTypesKnown: changedTypesKnown,
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 60)
    )

    #expect(scope.isFullSweep)
    #expect(scope.metrics == Self.selected)
    #expect(scope.reason == .unknownChange)
  }

  @Test("A scoped run covers the changed types only, in registry order")
  func scopedRunCoversTheChangedTypes() {
    let scope = scope(
      freshness: Self.freshness(
        checkedAgo: Self.everythingFresh, fullSweepAgo: 60, rotationOffset: 2))

    #expect(!scope.isFullSweep)
    #expect(scope.metrics == [.steps])
    #expect(scope.orderedMetrics == [.steps])
    #expect(scope.reason == .changedTypes)
    #expect(!scope.includesMedications)
  }

  @Test("A scoped run covers every metric of a changed type, not just the first")
  func scopedRunCoversEveryMetricOfAChangedType() {
    // Three selected metrics share the sleep analysis object type.
    let selected = Self.selected.union([.asleepTime, .wakeTime, .sleepDetails])
    var checkedAgo = Self.everythingFresh
    for metric in [MetricID.asleepTime, .wakeTime, .sleepDetails] { checkedAgo[metric] = 60 }

    let scope = scope(
      selected: selected,
      changedTypes: [.sleepAnalysis],
      freshness: Self.freshness(checkedAgo: checkedAgo, fullSweepAgo: 60)
    )

    #expect(!scope.isFullSweep)
    #expect(scope.orderedMetrics == [.asleepTime, .wakeTime, .sleepDetails])
    #expect(scope.reason == .changedTypes)
  }

  @Test("A scoped run whose changed types match no selected metric covers nothing")
  func scopedRunWithoutMatchingMetricsIsEmpty() {
    let scope = scope(
      changedTypes: [.mindfulSession],
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 60)
    )

    #expect(!scope.isFullSweep)
    #expect(scope.orderedMetrics.isEmpty)
    #expect(scope.metrics.isEmpty)
    #expect(scope.reason == .changedTypes)
  }

  @Test("A scoped run also covers metrics past the freshness interval")
  func scopedRunAddsStaleMetrics() {
    var checkedAgo = Self.everythingFresh
    checkedAgo[.bodyMass] = 3_601

    let scope = scope(
      freshness: Self.freshness(checkedAgo: checkedAgo, fullSweepAgo: 60, rotationOffset: 1))

    #expect(!scope.isFullSweep)
    #expect(scope.metrics == [.steps, .bodyMass])
    // Scoped runs do not rotate, whatever the stored offset.
    #expect(scope.orderedMetrics == [.steps, .bodyMass])
    #expect(scope.reason == .staleMetrics)
  }

  @Test("A scoped run always covers metrics that have never been checked")
  func scopedRunAlwaysIncludesNeverCheckedMetrics() {
    let scope = scope(
      freshness: Self.freshness(checkedAgo: [.steps: 60], fullSweepAgo: 60))

    #expect(!scope.isFullSweep)
    #expect(scope.metrics == Self.selected)
    #expect(scope.reason == .staleMetrics)
  }

  @Test("A scoped run includes medications when the medication type changed")
  func scopedRunIncludesMedicationsWhenTheMedicationTypeChanged() {
    let scope = scope(
      changedTypes: [.stepCount, Self.medicationObjectType],
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 60),
      policy: SyncScopePolicy(medicationObjectType: Self.medicationObjectType)
    )

    #expect(!scope.isFullSweep)
    #expect(scope.metrics == [.steps])
    #expect(scope.includesMedications)
  }

  @Test("A scoped run excludes medications when no medication type is configured")
  func scopedRunExcludesMedicationsWithoutAConfiguredType() {
    let scope = scope(
      changedTypes: [.stepCount, Self.medicationObjectType],
      freshness: Self.freshness(checkedAgo: Self.everythingFresh, fullSweepAgo: 60)
    )

    #expect(!scope.isFullSweep)
    #expect(!scope.includesMedications)
  }

  @Test("Only metrics past the starvation interval are starved")
  func starvedMetricsArePastTheStarvationInterval() {
    let freshness = Self.freshness(
      checkedAgo: [.steps: 7_200, .distance: 60, .bodyMass: 7_199, .restingHeartRate: 10_800],
      fullSweepAgo: 60
    )

    let starved = policy.starvedMetrics(
      selected: Self.selected,
      freshness: freshness,
      hasRun: true,
      frequency: .balanced,
      now: Self.now
    )

    #expect(starved == [.steps, .restingHeartRate])
  }

  /// Battery Saver wakes an hour apart, so two freshness intervals is still the right threshold:
  /// a metric checked by the previous wake is fresh, and one that missed two wakes is not.
  @Test("Battery Saver keeps the two-hour threshold")
  func batterySaverKeepsTheTwoHourThreshold() {
    let freshness = Self.freshness(
      checkedAgo: [.steps: 7_199, .distance: 7_200, .bodyMass: 60, .restingHeartRate: 60],
      fullSweepAgo: 60
    )

    let starved = policy.starvedMetrics(
      selected: Self.selected,
      freshness: freshness,
      hasRun: true,
      frequency: .batterySaver,
      now: Self.now
    )

    #expect(starved == [.distance])
  }

  /// A fixed two hours would report the whole selection starved on every Daily sweep: the last
  /// check is written at the end of the previous run, a day earlier by design.
  @Test("Daily scales the threshold to its own cadence")
  func dailyScalesTheThresholdToItsCadence() {
    let freshness = Self.freshness(
      checkedAgo: [
        .steps: 7_200, .distance: 86_400, .bodyMass: 172_799, .restingHeartRate: 172_800,
      ],
      fullSweepAgo: 60
    )

    let starved = policy.starvedMetrics(
      selected: Self.selected,
      freshness: freshness,
      hasRun: true,
      frequency: .daily,
      now: Self.now
    )

    #expect(starved == [.restingHeartRate])
  }

  /// A selection persisted by an older app version can name a metric this one no longer offers.
  /// Counting it would leave the audit permanently non-zero with nothing a user could do.
  @Test("A selected metric the registry no longer offers is never starved")
  func metricOutsideTheRegistryIsNotStarved() {
    let starved = policy.starvedMetrics(
      selected: [.steps, .netCalories],
      freshness: Self.freshness(checkedAgo: [.steps: 60], fullSweepAgo: 60),
      hasRun: true,
      frequency: .balanced,
      now: Self.now
    )

    #expect(starved.isEmpty)
  }

  @Test("Never-checked metrics are not starved before anything has run")
  func neverCheckedMetricsAreNotStarvedBeforeAnythingRuns() {
    let starved = policy.starvedMetrics(
      selected: Self.selected,
      freshness: Self.freshness(),
      hasRun: false,
      frequency: .balanced,
      now: Self.now
    )

    #expect(starved.isEmpty)
  }

  @Test("Never-checked metrics are starved once a full sweep has completed")
  func neverCheckedMetricsAreStarvedAfterAFullSweep() {
    let starved = policy.starvedMetrics(
      selected: Self.selected,
      freshness: Self.freshness(checkedAgo: [.steps: 60], fullSweepAgo: 60),
      hasRun: true,
      frequency: .balanced,
      now: Self.now
    )

    #expect(starved == [.distance, .bodyMass, .restingHeartRate])
  }

  /// A sweep the budget always truncates never completes, so gating on a completed sweep would
  /// hide exactly the metrics such a sweep never reaches.
  @Test("Never-checked metrics are starved once any run has checked something")
  func neverCheckedMetricsAreStarvedAfterAnyCheck() {
    let starved = policy.starvedMetrics(
      selected: Self.selected,
      freshness: Self.freshness(checkedAgo: [.steps: 60]),
      hasRun: false,
      frequency: .balanced,
      now: Self.now
    )

    #expect(starved == [.distance, .bodyMass, .restingHeartRate])
  }

  /// Runs whose only reached metric always fails, and a freshness store that cannot be read,
  /// both leave the snapshot empty forever. The audit has to see them.
  @Test("Never-checked metrics are starved once the app has run, whatever freshness says")
  func neverCheckedMetricsAreStarvedOnceTheAppHasRun() {
    let starved = policy.starvedMetrics(
      selected: Self.selected,
      freshness: MetricFreshnessSnapshot(),
      hasRun: true,
      frequency: .balanced,
      now: Self.now
    )

    #expect(starved == Self.selected)
  }

  @Test("A full sweep starts at the rotation offset and wraps")
  func fullSweepStartsAtTheRotationOffset() {
    let scope = scope(
      trigger: .appRefresh,
      freshness: Self.freshness(
        checkedAgo: Self.everythingFresh, fullSweepAgo: 60, rotationOffset: 2)
    )

    #expect(scope.metrics == Self.selected)
    #expect(scope.orderedMetrics == [.bodyMass, .restingHeartRate, .steps, .distance])
  }

  @Test("A rotation offset beyond the selection wraps around it")
  func rotationOffsetBeyondTheSelectionWraps() {
    let scope = scope(
      trigger: .appRefresh,
      freshness: Self.freshness(
        checkedAgo: Self.everythingFresh, fullSweepAgo: 60, rotationOffset: 5)
    )

    #expect(scope.orderedMetrics == [.distance, .bodyMass, .restingHeartRate, .steps])
  }

  @Test("The next rotation offset advances past the last collected metric")
  func nextRotationOffsetAdvancesPastTheLastCollectedMetric() {
    let next = policy.nextRotationOffset(
      after: [.bodyMass], selectedOrder: Self.selectedOrder, previous: 2)

    #expect(next == 3)
  }

  @Test("The next rotation offset wraps to zero at the end of the order")
  func nextRotationOffsetWrapsToZero() {
    let next = policy.nextRotationOffset(
      after: [.bodyMass, .restingHeartRate], selectedOrder: Self.selectedOrder, previous: 2)

    #expect(next == 0)
  }

  @Test("The rotation offset stands still when nothing was collected")
  func nextRotationOffsetStandsStillWithoutProgress() {
    let next = policy.nextRotationOffset(
      after: [], selectedOrder: Self.selectedOrder, previous: 2)

    #expect(next == 2)
  }

  @Test("The canonical order of a selection follows the registry")
  func canonicalOrderFollowsTheRegistry() {
    #expect(SyncScopePolicy.orderedSelection(Self.selected) == Self.selectedOrder)
  }
}
