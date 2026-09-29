import Foundation
import Testing

@testable import HealthSyncCore

/// The coordinator is where the scope policy, the freshness store and the outbound run meet: it
/// decides what a run covers, tells the outbound coordinator, and records what the run touched so
/// the next run can leave it alone.
@Suite("Scope resolution")
struct ScopeResolutionTests {
  /// 2026-09-19 20:30:00 UTC.
  private let now = Date(timeIntervalSince1970: 1_788_035_400)
  private let selection: Set<MetricID> = [.steps, .bodyMass, .restingHeartRate]
  /// `MetricRegistry.selectable` order, filtered to `selection`.
  private let selectionOrder: [MetricID] = [.steps, .bodyMass, .restingHeartRate]
  /// The starvation threshold at the fixture's configured cadence.
  private static let balancedStarvationInterval = SyncScopePolicy()
    .starvationInterval(for: .balanced)
  /// The sweep interval at the fixture's configured cadence.
  private static let balancedSweepInterval = SyncScopePolicy().sweepInterval(for: .balanced)

  @Test("An observer run with changed types covers only those metrics")
  func changedTypesScopeTheRun() async {
    let fixture = fixture(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: [
          .steps: now.addingTimeInterval(-60),
          .bodyMass: now.addingTimeInterval(-60),
          .restingHeartRate: now.addingTimeInterval(-60),
        ],
        lastFullSweepAt: now.addingTimeInterval(-60)
      )
    )

    guard
      case .performed = await fixture.coordinator.sync(
        trigger: .healthKitObserver,
        changedTypes: [.stepCount]
      )
    else {
      Issue.record("Expected a performed run")
      return
    }

    #expect(await fixture.outbound.requestedMetrics == [[.steps]])
    #expect(await fixture.outbound.collectionOrders == [[.steps]])
    #expect(await fixture.outbound.medicationFlags == [false])
    let event = await fixture.statusStore.snapshot().recentEvents.last
    #expect(event?.scopeReason == "changedTypes")
    #expect(event?.requestedMetrics == 1)
    #expect(event?.changedTypes == 1)
  }

  @Test("An observer run past the sweep interval covers the whole selection")
  func sweepDueCoversEverything() async {
    let fixture = fixture(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: [.steps: now.addingTimeInterval(-60)],
        lastFullSweepAt: now.addingTimeInterval(-Self.balancedSweepInterval)
      )
    )

    guard
      case .performed = await fixture.coordinator.sync(
        trigger: .healthKitObserver,
        changedTypes: [.stepCount]
      )
    else {
      Issue.record("Expected a performed run")
      return
    }

    #expect(await fixture.outbound.requestedMetrics == [selection])
    #expect(await fixture.outbound.collectionOrders == [selectionOrder])
    #expect(await fixture.outbound.medicationFlags == [true])
    #expect(await fixture.statusStore.snapshot().recentEvents.last?.scopeReason == "sweepDue")
  }

  @Test("A run records a check for what it collected and a send for what it synchronized")
  func runRecordsFreshness() async throws {
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(
        collected: [.steps, .bodyMass],
        synchronized: [.steps]
      )
    )

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    let freshness = try await fixture.freshnessStore.snapshot()
    #expect(freshness.lastCheckedAt == [.steps: now, .bodyMass: now])
    #expect(freshness.lastSentAt == [.steps: now])
  }

  @Test("A metric whose value never reached Health Bridge stays stale for the next run")
  func unsentMetricStaysStale() async throws {
    let store = InMemoryMetricFreshnessStore()
    // `.bodyMass` is collected with a value the deadline then abandons before it is sent.
    let outbound = RecordingOutboundCoordinator(unsent: [.bodyMass])
    let fixture = fixture(outbound: outbound, freshnessStore: store)

    _ = await fixture.coordinator.sync(trigger: .manual)

    // Stamping a check for data that is still on the phone would call it fresh for the whole
    // freshness interval, and the changed-type ledger that would have covered it was drained by
    // the very run that failed to send it.
    let afterTheSweep = await store.snapshot()
    #expect(afterTheSweep.lastCheckedAt[.bodyMass] == nil)
    #expect(afterTheSweep.lastCheckedAt[.steps] == now)

    fixture.clock.set(now.addingTimeInterval(20 * 60))
    _ = await fixture.coordinator.sync(trigger: .healthKitObserver, changedTypes: [.stepCount])

    // Stale, so the next scoped run covers it without needing the ledger at all.
    #expect(await outbound.requestedMetrics.last == [.steps, .bodyMass])
  }

  @Test("A metric whose query failed stays stale so the next run retries it")
  func failedMetricStaysStale() async throws {
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(
        collected: [.steps, .bodyMass],
        synchronized: [.steps],
        failures: [.init(metricID: .restingHeartRate, category: .healthKit)]
      )
    )

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    #expect(try await fixture.freshnessStore.snapshot().lastCheckedAt[.restingHeartRate] == nil)
  }

  @Test("A sweep that deferred nothing completes and advances the rotation offset")
  func completeSweepAdvancesRotation() async throws {
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(
        collected: [.steps, .bodyMass],
        synchronized: [.steps, .bodyMass]
      )
    )

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    let freshness = try await fixture.freshnessStore.snapshot()
    #expect(freshness.lastFullSweepAt == now)
    // `.bodyMass` is index 1 of the selection order, so the next sweep starts at index 2.
    #expect(freshness.rotationOffset == 2)
  }

  @Test("A sweep that deferred metrics stays due")
  func truncatedSweepStaysDue() async throws {
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(
        collected: [.steps],
        synchronized: [.steps],
        deferredMetrics: 2
      )
    )

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    let freshness = try await fixture.freshnessStore.snapshot()
    #expect(freshness.lastFullSweepAt == nil)
    #expect(freshness.lastCheckedAt == [.steps: now])
  }

  @Test("A sweep a locked device stopped does not count as a completed sweep")
  func lockedSweepDoesNotComplete() async throws {
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(
        collected: [],
        synchronized: [],
        failures: [.init(metricID: nil, category: .deviceLocked)]
      )
    )

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    // The run deferred nothing and failed no single metric, but it swept nothing either.
    #expect(try await fixture.freshnessStore.snapshot().lastFullSweepAt == nil)
  }

  @Test("A sweep that collected nothing does not complete")
  func sweepThatCollectedNothingDoesNotComplete() async throws {
    // A run that failed before it could look at a single metric — a blank webhook secret, say —
    // defers nothing and locks nothing, yet it swept nothing either. Stamping it as a completed
    // sweep would suppress the next sweep for an hour on the strength of a run that collected
    // nothing at all.
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(
        collected: [],
        synchronized: [],
        failures: [.init(metricID: nil, category: .configuration)]
      )
    )

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    #expect(try await fixture.freshnessStore.snapshot().lastFullSweepAt == nil)
  }

  @Test("Consecutive truncated sweeps rotate until the selection is covered")
  func truncatedSweepsRotateThroughTheSelection() async throws {
    let store = InMemoryMetricFreshnessStore()
    let outbound = RecordingOutboundCoordinator(collectionBudget: 1)
    let fixture = fixture(outbound: outbound, freshnessStore: store)

    // Manual sweeps, so the background cadence does not throttle the second and third.
    for _ in 0..<3 {
      _ = await fixture.coordinator.sync(trigger: .manual)
    }

    // Each sweep starts where the last one stopped, so three one-metric sweeps cover all three.
    #expect(await outbound.collectionOrders.map { $0?.first } == selectionOrder.map { $0 })
    #expect(await Set(store.snapshot().lastCheckedAt.keys) == selection)
    // None of them completed, so the sweep stays due and the audit keeps watching.
    #expect(await store.snapshot().lastFullSweepAt == nil)
  }

  @Test("Sweeps rotate past a metric that always fails")
  func sweepsRotatePastAFailingMetric() async throws {
    let store = InMemoryMetricFreshnessStore()
    let outbound = RecordingOutboundCoordinator(collectionBudget: 1, budgetedMetricsFail: true)
    let fixture = fixture(outbound: outbound, freshnessStore: store)

    for _ in 0..<3 {
      _ = await fixture.coordinator.sync(trigger: .manual)
    }

    // The run reached one metric and failed it, so it recorded no check — but it still made
    // progress through the selection, or that metric would pin every later sweep to itself.
    #expect(await outbound.collectionOrders.map { $0?.first } == selectionOrder.map { $0 })
    #expect(await store.snapshot().lastCheckedAt.isEmpty)
  }

  @Test("Starvation is audited from past attempts, not from a freshness store that never wrote")
  func starvationSurvivesAnUnreadableFreshnessStore() async throws {
    let fixture = fixture(
      freshnessStore: FailingMetricFreshnessStore(failsRead: true),
      status: SyncStatusSnapshot(lastAttemptedAt: now.addingTimeInterval(-86_400))
    )

    _ = await fixture.coordinator.sync(trigger: .manual)

    // Every wake sees an empty snapshot, so freshness alone would report nothing starved.
    #expect(await fixture.statusStore.snapshot().recentEvents.last?.starvedMetrics == 3)
  }

  @Test("The very first run reports nothing starved")
  func firstRunEverReportsNothingStarved() async throws {
    let fixture = fixture()

    _ = await fixture.coordinator.sync(trigger: .manual)

    #expect(await fixture.statusStore.snapshot().recentEvents.last?.starvedMetrics == 0)
  }

  @Test("A cancelled run does not record a completed sweep")
  func cancelledRunDoesNotCompleteASweep() async throws {
    let store = InMemoryMetricFreshnessStore()
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(delay: .milliseconds(200)),
      freshnessStore: store
    )

    let run = Task { await fixture.coordinator.sync(trigger: .appRefresh) }
    try await Task.sleep(for: .milliseconds(50))
    run.cancel()
    _ = await run.value

    // The run stopped scheduling collectors, so nothing was deferred either — but it swept
    // nothing it can vouch for. Its checks are still recorded; only the sweep date is withheld.
    #expect(await store.snapshot().lastFullSweepAt == nil)
  }

  @Test("A cancelled run still records the checks and the rotation it earned")
  func cancelledRunRecordsWhatItReached() async throws {
    let store = InMemoryMetricFreshnessStore()
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(collectionBudget: 1, suspendsAfterStart: true),
      freshnessStore: store
    )

    let run = Task { await fixture.coordinator.sync(trigger: .appRefresh) }
    await fixture.outbound.waitUntilSuspended()
    run.cancel()
    await fixture.outbound.releaseSuspendedRun()
    _ = await run.value

    // Throwing this away would restart the next sweep at the same offset, so a selection the
    // budget always truncates would never reach its tail.
    let freshness = await store.snapshot()
    #expect(freshness.lastCheckedAt == [.steps: now])
    #expect(freshness.rotationOffset == 1)
    #expect(freshness.lastFullSweepAt == nil)
  }

  @Test("A run drops freshness for metrics that are no longer selected")
  func runDropsDeselectedMetrics() async throws {
    let store = InMemoryMetricFreshnessStore(
      snapshot: MetricFreshnessSnapshot(
        lastCheckedAt: [.distance: now.addingTimeInterval(-60)],
        lastSentAt: [.distance: now.addingTimeInterval(-60)]
      )
    )
    let fixture = fixture(freshnessStore: store)

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    let freshness = await store.snapshot()
    #expect(freshness.lastCheckedAt[.distance] == nil)
    #expect(freshness.lastSentAt[.distance] == nil)
  }

  @Test("A full sweep reports how many selected metrics have gone unchecked")
  func fullSweepReportsStarvedMetrics() async {
    let fixture = fixture(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: [
          .steps: now.addingTimeInterval(-60),
          .bodyMass: now.addingTimeInterval(-Self.balancedStarvationInterval),
          .restingHeartRate: now.addingTimeInterval(-60),
        ],
        lastFullSweepAt: now.addingTimeInterval(-Self.balancedSweepInterval)
      )
    )

    _ = await fixture.coordinator.sync(trigger: .healthKitObserver, changedTypes: [.stepCount])

    #expect(await fixture.statusStore.snapshot().recentEvents.last?.starvedMetrics == 1)
  }

  @Test("A scoped run does not report starvation")
  func scopedRunOmitsStarvation() async {
    let fixture = fixture(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: [
          .steps: now.addingTimeInterval(-60),
          .bodyMass: now.addingTimeInterval(-60),
          .restingHeartRate: now.addingTimeInterval(-60),
        ],
        lastFullSweepAt: now.addingTimeInterval(-60)
      )
    )

    _ = await fixture.coordinator.sync(trigger: .healthKitObserver, changedTypes: [.stepCount])

    #expect(await fixture.statusStore.snapshot().recentEvents.last?.starvedMetrics == nil)
  }

  @Test("A window touch is the later of the last check and the last send")
  func windowTouchIsTheLaterOfCheckAndSend() async {
    let checked = now.addingTimeInterval(-600)
    let sent = now.addingTimeInterval(-1_200)
    let fixture = fixture(
      freshness: MetricFreshnessSnapshot(
        lastCheckedAt: [.steps: checked],
        lastSentAt: [.steps: sent, .bodyMass: sent]
      )
    )

    _ = await fixture.coordinator.sync(trigger: .appRefresh)

    // Gating on sends alone would re-query `.steps` on every wake for the rest of the day.
    #expect(await fixture.outbound.windowTouches == [[.steps: checked, .bodyMass: sent]])
  }

  @Test("A freshness read failure falls back to a full sweep and still runs")
  func freshnessReadFailureFallsBackToAFullSweep() async {
    let fixture = fixture(freshnessStore: FailingMetricFreshnessStore(failsRead: true))

    guard
      case .performed(let report) = await fixture.coordinator.sync(
        trigger: .healthKitObserver,
        changedTypes: [.stepCount]
      )
    else {
      Issue.record("Expected the run to go ahead without freshness data")
      return
    }

    #expect(report.succeeded)
    #expect(await fixture.outbound.requestedMetrics == [selection])
    #expect(
      await fixture.statusStore.snapshot().recentEvents.last?.scopeReason
        == "firstRunAfterLaunch"
    )
  }

  @Test("A freshness write failure is reported as a checkpoint failure")
  func freshnessWriteFailureIsACheckpointFailure() async {
    let fixture = fixture(freshnessStore: FailingMetricFreshnessStore(failsWrite: true))

    guard case .performed(let report) = await fixture.coordinator.sync(trigger: .appRefresh) else {
      Issue.record("Expected a performed run")
      return
    }

    #expect(report.setupFailureCategory == .checkpoint)
    #expect(report.outbound?.synchronizedMetrics == 3)
  }

  @Test("A run with nothing to record does not write freshness at all")
  func runWithNothingToRecordSkipsTheWrite() async {
    // A locked-device wake checks nothing, sends nothing, rotates nothing and sweeps nothing.
    // Writing it would cost a full encrypted read-modify-write for an unchanged document, on the
    // tightest-budget path there is. The store is one that fails every write, so a write that
    // was attempted shows up as a checkpoint failure.
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(
        collected: [],
        synchronized: [],
        failures: [.init(metricID: nil, category: .deviceLocked)]
      ),
      freshnessStore: FailingMetricFreshnessStore(failsWrite: true)
    )

    guard case .performed(let report) = await fixture.coordinator.sync(trigger: .appRefresh) else {
      Issue.record("Expected a performed run")
      return
    }

    #expect(report.setupFailureCategory == nil)
  }

  @Test("A full sweep does not join a scoped run that leaves medications out")
  func fullSweepDoesNotJoinAScopedRun() async throws {
    // Every metric is stale, so the scoped run happens to cover the whole selection — but it is
    // still scoped, and medications are not part of it.
    let fixture = fixture(
      outbound: RecordingOutboundCoordinator(delay: .milliseconds(300)),
      freshness: MetricFreshnessSnapshot(lastFullSweepAt: now.addingTimeInterval(-60))
    )

    let scoped = Task {
      await fixture.coordinator.sync(trigger: .healthKitObserver, changedTypes: [.stepCount])
    }
    try await Task.sleep(for: .milliseconds(50))
    let sweep = Task { await fixture.coordinator.sync(trigger: .manual) }

    _ = await scoped.value
    _ = await sweep.value

    #expect(await fixture.outbound.requestedMetrics == [selection, selection])
    #expect(await fixture.outbound.medicationFlags == [false, true])
  }

  @Test("A caller that waited out a run is resolved again from what that run recorded")
  func waitedOutCallerResolvesAgainstTheFinishedRun() async throws {
    let store = InMemoryMetricFreshnessStore(
      snapshot: MetricFreshnessSnapshot(lastFullSweepAt: now.addingTimeInterval(-60))
    )
    let outbound = RecordingOutboundCoordinator(delay: .milliseconds(300))
    let fixture = fixture(outbound: outbound, freshnessStore: store)

    // A scoped observer run — everything is stale, so it covers the whole selection — and then a
    // Sync Now that cannot join it and has to wait it out.
    let scoped = Task {
      await fixture.coordinator.sync(trigger: .healthKitObserver, changedTypes: [.stepCount])
    }
    try await Task.sleep(for: .milliseconds(50))
    let sweep = Task { await fixture.coordinator.sync(trigger: .manual) }
    _ = await scoped.value
    _ = await sweep.value

    // Resolving before the wait would hand the sweep the freshness from before the run it waited
    // for: it would re-send every daily metric that run just sent, and report the whole selection
    // starved on the very surface users are told to trust.
    let touches = await outbound.windowTouches.last
    let starved = await fixture.statusStore.snapshot().recentEvents.last?.starvedMetrics
    #expect(touches == [.steps: now, .bodyMass: now, .restingHeartRate: now])
    #expect(starved == 0)
  }

  @Test("A wake whose budget ran out while waiting is rescheduled when it is eligible again")
  func abandonedWakeUsesTheScheduleEligibility() async throws {
    let clock = MutableClock(now)
    let statusStore = DelayedSnapshotStatusStore(
      wrapping: InMemorySyncStatusStore(),
      delay: .milliseconds(200)
    )
    let outbound = RecordingOutboundCoordinator(delay: .milliseconds(400))
    let coordinator = BidirectionalSyncCoordinator(
      outbound: outbound,
      inbound: RecordingInboundCoordinator(),
      configurationStore: configurationStore(),
      statusStore: statusStore,
      freshnessStore: InMemoryMetricFreshnessStore(
        snapshot: MetricFreshnessSnapshot(
          lastCheckedAt: [
            .steps: now.addingTimeInterval(-60),
            .bodyMass: now.addingTimeInterval(-60),
            .restingHeartRate: now.addingTimeInterval(-60),
          ],
          lastFullSweepAt: now.addingTimeInterval(-60)
        )
      ),
      now: { clock.now }
    )

    // The sweep is not throttled: no attempt has been recorded when it looks. Its own eligibility
    // check is slow, so the observer run registers and records its attempt while it waits.
    let sweep = Task { await coordinator.sync(trigger: .appRefresh) }
    try await Task.sleep(for: .milliseconds(50))
    let observerStart = now.addingTimeInterval(5)
    clock.set(observerStart)
    let observer = Task {
      await coordinator.sync(trigger: .healthKitObserver, changedTypes: [.stepCount])
    }
    try await Task.sleep(for: .milliseconds(250))
    // The sweep's 25 s wake budget is gone before the observer run releases the coordinator.
    clock.set(now.addingTimeInterval(30))

    _ = await observer.value
    // Rescheduling at the abandoned wake would be throttled straight away: the observer run
    // attempted a sync 5 s into the wake, so Balanced eligibility runs from there.
    let eligibleAt = BackgroundSchedulePolicy(frequency: .balanced)
      .eligibleAt(lastAttemptedAt: observerStart)
    #expect(await sweep.value == .throttled(nextEligibleAt: eligibleAt!))
    #expect(await outbound.requestedMetrics == [[.steps]])
  }

  private func fixture(
    outbound: RecordingOutboundCoordinator? = nil,
    freshness: MetricFreshnessSnapshot = MetricFreshnessSnapshot(),
    freshnessStore: (any MetricFreshnessStore)? = nil,
    status: SyncStatusSnapshot = SyncStatusSnapshot()
  ) -> Fixture {
    let outbound = outbound ?? RecordingOutboundCoordinator()
    let store = freshnessStore ?? InMemoryMetricFreshnessStore(snapshot: freshness)
    let statusStore = InMemorySyncStatusStore(snapshot: status)
    let clock = MutableClock(now)
    return Fixture(
      coordinator: BidirectionalSyncCoordinator(
        outbound: outbound,
        inbound: RecordingInboundCoordinator(),
        configurationStore: configurationStore(),
        statusStore: statusStore,
        freshnessStore: store,
        now: { clock.now }
      ),
      outbound: outbound,
      statusStore: statusStore,
      freshnessStore: store,
      clock: clock
    )
  }

  private func configurationStore() -> InMemoryConfigurationStore {
    InMemoryConfigurationStore(
      configuration: AppConfiguration(
        baseURL: "https://ha.example.com",
        allowsConfirmedLocalHTTP: false,
        healthBridgeUserID: "oleh",
        selectedMetrics: selection,
        backgroundSyncEnabled: true,
        backgroundSyncFrequency: .balanced
      )
    )
  }

  private struct Fixture {
    let coordinator: BidirectionalSyncCoordinator
    let outbound: RecordingOutboundCoordinator
    let statusStore: InMemorySyncStatusStore
    let freshnessStore: any MetricFreshnessStore
    let clock: MutableClock
  }
}

private final class MutableClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) {
    self.date = date
  }

  var now: Date {
    lock.withLock { date }
  }

  func set(_ date: Date) {
    lock.withLock { self.date = date }
  }
}

private actor RecordingOutboundCoordinator: SyncCoordinating {
  private let delay: Duration
  private let collected: Set<MetricID>?
  private let synchronized: Set<MetricID>?
  private let deferredMetrics: Int
  /// Metrics the run collected a value for and never got an acknowledgement for, as an
  /// abandoned send leaves them: looked at, but not resolved.
  private let unsent: Set<MetricID>
  private let failures: [SyncFailureSummary]
  /// How many metrics the run's budget covers. The rest are deferred, as the send reserve does.
  private let collectionBudget: Int?
  /// Whether the metrics the budget covered fail rather than being collected.
  private let budgetedMetricsFail: Bool
  private let suspendsAfterStart: Bool
  private var startedWaiter: CheckedContinuation<Void, Never>?
  private var suspendedRun: CheckedContinuation<Void, Never>?
  private(set) var requestedMetrics: [Set<MetricID>] = []
  private(set) var medicationFlags: [Bool] = []
  private(set) var windowTouches: [[MetricID: Date]] = []
  private(set) var collectionOrders: [[MetricID]?] = []

  init(
    delay: Duration = .zero,
    collected: Set<MetricID>? = nil,
    synchronized: Set<MetricID>? = nil,
    deferredMetrics: Int = 0,
    unsent: Set<MetricID> = [],
    failures: [SyncFailureSummary] = [],
    collectionBudget: Int? = nil,
    budgetedMetricsFail: Bool = false,
    suspendsAfterStart: Bool = false
  ) {
    self.delay = delay
    self.collected = collected
    self.synchronized = synchronized
    self.deferredMetrics = deferredMetrics
    self.unsent = unsent
    self.failures = failures
    self.collectionBudget = collectionBudget
    self.budgetedMetricsFail = budgetedMetricsFail
    self.suspendsAfterStart = suspendsAfterStart
  }

  func waitUntilSuspended() async {
    if suspendedRun != nil { return }
    await withCheckedContinuation { startedWaiter = $0 }
  }

  func releaseSuspendedRun() {
    suspendedRun?.resume()
    suspendedRun = nil
  }

  func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?,
    includesMedications: Bool,
    lastWindowTouchAt: [MetricID: Date],
    orderedMetrics: [MetricID]?
  ) async -> SyncReport {
    let requested = metrics ?? []
    requestedMetrics.append(requested)
    medicationFlags.append(includesMedications)
    windowTouches.append(lastWindowTouchAt)
    collectionOrders.append(orderedMetrics)
    if suspendsAfterStart {
      await withCheckedContinuation {
        suspendedRun = $0
        startedWaiter?.resume()
        startedWaiter = nil
      }
    }
    try? await Task.sleep(for: delay)
    let date = Date(timeIntervalSince1970: 1_788_035_400)
    let budgeted = collectionBudget.map { Set((orderedMetrics ?? []).prefix($0)) }
    let reached = budgetedMetricsFail ? Set<MetricID>() : budgeted
    let collected = reached ?? collected ?? requested
    let synchronized = (reached ?? synchronized ?? requested).subtracting(unsent)
    let deferred = budgeted.map { requested.count - $0.count } ?? deferredMetrics
    let budgetFailures =
      budgetedMetricsFail
      ? (budgeted ?? []).map { SyncFailureSummary(metricID: $0, category: .healthKit) }
      : []
    let unsentFailures = unsent.intersection(collected).map {
      SyncFailureSummary(metricID: $0, category: .deadlineExceeded)
    }
    return SyncReport(
      trigger: trigger,
      attemptedMetrics: requested.count,
      synchronizedMetrics: synchronized.count,
      skippedMetrics: 0,
      failures: failures + budgetFailures + unsentFailures,
      startedAt: date,
      finishedAt: date,
      collectedMetrics: collected.count,
      deferredMetrics: deferred,
      collectedMetricIDs: collected,
      synchronizedMetricIDs: synchronized,
      // A collected metric is resolved unless its value never reached Health Bridge.
      resolvedMetricIDs: collected.subtracting(unsent)
    )
  }

  func sync(trigger: SyncTrigger, metrics: Set<MetricID>?) async -> SyncReport {
    await sync(
      trigger: trigger,
      metrics: metrics,
      deadline: nil,
      includesMedications: true,
      lastWindowTouchAt: [:],
      orderedMetrics: nil
    )
  }
}

private actor RecordingInboundCoordinator: InboundSyncCoordinating {
  func sync(trigger: SyncTrigger) async -> InboundSyncReport {
    let date = Date(timeIntervalSince1970: 1_788_035_400)
    return InboundSyncReport(
      trigger: trigger,
      attemptedPairings: 0,
      savedPairings: 0,
      skippedPairings: 0,
      failures: [],
      startedAt: date,
      finishedAt: date
    )
  }
}

private actor FailingMetricFreshnessStore: MetricFreshnessStore {
  private let failsRead: Bool
  private let failsWrite: Bool

  init(failsRead: Bool = false, failsWrite: Bool = false) {
    self.failsRead = failsRead
    self.failsWrite = failsWrite
  }

  func snapshot() throws -> MetricFreshnessSnapshot {
    if failsRead { throw Failure.expected }
    return MetricFreshnessSnapshot()
  }

  func record(_ update: MetricFreshnessUpdate) throws {
    try failIfWritesFail()
  }

  func reset() throws {
    try failIfWritesFail()
  }

  private func failIfWritesFail() throws {
    if failsWrite { throw Failure.expected }
  }

  private enum Failure: Error { case expected }
}

/// Delays only the first `snapshot()`, so a second caller can register a run while the first is
/// still deciding whether it is eligible to start one.
private actor DelayedSnapshotStatusStore: SyncStatusStore {
  private let wrapped: InMemorySyncStatusStore
  private let delay: Duration
  private var delayed = false

  init(wrapping wrapped: InMemorySyncStatusStore, delay: Duration) {
    self.wrapped = wrapped
    self.delay = delay
  }

  /// Reads first and delays afterwards, so the first caller acts on the status it saw before a
  /// second caller changed it.
  func snapshot() async -> SyncStatusSnapshot {
    let snapshot = await wrapped.snapshot()
    if !delayed {
      delayed = true
      try? await Task.sleep(for: delay)
    }
    return snapshot
  }

  func record(report: BidirectionalSyncReport) async throws {
    try await wrapped.record(report: report)
  }

  func record(report: SyncReport) async throws {
    try await wrapped.record(report: report)
  }

  func recordAttempt(trigger: SyncTrigger, at date: Date) async throws {
    try await wrapped.recordAttempt(trigger: trigger, at: date)
  }

  func recordThrottledWake() async throws {
    try await wrapped.recordThrottledWake()
  }

  func recordInterruptedAttemptIfNeeded() async throws -> SyncStatusEvent? {
    try await wrapped.recordInterruptedAttemptIfNeeded()
  }

  func setRegistration(
    _ state: BackgroundRegistrationState,
    for metric: MetricID
  ) async throws {
    try await wrapped.setRegistration(state, for: metric)
  }

  func reset() async throws {
    try await wrapped.reset()
  }
}
