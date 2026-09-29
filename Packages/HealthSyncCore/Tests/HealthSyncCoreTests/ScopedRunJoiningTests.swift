import Foundation
import Testing

@testable import HealthSyncCore

/// A caller may only take an in-flight run's report when that run covers everything the caller
/// asked for. Joining a narrower run is silent data loss: the caller's metrics are never
/// collected, yet it is told the sync succeeded.
@Suite("Scope-aware run joining")
struct ScopedRunJoiningTests {
  private let fixedDate = Date(timeIntervalSince1970: 1_788_035_400)
  /// Long enough for a second caller to reach the coordinator while the first run is in flight.
  private let runDelay = Duration.milliseconds(300)
  private let arrivalDelay = Duration.milliseconds(50)

  @Test(
    "Free sync completes while a paid start check is suspended",
    arguments: [SyncTrigger.manual, .pullToRefresh])
  func freeCallerDoesNotInheritDeniedPaidStart(trigger: SyncTrigger) async {
    let access = SuspendedPaidAccess()
    let outbound = ScopeRecordingOutboundCoordinator(suspendFirst: false)
    let coordinator = BidirectionalSyncCoordinator(
      outbound: outbound, inbound: ScopeRecordingInboundCoordinator(),
      configurationStore: InMemoryConfigurationStore(
        configuration: configuration(selectedMetrics: [.steps])),
      statusStore: InMemorySyncStatusStore(), paidAccess: access, now: { fixedDate })
    let paid = Task { await coordinator.sync(trigger: .shortcut) }
    await access.waitForCheck()
    // A bounded failure watchdog prevents a broken join from hanging the suite. Success must
    // happen before this releases the paid check; elapsed time never grants test success.
    let watchdog = Task {
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      await access.deny()
    }
    let manual = await coordinator.sync(trigger: trigger)
    #expect(await !access.wasReleased)
    guard case .performed = manual else {
      Issue.record("Free manual sync inherited a paid rejection")
      watchdog.cancel()
      await access.deny()
      _ = await paid.value
      return
    }
    watchdog.cancel()
    await access.deny()
    #expect(await paid.value == .requiresPurchase)
    #expect(await outbound.requestedMetrics == [[.steps]])
  }

  @Test("A broader Shortcut waiting behind an observer cannot start after revocation")
  func revokedShortcutWaitingBehindObserver() async throws {
    let access = JoiningPaidAccess()
    let store = JoiningConfigurationStore(configuration(selectedMetrics: [.steps]))
    let outbound = ScopeRecordingOutboundCoordinator()
    let inbound = ScopeRecordingInboundCoordinator()
    let base = BidirectionalSyncCoordinator(
      outbound: outbound, inbound: inbound, configurationStore: store,
      statusStore: InMemorySyncStatusStore(), paidAccess: access, now: { fixedDate })
    let coordinator = PaidSyncCoordinator(base: base, access: access)
    let observer = Task { await coordinator.sync(trigger: .healthKitObserver) }
    await outbound.waitUntilFirstRunSuspended()
    await store.save(configuration(selectedMetrics: [.steps, .bodyMass]))
    let shortcut = Task { await coordinator.sync(trigger: .shortcut) }
    // This read occurs inside the real coordinator, after the outer purchase gate.
    await store.waitForBroadRead()
    await access.revoke()
    await outbound.releaseFirstRun()
    _ = await observer.value
    #expect(await shortcut.value == .requiresPurchase)
    #expect(await outbound.requestedMetrics == [[.steps]])
    #expect(await inbound.triggers == [.healthKitObserver])
  }

  @Test("A caller covered by the active run joins it")
  func coveredCallerJoinsTheActiveRun() async throws {
    let sender = FakeHealthBridgeSender(delay: runDelay)
    let coordinator = try await makeCoordinator(query: populatedQuery(), sender: sender)

    let starter = Task {
      await coordinator.sync(trigger: .manual, metrics: [.steps, .bodyMass])
    }
    try await Task.sleep(for: arrivalDelay)
    let joiner = Task { await coordinator.sync(trigger: .manual, metrics: [.steps]) }

    let starterReport = await starter.value
    let joinerReport = await joiner.value

    #expect(starterReport == joinerReport)
    #expect(starterReport.attemptedMetrics == 2)
    #expect(await sender.batchSizes == [2])
  }

  @Test("A full-sweep caller joins a run that covers the whole selection")
  func fullSweepCallerJoinsAnEquivalentRun() async throws {
    let sender = FakeHealthBridgeSender(delay: runDelay)
    let coordinator = try await makeCoordinator(query: populatedQuery(), sender: sender)

    let starter = Task {
      await coordinator.sync(
        trigger: .appRefresh,
        metrics: [.steps, .bodyMass, .restingHeartRate],
        deadline: nil,
        includesMedications: true,
        lastWindowTouchAt: [:]
      )
    }
    try await Task.sleep(for: arrivalDelay)
    let joiner = Task { await coordinator.sync(trigger: .manual, metrics: nil) }

    let starterReport = await starter.value
    #expect(await joiner.value == starterReport)
    #expect(await sender.batchSizes == [3])
  }

  @Test("A caller the active run does not cover runs again after it")
  func uncoveredCallerRunsAgain() async throws {
    let query = try await populatedQuery()
    let sender = FakeHealthBridgeSender(delay: runDelay)
    let coordinator = try await makeCoordinator(query: query, sender: sender)

    let starter = Task { await coordinator.sync(trigger: .manual, metrics: [.steps]) }
    try await Task.sleep(for: arrivalDelay)
    let follower = Task {
      await coordinator.sync(trigger: .manual, metrics: [.steps, .bodyMass])
    }

    let starterReport = await starter.value
    let followerReport = await follower.value

    #expect(starterReport.attemptedMetrics == 1)
    #expect(followerReport.attemptedMetrics == 2)
    // The single-metric run sends on its own; the second run batches both of its metrics.
    #expect(await sender.batchSizes == [2])
    #expect(await sender.calls.count == 3)
    #expect(await sender.calls.filter { $0.metricID == .bodyMass }.count == 1)
  }

  @Test("A caller that needs medications does not join a run that leaves them out")
  func medicationCallerDoesNotJoinAMetricOnlyRun() async throws {
    let medications = FakeMedicationSyncCoordinator(
      report: MedicationSyncReport(
        attempted: true,
        synchronized: true,
        skipped: false,
        failure: nil
      )
    )
    let sender = FakeHealthBridgeSender(delay: runDelay)
    let coordinator = try await makeCoordinator(
      query: populatedQuery(),
      sender: sender,
      medicationCoordinator: medications,
      medicationEnabled: true
    )

    let starter = Task {
      await coordinator.sync(
        trigger: .healthKitObserver,
        metrics: [.steps, .bodyMass, .restingHeartRate],
        deadline: nil,
        includesMedications: false,
        lastWindowTouchAt: [:]
      )
    }
    try await Task.sleep(for: arrivalDelay)
    let follower = Task { await coordinator.sync(trigger: .manual, metrics: nil) }

    _ = await starter.value
    _ = await follower.value

    #expect(await medications.triggers == [.manual])
    #expect(await sender.batchSizes == [3, 3])
  }

  @Test("Cancelling a caller that joined an outbound run leaves the run intact")
  func joinerCancellationDoesNotCancelTheActiveRun() async throws {
    let sender = FakeHealthBridgeSender(delay: runDelay)
    let coordinator = try await makeCoordinator(query: populatedQuery(), sender: sender)

    let starter = Task {
      await coordinator.sync(trigger: .manual, metrics: [.steps, .bodyMass])
    }
    try await Task.sleep(for: arrivalDelay)
    let joiner = Task { await coordinator.sync(trigger: .manual, metrics: [.steps]) }
    try await Task.sleep(for: arrivalDelay)

    joiner.cancel()
    let starterReport = await starter.value
    _ = await joiner.value

    #expect(starterReport.synchronizedMetrics == 2)
    #expect(starterReport.failures.isEmpty)
    #expect(await sender.batchSizes == [2])
  }

  @Test("A bidirectional caller the active run does not cover gets its own run")
  func bidirectionalUncoveredCallerRunsAgain() async throws {
    let fixture = bidirectionalFixture()

    let observer = Task { await fixture.coordinator.sync(trigger: .healthKitObserver) }
    let sweep = try await widenedSweep(fixture)

    await fixture.outbound.releaseFirstRun()
    let observerOutcome = await observer.value
    let sweepOutcome = await sweep.value

    #expect(await fixture.outbound.requestedMetrics == [[.steps], [.steps, .bodyMass]])
    guard case .performed(let observerReport) = observerOutcome,
      case .performed(let sweepReport) = sweepOutcome
    else {
      Issue.record("Expected both callers to receive a performed run")
      return
    }
    #expect(observerReport.outbound?.attemptedMetrics == 1)
    #expect(sweepReport.outbound?.attemptedMetrics == 2)
  }

  @Test("A run that waited out another starts on a fresh clock, inside the wake's budget")
  func waitedOutRunStartsOnAFreshClock() async throws {
    let fixture = bidirectionalFixture()
    let wake = fixedDate.addingTimeInterval(720)
    let runStart = wake.addingTimeInterval(10)

    let observer = Task { await fixture.coordinator.sync(trigger: .healthKitObserver) }
    let sweep = try await widenedSweep(fixture)
    // Ten seconds of the sweep's 25 s wake budget go to waiting out the observer run.
    fixture.clock.set(runStart)

    await fixture.outbound.releaseFirstRun()
    _ = await observer.value
    let sweepOutcome = await sweep.value

    guard case .performed(let sweepReport) = sweepOutcome else {
      Issue.record("Expected the sweep to run after the observer run finished")
      return
    }
    #expect(sweepReport.startedAt == runStart)
    #expect(await fixture.statusStore.snapshot().lastAttemptedAt == runStart)
    // The deadline stays anchored to the wake: the wait spent part of the budget.
    #expect(
      await fixture.outbound.deadlines.last
        == ExecutionDeadline(expiresAt: wake.addingTimeInterval(25))
    )
  }

  @Test("A caller whose wake budget ran out while waiting does not start a run")
  func waitedOutRunWithoutBudgetIsAbandoned() async throws {
    let fixture = bidirectionalFixture()
    let wake = fixedDate.addingTimeInterval(720)
    let expiry = wake.addingTimeInterval(30)

    let observer = Task { await fixture.coordinator.sync(trigger: .healthKitObserver) }
    let sweep = try await widenedSweep(fixture)
    // The 25 s wake budget is gone before the observer run releases the coordinator.
    fixture.clock.set(expiry)

    await fixture.outbound.releaseFirstRun()
    _ = await observer.value

    #expect(await sweep.value == .throttled(nextEligibleAt: expiry))
    #expect(await fixture.outbound.requestedMetrics == [[.steps]])
    let snapshot = await fixture.statusStore.snapshot()
    #expect(snapshot.lastAttemptedAt == fixedDate)
    #expect(snapshot.pendingThrottledWakes == 1)
  }

  @Test("A caller cancelled while waiting does not start a run others could join")
  func cancellationWhileWaitingAbandonsTheRun() async throws {
    let query = try await populatedQuery()
    let sender = FakeHealthBridgeSender(delay: runDelay)
    let statusStore = InMemorySyncStatusStore()
    let coordinator = try await makeCoordinator(
      query: query,
      sender: sender,
      statusStore: statusStore
    )

    let starter = Task { await coordinator.sync(trigger: .manual, metrics: [.steps]) }
    try await Task.sleep(for: arrivalDelay)
    let waiter = Task {
      await coordinator.sync(trigger: .manual, metrics: [.steps, .bodyMass])
    }
    try await Task.sleep(for: arrivalDelay)

    waiter.cancel()
    let starterReport = await starter.value
    let waiterReport = await waiter.value

    #expect(starterReport.synchronizedMetrics == 1)
    #expect(waiterReport.synchronizedMetrics == 0)
    #expect(waiterReport.failures.allSatisfy { $0.category == .cancelled })
    #expect(await sender.calls.map(\.metricID) == [.steps])
    // The abandoned run was never registered, so it never attempted anything either.
    #expect(await statusStore.snapshot().recentEvents.count == 1)
  }

  @Test("A bidirectional caller cancelled while waiting does not start a run")
  func bidirectionalCancellationWhileWaitingAbandonsTheRun() async throws {
    let fixture = bidirectionalFixture()

    let observer = Task { await fixture.coordinator.sync(trigger: .healthKitObserver) }
    let sweep = try await widenedSweep(fixture)

    sweep.cancel()
    await fixture.outbound.releaseFirstRun()
    _ = await observer.value
    let sweepOutcome = await sweep.value

    guard case .performed(let sweepReport) = sweepOutcome else {
      Issue.record("Expected the cancelled sweep to report a cancelled run")
      return
    }
    #expect(sweepReport.setupFailureCategory == .cancelled)
    #expect(await fixture.outbound.requestedMetrics == [[.steps]])
    #expect(await fixture.statusStore.snapshot().recentEvents.count == 1)
  }

  private func bidirectionalFixture() -> BidirectionalFixture {
    let clock = MutableClock(fixedDate)
    let configurationStore = InMemoryConfigurationStore(
      configuration: configuration(selectedMetrics: [.steps])
    )
    let outbound = ScopeRecordingOutboundCoordinator()
    let statusStore = InMemorySyncStatusStore()
    let eligibilityObservation = ScopeSnapshotNotifyingStore(store: statusStore)
    return BidirectionalFixture(
      coordinator: BidirectionalSyncCoordinator(
        outbound: outbound,
        inbound: ScopeRecordingInboundCoordinator(),
        configurationStore: configurationStore,
        statusStore: eligibilityObservation,
        now: { clock.now }
      ),
      outbound: outbound,
      statusStore: statusStore,
      configurationStore: configurationStore,
      eligibilityObservation: eligibilityObservation,
      clock: clock
    )
  }

  /// Starts an `.appRefresh` sweep that the in-flight observer run does not cover, and returns
  /// once its wake date is captured and eligibility is checked while the observer is suspended.
  /// The fixture has no freshness store, so both runs are full
  /// sweeps; widening the selection is what leaves the first one narrower than the next caller.
  private func widenedSweep(
    _ fixture: BidirectionalFixture
  ) async throws -> Task<BidirectionalSyncOutcome, Never> {
    await fixture.outbound.waitUntilFirstRunSuspended()
    try await fixture.configurationStore.save(
      configuration(selectedMetrics: [.steps, .bodyMass])
    )
    // Past the Balanced allowance, so the sweep is not throttled by the observer's attempt.
    fixture.clock.set(fixedDate.addingTimeInterval(720))
    await fixture.eligibilityObservation.armSnapshotNotification()
    let sweep = Task { await fixture.coordinator.sync(trigger: .appRefresh) }
    await fixture.eligibilityObservation.waitForObservedSnapshot()
    return sweep
  }

  private func populatedQuery() async throws -> FakeMetricQueryService {
    let query = FakeMetricQueryService()
    await query.configureReading(
      MetricReading(metricID: .steps, timestamp: fixedDate, value: 8_421),
      for: .steps
    )
    await query.configureReading(
      MetricReading(metricID: .bodyMass, timestamp: fixedDate, value: 80),
      for: .bodyMass
    )
    await query.configureReading(
      MetricReading(metricID: .restingHeartRate, timestamp: fixedDate, value: 55),
      for: .restingHeartRate
    )
    return query
  }

  private func makeCoordinator(
    query: FakeMetricQueryService,
    sender: FakeHealthBridgeSender,
    statusStore: (any SyncStatusStore)? = nil,
    medicationCoordinator: (any MedicationSynchronizing)? = nil,
    medicationEnabled: Bool = false
  ) async throws -> SyncCoordinator {
    let credentialStore = InMemoryCredentialStore()
    try await credentialStore.write("fixture-webhook-secret", for: .webhookSecret)

    return SyncCoordinator(
      configurationStore: InMemoryConfigurationStore(
        configuration: configuration(
          selectedMetrics: [.steps, .bodyMass, .restingHeartRate],
          medicationEnabled: medicationEnabled
        )
      ),
      credentialStore: credentialStore,
      metricQuery: query,
      webhookSender: sender,
      calendar: Calendar(identifier: .gregorian),
      now: { fixedDate },
      statusStore: statusStore,
      medicationSyncCoordinator: medicationCoordinator
    )
  }

  private func configuration(
    selectedMetrics: Set<MetricID>,
    medicationEnabled: Bool = false
  ) -> AppConfiguration {
    AppConfiguration(
      baseURL: "https://ha.example.com",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "oleh",
      selectedMetrics: selectedMetrics,
      backgroundSyncEnabled: true,
      backgroundSyncFrequency: .balanced,
      medicationSyncEnabled: medicationEnabled
    )
  }

  private struct BidirectionalFixture {
    let coordinator: BidirectionalSyncCoordinator
    let outbound: ScopeRecordingOutboundCoordinator
    let statusStore: InMemorySyncStatusStore
    let configurationStore: InMemoryConfigurationStore
    let eligibilityObservation: ScopeSnapshotNotifyingStore
    let clock: MutableClock
  }
}

/// The joining rule itself, without the timing a coordinator needs to exercise it.
@Suite("Run coverage")
struct SyncRunCoverageTests {
  private let selection: Set<MetricID> = [.steps, .bodyMass]

  @Test("A run covers a request whose metrics it contains")
  func supersetCoversSubset() {
    #expect(coverage(selection).covers(coverage([.steps])))
    #expect(coverage(selection).covers(coverage(selection)))
    #expect(coverage(selection).covers(coverage([])))
  }

  @Test("A run does not cover a request that reaches past it")
  func subsetDoesNotCoverSuperset() {
    #expect(!coverage([.steps]).covers(coverage(selection)))
    #expect(!coverage([.steps]).covers(coverage([.bodyMass])))
  }

  @Test("An unresolved selection matches only another unresolved one")
  func unresolvedSelectionMatchesItsOwnKind() {
    #expect(coverage(nil).covers(coverage(nil)))
    #expect(!coverage(nil).covers(coverage(selection)))
    #expect(!coverage(selection).covers(coverage(nil)))
  }

  @Test("A run that leaves medications out does not cover a request that needs them")
  func medicationsMustBeCovered() {
    #expect(!coverage(selection, medications: false).covers(coverage([.steps])))
    #expect(!coverage(nil, medications: false).covers(coverage(nil)))
    #expect(coverage(selection, medications: false).covers(coverage([.steps], medications: false)))
    #expect(coverage(selection).covers(coverage([.steps], medications: false)))
  }

  private func coverage(
    _ metrics: Set<MetricID>?,
    medications: Bool = true
  ) -> SyncRunCoverage {
    SyncRunCoverage(metrics: metrics, includesMedications: medications)
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

private actor ScopeRecordingOutboundCoordinator: SyncCoordinating {
  private let suspendFirst: Bool
  init(suspendFirst: Bool = true) { self.suspendFirst = suspendFirst }
  private var firstRun: CheckedContinuation<Void, Never>?
  private var firstRunWaiter: CheckedContinuation<Void, Never>?
  private(set) var requestedMetrics: [Set<MetricID>] = []
  private(set) var deadlines: [ExecutionDeadline?] = []

  func waitUntilFirstRunSuspended() async {
    if firstRun != nil { return }
    await withCheckedContinuation { firstRunWaiter = $0 }
  }

  func releaseFirstRun() {
    firstRun?.resume()
    firstRun = nil
  }

  func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?
  ) async -> SyncReport {
    deadlines.append(deadline)
    return await sync(trigger: trigger, metrics: metrics)
  }

  func sync(trigger: SyncTrigger, metrics: Set<MetricID>?) async -> SyncReport {
    requestedMetrics.append(metrics ?? [])
    if requestedMetrics.count == 1 && suspendFirst {
      await withCheckedContinuation {
        firstRun = $0
        firstRunWaiter?.resume()
        firstRunWaiter = nil
      }
    }
    let date = Date(timeIntervalSince1970: 1_788_035_400)
    return SyncReport(
      trigger: trigger,
      attemptedMetrics: metrics?.count ?? 0,
      synchronizedMetrics: metrics?.count ?? 0,
      skippedMetrics: 0,
      failures: [],
      startedAt: date,
      finishedAt: date
    )
  }
}

/// Observe the automatic wake's eligibility read after its request date has been
/// captured. Forward all persistence to the real in-memory store used by assertions.
private actor ScopeSnapshotNotifyingStore: SyncStatusStore {
  let store: InMemorySyncStatusStore
  private var armed = false
  private var observed = false
  private var waiter: CheckedContinuation<Void, Never>?

  init(store: InMemorySyncStatusStore) { self.store = store }

  func armSnapshotNotification() {
    armed = true
    observed = false
  }

  func waitForObservedSnapshot() async {
    if observed { return }
    await withCheckedContinuation { waiter = $0 }
  }

  func snapshot() async -> SyncStatusSnapshot {
    let snapshot = await store.snapshot()
    if armed {
      armed = false
      observed = true
      waiter?.resume()
      waiter = nil
    }
    return snapshot
  }

  func recordAttempt(trigger: SyncTrigger, at: Date) async throws {
    try await store.recordAttempt(trigger: trigger, at: at)
  }
  func record(report: SyncReport) async throws { try await store.record(report: report) }
  func record(report: BidirectionalSyncReport) async throws {
    try await store.record(report: report)
  }
  func recordInterruptedAttemptIfNeeded() async throws -> SyncStatusEvent? {
    try await store.recordInterruptedAttemptIfNeeded()
  }
  func recordThrottledWake() async throws { try await store.recordThrottledWake() }
  func setRegistration(_ state: BackgroundRegistrationState, for metric: MetricID) async throws {
    try await store.setRegistration(state, for: metric)
  }
  func reset() async throws { try await store.reset() }
}

private actor ScopeRecordingInboundCoordinator: InboundSyncCoordinating {
  private(set) var triggers: [SyncTrigger] = []
  func sync(trigger: SyncTrigger) async -> InboundSyncReport {
    triggers.append(trigger)
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

private actor JoiningPaidAccess: PaidFeatureAccessing {
  private var state: PaidAccessState = .unlocked
  func accessState() -> PaidAccessState { state }
  func revoke() { state = .locked }
}

private actor SuspendedPaidAccess: PaidFeatureAccessing {
  private var check: CheckedContinuation<PaidAccessState, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  private(set) var wasReleased = false
  func accessState() async -> PaidAccessState {
    if wasReleased { return .locked }
    return await withCheckedContinuation {
      check = $0
      observer?.resume()
      observer = nil
    }
  }
  func waitForCheck() async {
    if check != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func deny() {
    wasReleased = true
    check?.resume(returning: .locked)
    check = nil
  }
}

private actor JoiningConfigurationStore: ConfigurationStore {
  private var configuration: AppConfiguration
  private var observed = false
  private var waiter: CheckedContinuation<Void, Never>?
  init(_ configuration: AppConfiguration) { self.configuration = configuration }
  func load() -> AppConfiguration {
    if configuration.selectedMetrics.count > 1 {
      observed = true
      waiter?.resume()
      waiter = nil
    }
    return configuration
  }
  func save(_ configuration: AppConfiguration) { self.configuration = configuration }
  func delete() { configuration = .default }
  func waitForBroadRead() async {
    if observed { return }
    await withCheckedContinuation { waiter = $0 }
  }
}
