import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Batched outbound synchronization")
struct BatchedSyncCoordinatorTests {
  private let now = Date(timeIntervalSince1970: 1_788_035_400)
  private let oldAnchor = Data([1])
  private let candidateAnchor = Data([2])
  private let metrics: [MetricID] = [.steps, .bodyMass, .restingHeartRate]

  @Test("Changed metrics share one request and commit every anchor")
  func batched() async throws {
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(metrics))

    #expect(report.synchronizedMetrics == 3)
    #expect(report.failures.isEmpty)
    #expect(report.requestCount == 1)
    #expect(await sender.batches.map(Set.init) == [Set(metrics.map(\.rawValue))])
    #expect(await sender.individualKeys.isEmpty)
    for metric in metrics {
      #expect(await context.store.anchor(for: metric) == candidateAnchor)
    }
  }

  @Test("Skipped entities fall back to one request per metric")
  func partialFallback() async throws {
    let sender = BatchSender(batchOutcomes: [.partial])
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(metrics))

    #expect(report.synchronizedMetrics == 3)
    #expect(report.requestCount == 4)
    #expect(Set(await sender.individualKeys) == Set(metrics.map(\.rawValue)))
  }

  @Test("HTTP 422 falls back to one request per metric")
  func validationFallback() async throws {
    let sender = BatchSender(batchOutcomes: [.failure(.validation)])
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(metrics))

    #expect(report.synchronizedMetrics == 3)
    #expect(await sender.individualKeys.count == 3)
  }

  @Test("A network failure fails the chunk and commits nothing")
  func networkFailure() async throws {
    let sender = BatchSender(batchOutcomes: [.failure(.server(statusCode: 503))])
    let context = try await makeContext(
      metrics: metrics,
      sender: sender,
      retryPolicy: RetryPolicy(maximumAttempts: 1)
    )

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(metrics))

    #expect(report.synchronizedMetrics == 0)
    #expect(report.failures.map(\.category) == [.server, .server, .server])
    for metric in metrics {
      #expect(await context.store.anchor(for: metric) == oldAnchor)
    }
  }

  @Test("Pending entries are chunked at fifty keys")
  func chunking() async throws {
    let many = MetricRegistry.selectable
      .filter { $0.aggregation != .latestWorkout }
      .prefix(60)
      .map(\.id)
    let sender = BatchSender()
    let context = try await makeContext(metrics: many, sender: sender)

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(many))

    #expect(await sender.batches.map(\.count) == [50, 10])
    #expect(report.synchronizedMetrics == 60)
    #expect(report.requestCount == 2)
  }

  @Test("Background request timeouts are capped at ten seconds")
  func timeouts() async throws {
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    _ = await context.coordinator.sync(
      trigger: .appRefresh,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: now.addingTimeInterval(25))
    )

    #expect(await sender.timeouts == [10])
  }

  @Test("An exhausted deadline sends nothing and keeps anchors")
  func deadline() async throws {
    let sender = BatchSender()
    let context = try await makeContext(metrics: metrics, sender: sender)

    let report = await context.coordinator.sync(
      trigger: .appRefresh,
      metrics: Set(metrics),
      deadline: ExecutionDeadline(expiresAt: now.addingTimeInterval(-1))
    )

    #expect(report.failures.map(\.category).contains(.deadlineExceeded))
    #expect(report.synchronizedMetrics == 0)
    #expect(await sender.batches.isEmpty)
    #expect(await sender.individualKeys.isEmpty)
    for metric in metrics {
      #expect(await context.store.anchor(for: metric) == oldAnchor)
    }
  }

  @Test("Collection runs concurrently within the collector limit")
  func concurrency() async throws {
    let many = MetricRegistry.selectable
      .filter { $0.aggregation != .latestWorkout }
      .prefix(20)
      .map(\.id)
    let changeQuery = SlowChangeQuery(
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let context = try await makeContext(
      metrics: many,
      sender: BatchSender(),
      changeQuery: changeQuery
    )

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(many))

    #expect(report.synchronizedMetrics == 20)
    let maximum = await changeQuery.maximumConcurrent
    #expect(maximum > 1)
    #expect(maximum <= SyncCoordinator.maximumConcurrentCollectors)
  }

  @Test("A lock on a later metric keeps accounting whole and sends entries collected before it")
  func lockOnLaterMetric() async throws {
    let many = Array(
      MetricRegistry.selectable
        .filter { $0.aggregation != .latestWorkout }
        .prefix(14)
        .map(\.id)
    )
    // The fifth metric locks. Two metrics are never scheduled, so unscheduled accounting counts.
    let lockedMetric = many[4]
    let changeQuery = LockOnMetricChangeQuery(
      order: many,
      lockedMetric: lockedMetric,
      changes: MetricChanges(
        addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
    )
    let sender = BatchSender()
    let context = try await makeContext(metrics: many, sender: sender, changeQuery: changeQuery)

    let report = await context.coordinator.sync(trigger: .manual, metrics: Set(many))

    #expect(report.attemptedMetrics == 14)
    #expect(report.skippedMetrics == 10)
    #expect(report.failures.filter { $0.category == .deviceLocked }.count == 1)
    #expect(report.failures == [.init(metricID: nil, category: .deviceLocked)])
    let metricScopedFailures = report.failures.filter { $0.metricID != nil }.count
    #expect(
      report.skippedMetrics + report.synchronizedMetrics + metricScopedFailures
        == report.attemptedMetrics
    )
    let collectedBeforeLock = Array(many.prefix(4))
    #expect(report.synchronizedMetrics == collectedBeforeLock.count)
    #expect(await sender.batches.map(Set.init) == [Set(collectedBeforeLock.map(\.rawValue))])
    for metric in collectedBeforeLock {
      #expect(await context.store.anchor(for: metric) == candidateAnchor)
    }
    for metric in many.dropFirst(4) {
      #expect(await context.store.anchor(for: metric) == oldAnchor)
    }
  }

  private func makeContext(
    metrics: [MetricID],
    sender: BatchSender,
    retryPolicy: RetryPolicy = .default,
    changeQuery suppliedChangeQuery: (any MetricChangeQuerying)? = nil
  ) async throws -> (coordinator: SyncCoordinator, store: TransactionCheckpointStore) {
    let query = FakeMetricQueryService()
    for (index, metric) in metrics.enumerated() {
      await query.configureReading(
        MetricReading(metricID: metric, timestamp: now, value: Double(index + 1)),
        for: metric
      )
    }
    let store = TransactionCheckpointStore(
      anchors: Dictionary(uniqueKeysWithValues: metrics.map { ($0, oldAnchor) })
    )
    let changeQuery =
      suppliedChangeQuery
      ?? TransactionChangeQuery(
        changes: MetricChanges(
          addedSampleIDs: [UUID()], deletedSampleIDs: [], candidateAnchor: candidateAnchor)
      )
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    let coordinator = SyncCoordinator(
      configurationStore: InMemoryConfigurationStore(
        configuration: AppConfiguration(
          baseURL: "https://ha.example.com",
          allowsConfirmedLocalHTTP: false,
          healthBridgeUserID: "example-user",
          selectedMetrics: Set(metrics),
          backgroundSyncEnabled: true
        )
      ),
      credentialStore: credentials,
      metricQuery: query,
      webhookSender: sender,
      calendar: Calendar(identifier: .gregorian),
      now: { now },
      checkpointStore: store,
      changeQuery: changeQuery,
      retryPolicy: retryPolicy,
      sleeper: RecordingSleeper(),
      jitterSource: FixedJitterSource()
    )
    return (coordinator, store)
  }
}

actor BatchSender: HealthBridgeSending {
  enum BatchOutcome: Sendable {
    case applied
    case partial
    case failure(NetworkFailure)
  }

  private var batchOutcomes: [BatchOutcome]
  private(set) var batches: [[String]] = []
  private(set) var timeouts: [TimeInterval] = []
  private(set) var individualKeys: [String] = []

  init(batchOutcomes: [BatchOutcome] = []) {
    self.batchOutcomes = batchOutcomes
  }

  func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) -> LiveAcknowledgement {
    individualKeys.append(reading.metricID.rawValue)
    return acknowledgement(requestID: requestID, received: 1, updated: 1, skipped: 0)
  }

  func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) -> LiveAcknowledgement {
    individualKeys.append(MetricID.lastAppleWorkout.rawValue)
    return acknowledgement(requestID: requestID, received: 1, updated: 1, skipped: 0)
  }

  func send(
    batch: [LiveBatchEntry],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) throws -> LiveAcknowledgement {
    batches.append(batch.map(\.key))
    timeouts.append(timeout)
    let outcome = batchOutcomes.isEmpty ? .applied : batchOutcomes.removeFirst()
    switch outcome {
    case .applied:
      return acknowledgement(
        requestID: requestID, received: batch.count, updated: batch.count, skipped: 0)
    case .partial:
      return acknowledgement(
        requestID: requestID, received: batch.count, updated: batch.count - 1, skipped: 1)
    case .failure(let failure):
      throw failure
    }
  }

  private func acknowledgement(
    requestID: String,
    received: Int,
    updated: Int,
    skipped: Int
  ) -> LiveAcknowledgement {
    LiveAcknowledgement(
      ok: true,
      applied: true,
      integrationVersion: "1.2.1",
      requestType: "live",
      protocolVersion: 1,
      requestID: requestID,
      receivedEntities: received,
      updatedEntities: updated,
      skippedEntities: skipped,
      lastSyncUpdated: true,
      error: nil
    )
  }
}

actor SlowChangeQuery: MetricChangeQuerying {
  private let result: MetricChanges
  private var concurrent = 0
  private(set) var maximumConcurrent = 0

  init(changes: MetricChanges) {
    result = changes
  }

  func changes(for metric: MetricID, committedAnchor: Data?) async throws -> MetricChanges {
    concurrent += 1
    maximumConcurrent = max(maximumConcurrent, concurrent)
    defer { concurrent -= 1 }
    try await Task.sleep(for: .milliseconds(20))
    return result
  }
}

/// Answers metrics before `lockedMetric` immediately, reports the lock after a short delay and
/// holds later metrics long enough to be cancelled by it.
actor LockOnMetricChangeQuery: MetricChangeQuerying {
  private let order: [MetricID]
  private let lockedMetric: MetricID
  private let result: MetricChanges

  init(order: [MetricID], lockedMetric: MetricID, changes: MetricChanges) {
    self.order = order
    self.lockedMetric = lockedMetric
    result = changes
  }

  func changes(for metric: MetricID, committedAnchor: Data?) async throws -> MetricChanges {
    guard let index = order.firstIndex(of: metric),
      let lockIndex = order.firstIndex(of: lockedMetric)
    else { return result }
    if index < lockIndex { return result }
    if index == lockIndex {
      try await Task.sleep(for: .milliseconds(50))
      throw MetricChangeQueryError.databaseInaccessible
    }
    try await Task.sleep(for: .seconds(5))
    return result
  }
}
