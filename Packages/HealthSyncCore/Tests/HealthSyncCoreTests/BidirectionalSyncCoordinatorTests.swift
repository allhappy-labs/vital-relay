import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Bidirectional sync coordinator")
struct BidirectionalSyncCoordinatorTests {
  private let start = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Automatic triggers run at every preset allowance boundary")
  func backgroundBoundaries() async {
    let cases: [(BackgroundSyncFrequency, TimeInterval)] = [
      (.responsive, 240),
      (.balanced, 720),
      (.batterySaver, 3_000),
      (.daily, 85_800),
    ]

    for (frequency, eligibleAfter) in cases {
      for trigger in [SyncTrigger.background, .healthKitObserver, .appRefresh] {
        let fixture = fixture(frequency: frequency, lastAttemptedAt: start)
        fixture.clock.set(start.addingTimeInterval(eligibleAfter - 1))

        #expect(
          await fixture.coordinator.sync(trigger: trigger)
            == .throttled(nextEligibleAt: start.addingTimeInterval(eligibleAfter))
        )

        fixture.clock.set(start.addingTimeInterval(eligibleAfter))
        guard case .performed = await fixture.coordinator.sync(trigger: trigger) else {
          Issue.record("Expected a performed run at the allowance boundary")
          continue
        }
        #expect(await fixture.outbound.callCount == 1)
        #expect(await fixture.inbound.callCount == 1)
      }
    }
  }

  @Test("Manual and Shortcut bypass cadence and reset background eligibility")
  func immediateTriggersResetCadence() async {
    let fixture = fixture(frequency: .balanced, lastAttemptedAt: start)
    fixture.clock.set(start.addingTimeInterval(10))

    guard case .performed = await fixture.coordinator.sync(trigger: .manual) else {
      Issue.record("Expected Manual to run immediately")
      return
    }
    #expect(
      await fixture.coordinator.sync(trigger: .background)
        == .throttled(nextEligibleAt: start.addingTimeInterval(730))
    )

    fixture.clock.set(start.addingTimeInterval(20))
    guard case .performed = await fixture.coordinator.sync(trigger: .shortcut) else {
      Issue.record("Expected Shortcut to run immediately")
      return
    }
    #expect(
      await fixture.coordinator.sync(trigger: .background)
        == .throttled(nextEligibleAt: start.addingTimeInterval(740))
    )
    #expect(await fixture.outbound.triggers == [.manual, .shortcut])
    #expect(await fixture.inbound.triggers == [.manual, .shortcut])
    #expect(
      await fixture.outbound.requestedMetrics
        == [
          [.steps, .bodyMass],
          [.steps, .bodyMass],
        ]
    )
  }

  @Test("A run without freshness data sweeps everything, medications included")
  func outboundRunCoversMedications() async {
    let fixture = fixture()

    guard case .performed = await fixture.coordinator.sync(trigger: .healthKitObserver) else {
      Issue.record("Expected a performed run")
      return
    }

    // With no freshness store the scope policy sees no previous full sweep, so the observer
    // wake resolves to a full sweep: every selected metric, medications included, and no window
    // touches to pass on.
    #expect(await fixture.outbound.medicationFlags == [true])
    #expect(await fixture.outbound.windowTouches == [[:]])
  }

  @Test("Concurrent triggers share one two-direction run")
  func concurrentTriggersCoalesce() async {
    let fixture = fixture(delay: .milliseconds(50))

    async let first = fixture.coordinator.sync(trigger: .manual)
    async let second = fixture.coordinator.sync(trigger: .manual)
    _ = await (first, second)

    #expect(await fixture.outbound.callCount == 1)
    #expect(await fixture.inbound.callCount == 1)
  }

  @Test("A one-direction failure preserves the other report")
  func partialFailure() async {
    let pairingID = UUID(uuidString: "7581B12B-14FE-43C2-971C-07EA1721E6D5")!
    let inbound = RecordingInboundCoordinator(
      failures: [.init(pairingID: pairingID, category: .validation)]
    )
    let fixture = fixture(inbound: inbound)

    guard case .performed(let report) = await fixture.coordinator.sync(trigger: .manual) else {
      Issue.record("Expected a performed run")
      return
    }

    #expect(report.outbound?.synchronizedMetrics == 2)
    #expect(report.inbound?.failures.first?.category == .validation)
    #expect(report.firstFailureCategory == .validation)
    #expect(report.succeeded == false)
    let snapshot = await fixture.statusStore.snapshot()
    #expect(snapshot.lastSuccessfulAt == nil)
    #expect(snapshot.lastFailure?.metricID == nil)
  }

  @Test("Configuration failure uses Balanced cadence and stays value-free")
  func configurationFailure() async {
    let clock = TestClock(start.addingTimeInterval(719))
    let statusStore = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(lastAttemptedAt: start)
    )
    let outbound = RecordingOutboundCoordinator()
    let inbound = RecordingInboundCoordinator()
    let coordinator = BidirectionalSyncCoordinator(
      outbound: outbound,
      inbound: inbound,
      configurationStore: FailingConfigurationStore(),
      statusStore: statusStore,
      now: { clock.now }
    )

    #expect(
      await coordinator.sync(trigger: .background)
        == .throttled(nextEligibleAt: start.addingTimeInterval(720))
    )

    clock.set(start.addingTimeInterval(720))
    guard case .performed(let report) = await coordinator.sync(trigger: .background) else {
      Issue.record("Expected a value-free setup failure at the boundary")
      return
    }
    #expect(report.setupFailureCategory == .configuration)
    #expect(report.outbound == nil)
    #expect(report.inbound == nil)
    #expect(await outbound.callCount == 0)
    #expect(await inbound.callCount == 0)
  }

  @Test("Persisted attempts preserve cadence after reconstruction")
  func reconstructionPreservesCadence() async {
    let clock = TestClock(start)
    let configurationStore = configuredStore(frequency: .responsive)
    let statusStore = InMemorySyncStatusStore()
    let first = BidirectionalSyncCoordinator(
      outbound: RecordingOutboundCoordinator(),
      inbound: RecordingInboundCoordinator(),
      configurationStore: configurationStore,
      statusStore: statusStore,
      now: { clock.now }
    )
    _ = await first.sync(trigger: .manual)

    let reconstructed = BidirectionalSyncCoordinator(
      outbound: RecordingOutboundCoordinator(),
      inbound: RecordingInboundCoordinator(),
      configurationStore: configurationStore,
      statusStore: statusStore,
      now: { clock.now }
    )

    #expect(
      await reconstructed.sync(trigger: .background)
        == .throttled(nextEligibleAt: start.addingTimeInterval(240))
    )
  }

  @Test("A locked-device defer never throttles the next unlocked opportunity")
  func lockedDeviceDeferRetriesImmediately() async {
    let retryDate = start.addingTimeInterval(10)
    let clock = TestClock(retryDate)
    let statusStore = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(
        lastAttemptedAt: start,
        lastFailure: SyncStatusFailure(
          metricID: nil,
          category: .deviceLocked,
          at: start
        )
      )
    )
    let outbound = RecordingOutboundCoordinator()
    let inbound = RecordingInboundCoordinator()
    let coordinator = BidirectionalSyncCoordinator(
      outbound: outbound,
      inbound: inbound,
      configurationStore: configuredStore(frequency: .balanced),
      statusStore: statusStore,
      now: { clock.now }
    )

    guard case .performed = await coordinator.sync(trigger: .background) else {
      Issue.record("Expected the first unlocked opportunity to run immediately")
      return
    }

    #expect(await outbound.callCount == 1)
    #expect(await inbound.callCount == 1)
    #expect(await statusStore.snapshot().lastFailure == nil)
  }

  @Test("Cancellation stops both directions and reports cancellation")
  func cancellation() async throws {
    let fixture = fixture(delay: .seconds(5))
    let task = Task { await fixture.coordinator.sync(trigger: .manual) }
    // Exercise cancellation of running children, not cancellation before they are scheduled.
    let readinessDeadline = ContinuousClock.now.advanced(by: .seconds(1))
    while ContinuousClock.now < readinessDeadline {
      if await fixture.outbound.callCount == 1, await fixture.inbound.callCount == 1 { break }
      await Task.yield()
    }
    let outboundStarted = await fixture.outbound.callCount
    let inboundStarted = await fixture.inbound.callCount
    try #require(outboundStarted == 1 && inboundStarted == 1)

    task.cancel()
    let outcome = await task.value

    guard case .performed(let report) = outcome else {
      Issue.record("Expected a performed cancellation report")
      return
    }
    #expect(report.setupFailureCategory == .cancelled)
    let outboundCalls = await fixture.outbound.callCount
    let inboundCalls = await fixture.inbound.callCount
    let outboundCancellations = await fixture.outbound.cancellationCount
    let inboundCancellations = await fixture.inbound.cancellationCount
    #expect(outboundCancellations == 1, "outbound calls: \(outboundCalls)")
    #expect(inboundCancellations == 1, "inbound calls: \(inboundCalls)")
  }

  @Test("Cancelling a caller that joined a shared run leaves the run intact")
  func joinerCancellationDoesNotCancelSharedRun() async throws {
    let fixture = fixture(delay: .milliseconds(300))
    let starter = Task { await fixture.coordinator.sync(trigger: .appRefresh) }
    try await Task.sleep(for: .milliseconds(30))
    let joiner = Task { await fixture.coordinator.sync(trigger: .healthKitObserver) }
    try await Task.sleep(for: .milliseconds(30))

    joiner.cancel()
    let outcome = await starter.value
    _ = await joiner.value

    guard case .performed(let report) = outcome else {
      Issue.record("Expected the starter to receive a performed run")
      return
    }
    #expect(!report.failureCategories.contains(.cancelled))
    #expect(await fixture.outbound.callCount == 1)
    #expect(await fixture.outbound.cancellationCount == 0)
    #expect(await fixture.inbound.cancellationCount == 0)
  }

  @Test("Budgeted triggers pass one deadline to both directions")
  func deadlines() async {
    let fixture = fixture()

    _ = await fixture.coordinator.sync(trigger: .appRefresh)
    _ = await fixture.coordinator.sync(trigger: .manual)

    let expected = ExecutionDeadline(expiresAt: start.addingTimeInterval(25))
    #expect(await fixture.outbound.deadlines == [expected, nil])
    #expect(await fixture.inbound.deadlines == [expected, nil])
  }

  @Test("Every budgeted trigger derives its deadline from its own allowance")
  func perTriggerDeadlines() async {
    let cases: [(SyncTrigger, TimeInterval)] = [
      (.appRefresh, 25),
      (.shortcut, 25),
      (.healthKitObserver, 18),
    ]

    for (trigger, budget) in cases {
      let fixture = fixture()
      _ = await fixture.coordinator.sync(trigger: trigger)

      let expected = ExecutionDeadline(expiresAt: start.addingTimeInterval(budget))
      #expect(await fixture.outbound.deadlines == [expected])
      #expect(await fixture.inbound.deadlines == [expected])
    }
  }

  @Test("Throttled wakes are counted into the next event")
  func throttledWakeCounting() async {
    let fixture = fixture(frequency: .batterySaver, lastAttemptedAt: start)
    fixture.clock.set(start.addingTimeInterval(60))

    #expect(
      await fixture.coordinator.sync(trigger: .healthKitObserver)
        == .throttled(nextEligibleAt: start.addingTimeInterval(3_000))
    )
    #expect(await fixture.statusStore.snapshot().pendingThrottledWakes == 1)

    _ = await fixture.coordinator.sync(trigger: .manual)
    #expect(await fixture.statusStore.snapshot().recentEvents.last?.throttledWakesBefore == 1)
  }

  @Test("An attempt left by a previous launch is recorded before the next run")
  func interruptedAttempt() async {
    let clock = TestClock(start)
    let statusStore = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(
        inFlightAttempt: SyncInFlightAttempt(
          trigger: .appRefresh,
          startedAt: start.addingTimeInterval(-600),
          launchID: UUID()
        )
      )
    )
    let coordinator = BidirectionalSyncCoordinator(
      outbound: RecordingOutboundCoordinator(),
      inbound: RecordingInboundCoordinator(),
      configurationStore: configuredStore(frequency: .balanced),
      statusStore: statusStore,
      now: { clock.now }
    )

    _ = await coordinator.sync(trigger: .manual)

    let events = await statusStore.snapshot().recentEvents
    #expect(events.map(\.outcome) == [.interrupted, .completed])
    #expect(events.first?.trigger == .appRefresh)
  }

  @Test("An interrupted attempt from a previous launch retries soon instead of full throttling")
  func interruptedAttemptRetriesSoon() async {
    let clock = TestClock(start.addingTimeInterval(13 * 60))
    let statusStore = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(
        lastAttemptedAt: start,
        inFlightAttempt: SyncInFlightAttempt(
          trigger: .healthKitObserver,
          startedAt: start,
          launchID: UUID()
        )
      )
    )
    let outbound = RecordingOutboundCoordinator()
    let inbound = RecordingInboundCoordinator()
    let coordinator = BidirectionalSyncCoordinator(
      outbound: outbound,
      inbound: inbound,
      configurationStore: configuredStore(frequency: .batterySaver),
      statusStore: statusStore,
      now: { clock.now }
    )

    guard case .performed = await coordinator.sync(trigger: .healthKitObserver) else {
      Issue.record("Expected the interrupted-then-retried wake to run, not throttle")
      return
    }
    #expect(await outbound.callCount == 1)
    #expect(await inbound.callCount == 1)
  }

  @Test("Concurrent syncs still record an interrupted attempt from a previous launch")
  func concurrentSyncsPreserveInterruptedAttempt() async {
    let clock = TestClock(start)
    let innerStore = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(
        inFlightAttempt: SyncInFlightAttempt(
          trigger: .appRefresh,
          startedAt: start.addingTimeInterval(-600),
          launchID: UUID()
        )
      )
    )
    let statusStore = SlowInterruptedCheckStatusStore(wrapping: innerStore)
    let coordinator = BidirectionalSyncCoordinator(
      outbound: RecordingOutboundCoordinator(),
      inbound: RecordingInboundCoordinator(),
      configurationStore: configuredStore(frequency: .balanced),
      statusStore: statusStore,
      now: { clock.now }
    )

    async let first = coordinator.sync(trigger: .manual)
    async let second = coordinator.sync(trigger: .manual)
    _ = await (first, second)

    let events = await innerStore.snapshot().recentEvents
    #expect(events.map(\.outcome) == [.interrupted, .completed])
    #expect(events.first?.trigger == .appRefresh)
  }

  @Test("Run context is captured into the report")
  func context() async {
    let context = SyncRunContext(
      backgroundRefresh: .denied,
      lowPowerMode: true,
      protectedDataAvailable: false
    )
    let clock = TestClock(start)
    let coordinator = BidirectionalSyncCoordinator(
      outbound: RecordingOutboundCoordinator(),
      inbound: RecordingInboundCoordinator(),
      configurationStore: configuredStore(frequency: .balanced),
      statusStore: InMemorySyncStatusStore(),
      contextProvider: FixedContextProvider(context: context),
      now: { clock.now }
    )

    guard case .performed(let report) = await coordinator.sync(trigger: .manual) else {
      Issue.record("Expected a performed run")
      return
    }
    #expect(report.context == context)
  }

  private func fixture(
    frequency: BackgroundSyncFrequency = .balanced,
    lastAttemptedAt: Date? = nil,
    delay: Duration = .zero,
    inbound: RecordingInboundCoordinator? = nil
  ) -> Fixture {
    let clock = TestClock(start)
    let statusStore = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(lastAttemptedAt: lastAttemptedAt)
    )
    let outbound = RecordingOutboundCoordinator(delay: delay)
    let inbound = inbound ?? RecordingInboundCoordinator(delay: delay)
    let coordinator = BidirectionalSyncCoordinator(
      outbound: outbound,
      inbound: inbound,
      configurationStore: configuredStore(frequency: frequency),
      statusStore: statusStore,
      now: { clock.now }
    )
    return Fixture(
      coordinator: coordinator,
      outbound: outbound,
      inbound: inbound,
      statusStore: statusStore,
      clock: clock
    )
  }

  private func configuredStore(
    frequency: BackgroundSyncFrequency
  ) -> InMemoryConfigurationStore {
    InMemoryConfigurationStore(
      configuration: AppConfiguration(
        baseURL: "https://ha.example.com",
        allowsConfirmedLocalHTTP: false,
        healthBridgeUserID: "example-user",
        selectedMetrics: [.steps, .bodyMass],
        backgroundSyncEnabled: true,
        backgroundSyncFrequency: frequency
      )
    )
  }

  private struct Fixture {
    let coordinator: BidirectionalSyncCoordinator
    let outbound: RecordingOutboundCoordinator
    let inbound: RecordingInboundCoordinator
    let statusStore: InMemorySyncStatusStore
    let clock: TestClock
  }
}

private final class TestClock: @unchecked Sendable {
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
  private(set) var triggers: [SyncTrigger] = []
  private(set) var requestedMetrics: [Set<MetricID>] = []
  private(set) var cancellationCount = 0
  private(set) var deadlines: [ExecutionDeadline?] = []
  private(set) var medicationFlags: [Bool] = []
  private(set) var windowTouches: [[MetricID: Date]] = []
  private(set) var collectionOrders: [[MetricID]?] = []

  init(delay: Duration = .zero) {
    self.delay = delay
  }

  var callCount: Int { triggers.count }

  func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?,
    includesMedications: Bool,
    lastWindowTouchAt: [MetricID: Date],
    orderedMetrics: [MetricID]?
  ) async -> SyncReport {
    medicationFlags.append(includesMedications)
    windowTouches.append(lastWindowTouchAt)
    collectionOrders.append(orderedMetrics)
    return await sync(trigger: trigger, metrics: metrics, deadline: deadline)
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
    triggers.append(trigger)
    requestedMetrics.append(metrics ?? [])
    do {
      try await Task.sleep(for: delay)
    } catch {
      cancellationCount += 1
    }
    let date = Date(timeIntervalSince1970: 1_788_035_400)
    return SyncReport(
      trigger: trigger,
      attemptedMetrics: 2,
      synchronizedMetrics: Task.isCancelled ? 0 : 2,
      skippedMetrics: 0,
      failures: Task.isCancelled ? [.init(metricID: nil, category: .cancelled)] : [],
      startedAt: date,
      finishedAt: date
    )
  }
}

private actor RecordingInboundCoordinator: InboundSyncCoordinating {
  private let delay: Duration
  private let failures: [InboundSyncFailure]
  private(set) var triggers: [SyncTrigger] = []
  private(set) var cancellationCount = 0
  private(set) var deadlines: [ExecutionDeadline?] = []

  init(
    delay: Duration = .zero,
    failures: [InboundSyncFailure] = []
  ) {
    self.delay = delay
    self.failures = failures
  }

  var callCount: Int { triggers.count }

  func sync(trigger: SyncTrigger, deadline: ExecutionDeadline?) async -> InboundSyncReport {
    deadlines.append(deadline)
    return await sync(trigger: trigger)
  }

  func sync(trigger: SyncTrigger) async -> InboundSyncReport {
    triggers.append(trigger)
    do {
      try await Task.sleep(for: delay)
    } catch {
      cancellationCount += 1
    }
    let date = Date(timeIntervalSince1970: 1_788_035_400)
    let reportFailures =
      Task.isCancelled ? [.init(pairingID: nil, category: .cancelled)] : failures
    return InboundSyncReport(
      trigger: trigger,
      attemptedPairings: 1,
      savedPairings: reportFailures.isEmpty ? 1 : 0,
      skippedPairings: 0,
      failures: reportFailures,
      startedAt: date,
      finishedAt: date
    )
  }
}

private actor FailingConfigurationStore: ConfigurationStore {
  func load() throws -> AppConfiguration { throw Failure.expected }
  func save(_ configuration: AppConfiguration) throws { throw Failure.expected }
  func delete() throws { throw Failure.expected }

  private enum Failure: Error { case expected }
}

private actor SlowInterruptedCheckStatusStore: SyncStatusStore {
  private let wrapped: InMemorySyncStatusStore
  private let delay: Duration

  init(wrapping wrapped: InMemorySyncStatusStore, delay: Duration = .milliseconds(50)) {
    self.wrapped = wrapped
    self.delay = delay
  }

  func snapshot() async throws -> SyncStatusSnapshot {
    await wrapped.snapshot()
  }

  func recordAttempt(trigger: SyncTrigger, at date: Date) async throws {
    try await wrapped.recordAttempt(trigger: trigger, at: date)
  }

  func record(report: SyncReport) async throws {
    try await wrapped.record(report: report)
  }

  func record(report: BidirectionalSyncReport) async throws {
    try await wrapped.record(report: report)
  }

  func recordInterruptedAttemptIfNeeded() async throws -> SyncStatusEvent? {
    try? await Task.sleep(for: delay)
    return try await wrapped.recordInterruptedAttemptIfNeeded()
  }

  func recordThrottledWake() async throws {
    try await wrapped.recordThrottledWake()
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

private struct FixedContextProvider: SyncRunContextProviding {
  let context: SyncRunContext

  func currentContext() async -> SyncRunContext? { context }
}
