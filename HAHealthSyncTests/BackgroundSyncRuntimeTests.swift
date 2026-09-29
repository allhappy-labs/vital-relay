import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

private actor BackgroundPaidAccess: PaidFeatureAccessing {
  var state: PaidAccessState
  init(_ state: PaidAccessState) { self.state = state }
  func accessState() -> PaidAccessState { state }
  func revoke() { state = .locked }
}

@MainActor
final class BackgroundSyncRuntimeTests: XCTestCase {
  func testLockedEntitlementKeepsPreferenceButDisablesScheduling() async throws {
    let access = BackgroundPaidAccess(.locked)
    let fixture = try await makeFixture(access: access)
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    XCTAssertFalse(fixture.runtime.isEligible)
    XCTAssertEqual(fixture.refresh.calls.last?.enabled, false)
    let configuration = try await fixture.configurationStore.load()
    XCTAssertTrue(configuration.backgroundSyncEnabled)
  }

  func testRefundBlocksQueuedRefreshAndObserverButManualSyncRemainsFree() async throws {
    let access = BackgroundPaidAccess(.unlocked)
    let fixture = try await makeFixture(access: access)
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    await access.revoke()
    let refresh = await fixture.runtime.performRefreshSync()
    let observer = await fixture.runtime.coordinator.sync(trigger: .healthKitObserver)
    if case .requiresPurchase = refresh {} else { XCTFail("Queued refresh ran after revocation") }
    if case .requiresPurchase = observer {} else { XCTFail("Observer ran after revocation") }
    await fixture.runtime.reconcile()
    XCTAssertFalse(fixture.runtime.isEligible)
    XCTAssertEqual(fixture.refresh.calls.last?.enabled, false)
    let manual = await fixture.runtime.coordinator.sync(trigger: .manual)
    if case .performed = manual {} else { XCTFail("Manual sync should remain free") }
  }
  private let now = Date(timeIntervalSince1970: 1_788_035_400)

  func testBootstrapReconcilesObserversAndSubmitsRefreshFromPersistedAttempt() async throws {
    let fixture = try await makeFixture(
      status: SyncStatusSnapshot(lastAttemptedAt: now.addingTimeInterval(-600))
    )

    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()

    XCTAssertTrue(fixture.runtime.isEligible)
    let observerCalls = await fixture.observers.reconciliations
    XCTAssertEqual(observerCalls.map(\.enabled), [true])
    XCTAssertEqual(observerCalls.first?.metrics, [.steps, .bodyMass])
    XCTAssertEqual(fixture.refresh.calls.last?.enabled, true)
    XCTAssertEqual(fixture.refresh.calls.last?.date, now.addingTimeInterval(2_400))
    XCTAssertEqual(fixture.refresh.calls.last?.retryInterval, 900)
    XCTAssertEqual(fixture.refresh.registerCount, 1)
    XCTAssertTrue(fixture.refresh.launchDelegate === fixture.runtime)
  }

  func testBootstrapDisablesBackgroundWorkWithoutCredentials() async throws {
    let fixture = try await makeFixture(credentials: false)

    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()

    XCTAssertFalse(fixture.runtime.isEligible)
    let observerCalls = await fixture.observers.reconciliations
    XCTAssertEqual(observerCalls.map(\.enabled), [false])
    XCTAssertEqual(fixture.refresh.calls.map(\.enabled), [false])
  }

  func testBootstrapRecordsAndPublishesAnInterruptedAttempt() async throws {
    let fixture = try await makeFixture(
      status: SyncStatusSnapshot(
        lastAttemptedAt: now,
        inFlightAttempt: SyncInFlightAttempt(trigger: .appRefresh, startedAt: now, launchID: UUID())
      )
    )

    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()

    let events = await fixture.statusStore.snapshot().recentEvents
    XCTAssertEqual(events.map(\.outcome), [.interrupted])
    let published = await waitUntil { await !fixture.publisher.events.isEmpty }
    XCTAssertTrue(published)
    let publishedEvents = await fixture.publisher.events
    XCTAssertEqual(publishedEvents.map(\.outcome), [.interrupted])
  }

  func testInterruptedAttemptPublishDoesNotBlockBootstrap() async throws {
    let fixture = try await makeFixture(
      status: SyncStatusSnapshot(
        lastAttemptedAt: now,
        inFlightAttempt: SyncInFlightAttempt(trigger: .appRefresh, startedAt: now, launchID: UUID())
      ),
      publishDelay: .seconds(1)
    )
    let clock = ContinuousClock()
    let started = clock.now

    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()

    XCTAssertLessThan(clock.now - started, .milliseconds(500))
    XCTAssertTrue(fixture.runtime.isEligible)
    XCTAssertEqual(fixture.refresh.calls.last?.enabled, true)
    let published = await waitUntil(timeout: .seconds(3)) {
      await !fixture.publisher.events.isEmpty
    }
    XCTAssertTrue(published)
  }

  func testStoreReadErrorKeepsExistingBackgroundWork() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    let refreshCalls = fixture.refresh.calls.count
    await fixture.configurationStore.setFailing(true)

    await fixture.runtime.reconcile()

    XCTAssertTrue(fixture.runtime.isEligible)
    let observerCalls = await fixture.observers.reconciliations
    XCTAssertEqual(observerCalls.map(\.enabled), [true])
    let stopCount = await fixture.observers.stopCount
    XCTAssertEqual(stopCount, 0)
    XCTAssertEqual(fixture.refresh.calls.count, refreshCalls)
    XCTAssertFalse(fixture.refresh.calls.contains { !$0.enabled })
    let eligible = await fixture.runtime.isBackgroundWorkEligible()
    XCTAssertFalse(eligible)
  }

  func testEveryOutcomeResubmitsRefreshWithPolicyDate() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()

    await fixture.base.setOutcome(.performed(report(trigger: .manual, failure: nil)))
    _ = await fixture.runtime.coordinator.sync(trigger: .manual)
    XCTAssertEqual(fixture.refresh.calls.last?.date, now.addingTimeInterval(3_000))

    await fixture.base.setOutcome(
      .performed(
        report(
          trigger: .healthKitObserver,
          failure: .deviceLocked,
          startedAt: now.addingTimeInterval(1)
        )))
    _ = await fixture.runtime.coordinator.sync(trigger: .healthKitObserver)
    XCTAssertEqual(fixture.refresh.calls.last?.date, now.addingTimeInterval(900))

    await fixture.base.setOutcome(.throttled(nextEligibleAt: now.addingTimeInterval(1_234)))
    _ = await fixture.runtime.coordinator.sync(trigger: .healthKitObserver)
    XCTAssertEqual(fixture.refresh.calls.last?.date, now.addingTimeInterval(1_234))
  }

  func testDecoratedCoordinatorForwardsTheObserversChangedTypes() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    await fixture.base.setOutcome(
      .performed(report(trigger: .healthKitObserver, failure: nil)))
    let refreshCalls = fixture.refresh.calls.count

    _ = await fixture.runtime.coordinator.sync(
      trigger: .healthKitObserver, changedTypes: [.stepCount, .bodyMass])

    let changedTypeSets = await fixture.base.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount, .bodyMass]])
    // The decorator must still reschedule, so forwarding cannot have bypassed it.
    XCTAssertEqual(fixture.refresh.calls.count, refreshCalls + 1)
  }

  func testIneligibleRuntimeDoesNotResubmitAfterRuns() async throws {
    let fixture = try await makeFixture(backgroundEnabled: false)
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    let callCount = fixture.refresh.calls.count

    _ = await fixture.runtime.coordinator.sync(trigger: .manual)

    XCTAssertEqual(fixture.refresh.calls.count, callCount)
  }

  func testCancelledRunResubmitsRefreshAtRetryIntervalWhileEligible() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    let callCount = fixture.refresh.calls.count
    await fixture.base.setOutcome(.performed(cancelledReport()))

    _ = await fixture.runtime.coordinator.sync(trigger: .appRefresh)

    XCTAssertEqual(fixture.refresh.calls.count, callCount + 1)
    XCTAssertEqual(fixture.refresh.calls.last?.enabled, true)
    XCTAssertEqual(fixture.refresh.calls.last?.date, now.addingTimeInterval(900))
  }

  func testCancelledRunAfterSuspendDoesNotResubmitRefresh() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    await fixture.runtime.suspend()
    let callCount = fixture.refresh.calls.count
    await fixture.base.setOutcome(.performed(cancelledReport()))

    _ = await fixture.runtime.coordinator.sync(trigger: .appRefresh)

    XCTAssertEqual(fixture.refresh.calls.count, callCount)
    XCTAssertEqual(fixture.refresh.calls.last?.enabled, false)
  }

  func testPerformedRunsArePublished() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    await fixture.base.setOutcome(.performed(report(trigger: .appRefresh, failure: nil)))

    _ = await fixture.runtime.coordinator.sync(trigger: .appRefresh)

    let published = await fixture.publisher.events
    XCTAssertEqual(published.map(\.trigger), [.appRefresh])
  }

  func testDuplicateOutcomesForOneRunAreHandledOnce() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()
    let outcome = BidirectionalSyncOutcome.performed(report(trigger: .appRefresh, failure: nil))
    let refreshCalls = fixture.refresh.calls.count

    await fixture.runtime.handleOutcome(trigger: .appRefresh, outcome: outcome)
    await fixture.runtime.handleOutcome(trigger: .healthKitObserver, outcome: outcome)

    let published = await fixture.publisher.events
    XCTAssertEqual(published.count, 1)
    XCTAssertEqual(fixture.refresh.calls.count, refreshCalls + 1)

    let throttled = BidirectionalSyncOutcome.throttled(nextEligibleAt: now.addingTimeInterval(60))
    await fixture.runtime.handleOutcome(trigger: .healthKitObserver, outcome: throttled)
    XCTAssertEqual(fixture.refresh.calls.count, refreshCalls + 2)
  }

  func testSuspendStopsObserversAndCancelsRefresh() async throws {
    let fixture = try await makeFixture()
    fixture.runtime.start()
    await fixture.runtime.waitUntilReady()

    await fixture.runtime.suspend()

    XCTAssertFalse(fixture.runtime.isEligible)
    let stopCount = await fixture.observers.stopCount
    XCTAssertEqual(stopCount, 1)
    XCTAssertEqual(fixture.refresh.calls.last?.enabled, false)
  }

  func testRefreshLaunchWaitsForBootstrapThenRunsThroughTheDecorator() async throws {
    let scheduler = FakeAppRefreshScheduler()
    let fixedNow = now
    let refreshManager = AppRefreshManager(scheduler: scheduler, now: { fixedNow })
    let fixture = try await makeFixture(
      refreshManager: refreshManager,
      configurationDelay: .milliseconds(100)
    )
    await fixture.base.setOutcome(.performed(report(trigger: .appRefresh, failure: nil)))
    let task = FakeAppRefreshTask()

    fixture.runtime.start()
    scheduler.launch(task)
    let completed = await waitUntil { !task.completions.isEmpty }

    XCTAssertTrue(completed)
    XCTAssertEqual(task.completions, [true])
    let triggers = await fixture.base.triggers
    XCTAssertEqual(triggers, [.appRefresh])
    XCTAssertEqual(scheduler.submissions.last?.date, now.addingTimeInterval(3_000))
  }

  // MARK: - Fixture

  private struct Fixture {
    let runtime: BackgroundSyncRuntime
    let base: ScriptedCoordinator
    let observers: RecordingObserverManager
    let refresh: RecordingRefreshController
    let statusStore: InMemorySyncStatusStore
    let publisher: RecordingAttemptPublisher
    let configurationStore: DelayedConfigurationStore
  }

  func testScopeDecisionsAreLoggedAsTriggerReasonAndCounts() {
    let scoped = BidirectionalSyncReport(
      trigger: .healthKitObserver,
      outbound: SyncReport(
        trigger: .healthKitObserver,
        attemptedMetrics: 3,
        synchronizedMetrics: 3,
        skippedMetrics: 0,
        failures: [],
        startedAt: now,
        finishedAt: now,
        collectedMetrics: 3
      ),
      inbound: nil,
      startedAt: now,
      finishedAt: now,
      scopeReason: .changedTypes,
      requestedMetrics: 3,
      changedTypes: 1
    )
    let sweep = BidirectionalSyncReport(
      trigger: .appRefresh,
      outbound: SyncReport(
        trigger: .appRefresh,
        attemptedMetrics: 88,
        synchronizedMetrics: 40,
        skippedMetrics: 0,
        failures: [],
        startedAt: now,
        finishedAt: now,
        collectedMetrics: 40,
        deferredMetrics: 48
      ),
      inbound: nil,
      startedAt: now,
      finishedAt: now,
      scopeReason: .sweepDue,
      requestedMetrics: 88,
      starvedMetrics: 2
    )

    XCTAssertEqual(
      BackgroundLog.scopeMessage(for: scoped),
      "Scope healthKitObserver reason=changedTypes requested=3 collected=3 changed=1"
    )
    XCTAssertEqual(
      BackgroundLog.scopeMessage(for: sweep),
      "Scope appRefresh reason=sweepDue requested=88 collected=40 deferred=48 starved=2"
    )
    // A run no scope was resolved for has nothing to say about scope.
    XCTAssertNil(BackgroundLog.scopeMessage(for: report(trigger: .manual, failure: nil)))
  }

  private func makeFixture(
    backgroundEnabled: Bool = true,
    credentials: Bool = true,
    status: SyncStatusSnapshot = SyncStatusSnapshot(),
    refreshManager: (any AppRefreshControlling)? = nil,
    configurationDelay: Duration = .zero,
    publishDelay: Duration = .zero,
    access: any PaidFeatureAccessing = BackgroundPaidAccess(.unlocked)
  ) async throws -> Fixture {
    let configuration = AppConfiguration(
      baseURL: "https://ha.example.com",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .bodyMass],
      backgroundSyncEnabled: backgroundEnabled,
      backgroundSyncFrequency: .batterySaver
    )
    let credentialStore = InMemoryCredentialStore()
    if credentials {
      try await credentialStore.write("fixture-secret", for: .webhookSecret)
      try await credentialStore.write("fixture-token", for: .accessToken)
    }
    let statusStore = InMemorySyncStatusStore(snapshot: status)
    let base = ScriptedCoordinator(outcome: .performed(report(trigger: .manual, failure: nil)))
    let observers = RecordingObserverManager()
    let recordingRefresh = RecordingRefreshController()
    let publisher = RecordingAttemptPublisher(delay: publishDelay)
    let fixedNow = now
    let configurationStore = DelayedConfigurationStore(
      configuration: configuration, delay: configurationDelay)
    let runtime = BackgroundSyncRuntime(
      access: access,
      baseCoordinator: base,
      makeObserverManager: { _ in observers },
      refreshManager: refreshManager ?? recordingRefresh,
      configurationStore: configurationStore,
      credentialStore: credentialStore,
      statusStore: statusStore,
      publisher: publisher,
      now: { fixedNow }
    )
    return Fixture(
      runtime: runtime,
      base: base,
      observers: observers,
      refresh: recordingRefresh,
      statusStore: statusStore,
      publisher: publisher,
      configurationStore: configurationStore
    )
  }

  private func cancelledReport() -> BidirectionalSyncReport {
    BidirectionalSyncReport(
      trigger: .appRefresh,
      outbound: nil,
      inbound: nil,
      setupFailureCategory: .cancelled,
      startedAt: now,
      finishedAt: now
    )
  }

  private func report(
    trigger: SyncTrigger,
    failure: SyncFailureCategory?,
    startedAt: Date? = nil
  ) -> BidirectionalSyncReport {
    let startedAt = startedAt ?? now
    return BidirectionalSyncReport(
      trigger: trigger,
      outbound: SyncReport(
        trigger: trigger,
        attemptedMetrics: 1,
        synchronizedMetrics: failure == nil ? 1 : 0,
        skippedMetrics: 0,
        failures: failure.map { [.init(metricID: nil, category: $0)] } ?? [],
        startedAt: startedAt,
        finishedAt: startedAt
      ),
      inbound: nil,
      startedAt: startedAt,
      finishedAt: startedAt
    )
  }
}

private actor ScriptedCoordinator: BidirectionalSyncCoordinating {
  private var outcome: BidirectionalSyncOutcome
  private(set) var triggers: [SyncTrigger] = []
  private(set) var changedTypeSets: [Set<HealthObjectTypeID>] = []

  init(outcome: BidirectionalSyncOutcome) {
    self.outcome = outcome
  }

  func setOutcome(_ outcome: BidirectionalSyncOutcome) {
    self.outcome = outcome
  }

  func sync(trigger: SyncTrigger) -> BidirectionalSyncOutcome {
    triggers.append(trigger)
    return outcome
  }

  func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>
  ) -> BidirectionalSyncOutcome {
    changedTypeSets.append(changedTypes)
    return sync(trigger: trigger)
  }
}

private actor RecordingObserverManager: BackgroundSyncManaging {
  private(set) var reconciliations: [(enabled: Bool, metrics: Set<MetricID>)] = []
  private(set) var stopCount = 0

  func reconcile(enabled: Bool, metrics: Set<MetricID>) {
    reconciliations.append((enabled, metrics))
  }

  func stopAll() {
    stopCount += 1
  }

  func registrationStates() -> [MetricID: BackgroundRegistrationState] { [:] }
}

@MainActor
private final class RecordingRefreshController: AppRefreshControlling {
  struct Call {
    let enabled: Bool
    let date: Date?
    let retryInterval: TimeInterval
  }

  weak var launchDelegate: (any AppRefreshLaunchDelegate)?
  private(set) var calls: [Call] = []
  private(set) var registerCount = 0

  func register() -> Bool {
    registerCount += 1
    return true
  }

  func reconcile(enabled: Bool, earliestBeginDate: Date?, retryInterval: TimeInterval) {
    calls.append(Call(enabled: enabled, date: earliestBeginDate, retryInterval: retryInterval))
  }
}

private actor RecordingAttemptPublisher: SyncAttemptPublishing {
  private let delay: Duration
  private(set) var events: [SyncStatusEvent] = []

  init(delay: Duration = .zero) {
    self.delay = delay
  }

  func publish(_ event: SyncStatusEvent, deadline: ExecutionDeadline?) async -> SyncFailureCategory?
  {
    if delay > .zero { try? await Task.sleep(for: delay) }
    events.append(event)
    return nil
  }

  func publishTest() {}
}

private actor DelayedConfigurationStore: ConfigurationStore {
  private var configuration: AppConfiguration
  private let delay: Duration
  private var isFailing = false

  init(configuration: AppConfiguration, delay: Duration) {
    self.configuration = configuration
    self.delay = delay
  }

  func load() async throws -> AppConfiguration {
    if delay > .zero { try await Task.sleep(for: delay) }
    if isFailing { throw ConfigurationStoreError.corruptedData }
    return configuration
  }

  func setFailing(_ failing: Bool) {
    isFailing = failing
  }

  func save(_ configuration: AppConfiguration) {
    self.configuration = configuration
  }

  func delete() {
    configuration = .default
  }
}
