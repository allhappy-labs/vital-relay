import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Send reserve and collection order")
struct SendReserveTests {
  private let start = Date(timeIntervalSince1970: 1_788_035_400)
  private let oldAnchor = Data([1])
  private let candidateAnchor = Data([2])

  @Test("Collection stops while there is budget left to send what it collected")
  func collectionStopsAtTheReserve() async throws {
    let metrics = Self.metrics(count: 40)
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(
      trigger: .appRefresh,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: start.addingTimeInterval(25))
    )

    let batch = try #require(await sender.batches.first)
    #expect(await sender.batches.count == 1)
    #expect(report.attemptedMetrics == 40)
    #expect(report.collectedMetrics == batch.count)
    #expect(report.deferredMetrics == 40 - batch.count)
    #expect(report.synchronizedMetrics == batch.count)
    #expect(report.failures.isEmpty)
    #expect(report.collectSeconds + report.sendSeconds <= 25)
    // Every collector spends a second of the 25 s budget. Scheduling stops once the remaining
    // budget is down to the 8 s reserve, so at least 17 metrics are collected, and at most the
    // eight concurrent collectors already past that check can run on — never all 40.
    #expect(batch.count >= 17)
    #expect(batch.count <= 24)
    let collected = Set(batch)
    for metric in metrics {
      #expect(
        await context.store.anchor(for: metric)
          == (collected.contains(metric.rawValue) ? candidateAnchor : oldAnchor)
      )
    }
  }

  @Test("The report counts what was collected and how long each phase took")
  func reportRecordsCollectionAndSendTimings() async throws {
    let metrics = Self.metrics(count: 3)
    // The first request fails and the retry sleeps one second, which the sleeper charges to the
    // run's clock the way a real wait would.
    let sender = BatchSender(batchOutcomes: [.failure(.server(statusCode: 503))])
    let clock = AdvancingClock(start)
    let context = try await makeContext(
      metrics: metrics,
      sender: sender,
      clock: clock,
      sleeper: ClockAdvancingSleeper(clock: clock)
    )

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(metrics))

    #expect(report.collectedMetrics == 3)
    #expect(report.synchronizedMetrics == 3)
    #expect(report.collectSeconds == 3)
    #expect(report.sendSeconds == 1)
    #expect(report.collectSeconds + report.sendSeconds <= 25)
  }

  @Test("A supplied order decides which metrics are collected first")
  func suppliedOrderDecidesCollectionOrder() async throws {
    let metrics = Self.metrics(count: 6)
    let rotated = Array(metrics.dropFirst(2) + metrics.prefix(2))
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(
      trigger: .manual,
      metrics: Set(metrics),
      deadline: nil,
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: rotated
    )

    // Collectors run concurrently, so the batch — which follows the collection order — is where
    // the run's order shows, not the order the change query happens to be reached in.
    #expect(report.synchronizedMetrics == 6)
    #expect(await sender.batches == [rotated.map(\.rawValue)])
  }

  @Test("A truncated run collects the prefix of the supplied order")
  func truncatedRunCollectsTheOrderedPrefix() async throws {
    let metrics = Self.metrics(count: 6)
    let rotated = Array(metrics.dropFirst(2) + metrics.prefix(2))
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    // Nine seconds leaves room for one metric: after it, the remaining eight seconds are the
    // reserve, so no further collector is scheduled.
    let report = await context.coordinator.sync(
      trigger: .appRefresh,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: start.addingTimeInterval(9)),
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: rotated
    )

    #expect(report.attemptedMetrics == 6)
    #expect(report.collectedMetrics == 1)
    #expect(report.synchronizedMetrics == 1)
    #expect(await context.changeQuery.requestedMetrics == [rotated[0]])
    #expect(await sender.individualKeys == [rotated[0].rawValue])
    #expect(await context.store.anchor(for: rotated[0]) == candidateAnchor)
    for metric in rotated.dropFirst() {
      #expect(await context.store.anchor(for: metric) == oldAnchor)
    }
  }

  @Test("Without a deadline no reserve is withheld and every metric is collected")
  func noDeadlineCollectsEveryMetric() async throws {
    let metrics = Self.metrics(count: 40)
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(metrics))

    #expect(report.collectedMetrics == 40)
    #expect(report.synchronizedMetrics == 40)
    #expect(await sender.batches.map(\.count) == [40])
    for metric in metrics {
      #expect(await context.store.anchor(for: metric) == candidateAnchor)
    }
  }

  @Test("A complete run defers nothing, even though medications add an attempt")
  func completeRunDefersNothing() async throws {
    let metrics = Self.metrics(count: 6)
    let context = try await makeContext(
      metrics: metrics,
      sender: BatchSender(),
      medicationCoordinator: Self.synchronizingMedications
    )

    let report = await context.coordinator.sync(
      trigger: .appRefresh,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: start.addingTimeInterval(25)),
      includesMedications: true,
      lastWindowTouchAt: [:],
      orderedMetrics: nil
    )

    // Medications are attempted on top of the selected metrics, so `attempted - collected` is not
    // a truncation signal; `deferredMetrics` is.
    #expect(report.attemptedMetrics == 7)
    #expect(report.collectedMetrics == 6)
    #expect(report.synchronizedMetrics == 7)
    #expect(report.deferredMetrics == 0)
  }

  @Test("A truncated run reports every metric the reserve left behind")
  func truncatedRunReportsDeferredMetrics() async throws {
    let metrics = Self.metrics(count: 6)
    let context = try await makeContext(
      metrics: metrics,
      sender: BatchSender(),
      medicationCoordinator: Self.synchronizingMedications
    )

    let report = await context.coordinator.sync(
      trigger: .appRefresh,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: start.addingTimeInterval(9)),
      includesMedications: true,
      lastWindowTouchAt: [:],
      orderedMetrics: nil
    )

    #expect(report.attemptedMetrics == 7)
    #expect(report.collectedMetrics == 1)
    #expect(report.deferredMetrics == 5)
  }

  @Test("A partial order collects what it names first and the rest in registry order")
  func partialOrderIsCompletedWithRegistryOrder() async throws {
    let metrics = Self.metrics(count: 6)
    let unselected = try #require(Self.metrics(count: 8).last)
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(
      trigger: .manual,
      metrics: Set(metrics),
      deadline: nil,
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: [metrics[4], unselected, metrics[1]]
    )

    let expected = [metrics[4], metrics[1], metrics[0], metrics[2], metrics[3], metrics[5]]
    #expect(report.collectedMetrics == 6)
    #expect(report.synchronizedMetrics == 6)
    #expect(await sender.batches == [expected.map(\.rawValue)])
  }

  @Test("A collector that outlives the reserve is abandoned and its metric deferred")
  func collectorThatOutlivesTheReserveIsDeferred() async throws {
    let metrics = Self.metrics(count: 4)
    // Every metric but the lock probe stalls in a way cancellation cannot shorten, the way a cold
    // HealthKit anchored query does. The reserve may only admit collectors while more than
    // `sendReserve` is left, so all three start — bounding admission alone cannot end this run.
    let changeQuery = StallingChangeQuery(
      stalling: Set(metrics.dropFirst()),
      stallSeconds: 10,
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let context = try await makeContext(
      metrics: metrics,
      sender: BatchSender(),
      changeQuery: changeQuery,
      now: { Date() }
    )

    let startedAt = Date()
    let report = await context.coordinator.sync(
      trigger: .healthKitObserver,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(
        expiresAt: startedAt.addingTimeInterval(SyncCoordinator.sendReserve + 0.5)),
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: metrics
    )

    #expect(Date().timeIntervalSince(startedAt) < 5)
    #expect(report.collectedMetrics == 1)
    #expect(report.deferredMetrics == 3)
    // A deferred metric was never answered for, so it keeps its anchor for the next run.
    for metric in metrics.dropFirst() {
      #expect(await context.store.anchor(for: metric) == oldAnchor)
    }
  }

  @Test("A cancelled run accounts for every metric, in flight or not yet reached")
  func cancelledRunAccountsForEveryMetric() async throws {
    let metrics = Self.metrics(count: 12)
    let changeQuery = StallingChangeQuery(
      stalling: Set(metrics.dropFirst()),
      stallSeconds: 0.6,
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let context = try await makeContext(
      metrics: metrics,
      sender: BatchSender(),
      changeQuery: changeQuery,
      now: { Date() }
    )
    let coordinator = context.coordinator

    let run = Task {
      await coordinator.sync(
        trigger: .healthKitObserver,
        metrics: Set(metrics),
        deadline: nil,
        includesMedications: false,
        lastWindowTouchAt: [:],
        orderedMetrics: metrics
      )
    }
    try await Task.sleep(for: .milliseconds(200))
    run.cancel()
    let report = await run.value

    // Cancellation reaches the eight admitted collectors in one pass, and three metrics were
    // never scheduled at all. Neither group was looked at, so all eleven are deferred: they keep
    // their anchors and their freshness and lead the next run.
    #expect(report.collectedMetrics == 1)
    #expect(report.skippedMetrics == 0)
    #expect(report.deferredMetrics == 11)
    // Every requested metric lands in exactly one bucket. `skippedMetrics` is not a third bucket
    // — an unchanged metric was still looked at, so it counts in `collectedMetrics` too — which
    // is why this run is arranged to skip nothing.
    #expect(
      report.collectedMetrics + report.skippedMetrics + report.deferredMetrics
        == report.attemptedMetrics
    )
    // One row per category rather than one per metric: eight collectors were cancelled together,
    // and a persisted event must not carry eight identical rows. The second row is the send's,
    // for the chunk it never started.
    #expect(report.failures.map(\.category) == [.cancelled, .cancelled])
    #expect(report.failures.filter { $0.metricID != nil }.count == 2)
    for metric in metrics.dropFirst() {
      #expect(await context.store.anchor(for: metric) == oldAnchor)
    }
  }

  @Test("A request that outlives the deadline is abandoned rather than awaited")
  func requestThatOutlivesTheDeadlineIsAbandoned() async throws {
    let metrics = Self.metrics(count: 1)
    // The timeout handed to the transport is an idle timeout, and the name lookup ahead of it
    // observes no timeout at all: a send can outlive the deadline whatever value is passed down.
    let sender = StallingSender(stallSeconds: 10)
    let context = try await makeContext(metrics: metrics, sender: sender, now: { Date() })

    let startedAt = Date()
    let report = await context.coordinator.sync(
      trigger: .healthKitObserver,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: startedAt.addingTimeInterval(1)),
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: metrics
    )

    #expect(Date().timeIntervalSince(startedAt) < 5)
    #expect(report.requestCount == 1)
    #expect(report.synchronizedMetrics == 0)
    #expect(report.failures.map(\.category) == [.deadlineExceeded])
    let metric = try #require(metrics.first)
    #expect(await context.store.anchor(for: metric) == oldAnchor)
    // The run looked at the metric, but its value is still only on the phone: collected, not
    // resolved. Recording a check for it would let the staleness rule call unsent data fresh.
    #expect(report.collectedMetricIDs == [metric])
    #expect(report.resolvedMetricIDs.isEmpty)
  }

  @Test("A probe that never answers does not block the metrics behind it")
  func hungProbeDoesNotBlockTheRest() async throws {
    let metrics = Self.metrics(count: 4)
    let probe = try #require(metrics.first)
    // Only the lock probe stalls, the way a HealthKit anchored query does when the database has
    // been locked for hours: the wait happens in a detached task, so cancellation cannot shorten
    // it and the probe never answers at all — neither a value nor `databaseInaccessible`.
    let changeQuery = StallingChangeQuery(
      stalling: [probe],
      stallSeconds: 30,
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let sender = BatchSender()
    let context = try await makeContext(
      metrics: metrics,
      sender: sender,
      changeQuery: changeQuery,
      now: { Date() }
    )

    let startedAt = Date()
    // Enough budget that giving up on the probe still leaves more than the send reserve.
    let budget = SyncCoordinator.probeTimeout + SyncCoordinator.sendReserve + 3
    let report = await context.coordinator.sync(
      trigger: .healthKitObserver,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: startedAt.addingTimeInterval(budget)),
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: metrics
    )

    // A probe that hung says nothing about the device: it is deferred, keeping its anchor and
    // its freshness, and the three metrics behind it are collected and sent with what is left.
    #expect(report.collectedMetrics == 3)
    #expect(report.deferredMetrics == 1)
    #expect(report.synchronizedMetrics == 3)
    #expect(report.requestCount >= 1)
    #expect(report.failures.allSatisfy { $0.category != .deviceLocked })
    #expect(await context.store.anchor(for: probe) == oldAnchor)
    for metric in metrics.dropFirst() {
      #expect(await context.store.anchor(for: metric) == candidateAnchor)
    }
    #expect(Date().timeIntervalSince(startedAt) < budget)
  }

  @Test("A hung probe spends the probe timeout, not the whole budget")
  func hungProbeIsBoundedByTheProbeTimeout() async throws {
    let metrics = Self.metrics(count: 4)
    let probe = try #require(metrics.first)
    let changeQuery = StallingChangeQuery(
      stalling: [probe],
      stallSeconds: 30,
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let context = try await makeContext(
      metrics: metrics,
      sender: BatchSender(),
      changeQuery: changeQuery,
      now: { Date() }
    )

    let startedAt = Date()
    // Four times the probe timeout, so a probe bounded at the deadline would spend all of it.
    let budget = SyncCoordinator.probeTimeout * 4
    let report = await context.coordinator.sync(
      trigger: .healthKitObserver,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: startedAt.addingTimeInterval(budget)),
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: metrics
    )

    #expect(report.collectSeconds >= SyncCoordinator.probeTimeout)
    #expect(report.collectSeconds < SyncCoordinator.probeTimeout + 2)
    #expect(Date().timeIntervalSince(startedAt) < budget)
    #expect(report.collectedMetrics == 3)
    // The probe hung; asking it again in the same run would only hang again. It is queried once,
    // deferred once, and leads the next run.
    let requested = await changeQuery.requestedMetrics
    #expect(requested.filter { $0 == probe }.count == 1)
  }

  @Test("A probe that answers locked still short-circuits the whole run")
  func lockedProbeShortCircuitsTheRun() async throws {
    let metrics = Self.metrics(count: 4)
    let probe = try #require(metrics.first)
    // The probe returns `databaseInaccessible` promptly, as a locked database does; every metric
    // behind it would stall for five seconds if the run wrongly carried on.
    let changeQuery = LockOnMetricChangeQuery(
      order: metrics,
      lockedMetric: probe,
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let sender = BatchSender()
    let context = try await makeContext(
      metrics: metrics,
      sender: sender,
      changeQuery: changeQuery,
      now: { Date() }
    )

    let startedAt = Date()
    let report = await context.coordinator.sync(
      trigger: .healthKitObserver,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(
        expiresAt: startedAt.addingTimeInterval(SyncCoordinator.probeTimeout * 4)),
      includesMedications: false,
      lastWindowTouchAt: [:],
      orderedMetrics: metrics
    )

    // A lock is an answer, and the answer is that nothing on this device can be read: the run
    // skips every metric, records `deviceLocked` and sends nothing.
    #expect(Date().timeIntervalSince(startedAt) < SyncCoordinator.probeTimeout)
    #expect(report.collectedMetrics == 0)
    #expect(report.deferredMetrics == 0)
    #expect(report.skippedMetrics == 4)
    #expect(report.failures == [.init(metricID: nil, category: .deviceLocked)])
    #expect(report.requestCount == 0)
    #expect(await sender.batches.isEmpty)
    for metric in metrics {
      #expect(await context.store.anchor(for: metric) == oldAnchor)
    }
  }

  private static let synchronizingMedications = FakeMedicationSyncCoordinator(
    report: MedicationSyncReport(
      attempted: true, synchronized: true, skipped: false, failure: nil)
  )

  private static func metrics(count: Int) -> [MetricID] {
    Array(
      MetricRegistry.selectable
        .filter { $0.aggregation != .latestWorkout }
        .prefix(count)
        .map(\.id)
    )
  }

  private struct Context {
    let coordinator: SyncCoordinator
    let store: TransactionCheckpointStore
    let changeQuery: MeteredChangeQuery
  }

  private func makeContext(
    metrics: [MetricID],
    sender: any HealthBridgeSending,
    clock suppliedClock: AdvancingClock? = nil,
    sleeper: any SyncSleeper = RecordingSleeper(),
    medicationCoordinator: (any MedicationSynchronizing)? = nil,
    changeQuery suppliedChangeQuery: (any MetricChangeQuerying)? = nil,
    now: (@Sendable () -> Date)? = nil
  ) async throws -> Context {
    let clock = suppliedClock ?? AdvancingClock(start)
    let query = FakeMetricQueryService()
    for (index, metric) in metrics.enumerated() {
      await query.configureReading(
        MetricReading(metricID: metric, timestamp: start, value: Double(index + 1)),
        for: metric
      )
    }
    let store = TransactionCheckpointStore(
      anchors: Dictionary(uniqueKeysWithValues: metrics.map { ($0, oldAnchor) })
    )
    let meteredChangeQuery = MeteredChangeQuery(
      clock: clock,
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let changeQuery = suppliedChangeQuery ?? meteredChangeQuery
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    let coordinator = SyncCoordinator(
      configurationStore: InMemoryConfigurationStore(
        configuration: AppConfiguration(
          baseURL: "https://ha.example.com",
          allowsConfirmedLocalHTTP: false,
          healthBridgeUserID: "example-user",
          selectedMetrics: Set(metrics),
          backgroundSyncEnabled: true,
          medicationSyncEnabled: medicationCoordinator != nil
        )
      ),
      credentialStore: credentials,
      metricQuery: query,
      webhookSender: sender,
      calendar: Calendar(identifier: .gregorian),
      now: now ?? { clock.now },
      checkpointStore: store,
      changeQuery: changeQuery,
      sleeper: sleeper,
      jitterSource: FixedJitterSource(),
      medicationSyncCoordinator: medicationCoordinator
    )
    return Context(coordinator: coordinator, store: store, changeQuery: meteredChangeQuery)
  }
}

/// A clock the doubles below move forward, so a run's deadline runs down as it works instead of
/// depending on how fast the test machine is.
final class AdvancingClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) {
    self.date = date
  }

  var now: Date {
    lock.withLock { date }
  }

  func advance(by seconds: TimeInterval) {
    lock.withLock { date = date.addingTimeInterval(seconds) }
  }
}

/// Charges the run's clock for every change query, so collecting a metric costs budget.
actor MeteredChangeQuery: MetricChangeQuerying {
  private let clock: AdvancingClock
  private let seconds: TimeInterval
  private let result: MetricChanges
  private(set) var requestedMetrics: [MetricID] = []

  init(clock: AdvancingClock, seconds: TimeInterval = 1, changes: MetricChanges) {
    self.clock = clock
    self.seconds = seconds
    result = changes
  }

  func changes(for metric: MetricID, committedAnchor: Data?) -> MetricChanges {
    requestedMetrics.append(metric)
    clock.advance(by: seconds)
    return result
  }
}

/// Charges the run's clock for a retry wait instead of waiting.
actor ClockAdvancingSleeper: SyncSleeper {
  private let clock: AdvancingClock

  init(clock: AdvancingClock) {
    self.clock = clock
  }

  func sleep(for delay: TimeInterval) throws {
    try Task.checkCancellation()
    clock.advance(by: delay)
  }
}

/// Stalls the metrics it is given in a way cancellation cannot shorten, the way HealthKit's own
/// queries do: the wait happens in a detached task, which inherits no cancellation.
actor StallingChangeQuery: MetricChangeQuerying {
  private let stalling: Set<MetricID>
  private let stallSeconds: Double
  private let result: MetricChanges
  private(set) var requestedMetrics: [MetricID] = []

  init(stalling: Set<MetricID>, stallSeconds: Double, changes: MetricChanges) {
    self.stalling = stalling
    self.stallSeconds = stallSeconds
    result = changes
  }

  func changes(for metric: MetricID, committedAnchor: Data?) async throws -> MetricChanges {
    requestedMetrics.append(metric)
    guard stalling.contains(metric) else { return result }
    let seconds = stallSeconds
    await Task.detached { try? await Task.sleep(for: .seconds(seconds)) }.value
    return result
  }
}

/// Answers every send, but only after a wait cancellation cannot shorten — a stalled name lookup
/// or a connection that trickles just enough to keep URLSession's idle timeout from firing.
actor StallingSender: HealthBridgeSending {
  private let stallSeconds: Double
  private(set) var requestIDs: [String] = []

  init(stallSeconds: Double) {
    self.stallSeconds = stallSeconds
  }

  func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async -> LiveAcknowledgement {
    await stall(requestID: requestID)
    return acknowledgement(requestID: requestID, count: 1)
  }

  func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async -> LiveAcknowledgement {
    await stall(requestID: requestID)
    return acknowledgement(requestID: requestID, count: 1)
  }

  func send(
    batch: [LiveBatchEntry],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async -> LiveAcknowledgement {
    await stall(requestID: requestID)
    return acknowledgement(requestID: requestID, count: batch.count)
  }

  private func stall(requestID: String) async {
    requestIDs.append(requestID)
    let seconds = stallSeconds
    await Task.detached { try? await Task.sleep(for: .seconds(seconds)) }.value
  }

  private func acknowledgement(requestID: String, count: Int) -> LiveAcknowledgement {
    LiveAcknowledgement(
      ok: true,
      applied: true,
      integrationVersion: "1.2.1",
      requestType: "live",
      protocolVersion: 1,
      requestID: requestID,
      receivedEntities: count,
      updatedEntities: count,
      skippedEntities: 0,
      lastSyncUpdated: true,
      error: nil
    )
  }
}
