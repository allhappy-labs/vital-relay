import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Incremental anchor transaction")
struct AnchorTransactionTests {
  private let now = Date(timeIntervalSince1970: 1_788_035_400)
  private let oldAnchor = Data([1])
  private let candidateAnchor = Data([2])

  @Test("Commits the candidate only after a matching applied acknowledgement")
  func successCommit() async throws {
    let context = try await makeContext()

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.synchronizedMetrics == 1)
    #expect(report.failures.isEmpty)
    #expect(await context.store.anchor(for: .steps) == candidateAnchor)
    #expect(await context.store.commits == [.steps])
  }

  @Test(
    "Network and acknowledgement failures preserve the committed anchor",
    arguments: [
      TransactionSender.Outcome.failure(.server(statusCode: 503)),
      .mismatchedRequestID,
      .notApplied,
      .zeroUpdated,
    ]
  )
  func failedSendRollsBack(outcome: TransactionSender.Outcome) async throws {
    let context = try await makeContext(
      sender: TransactionSender(outcomes: [outcome]),
      retryPolicy: RetryPolicy(maximumAttempts: 1)
    )

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.synchronizedMetrics == 0)
    #expect(report.failures.count == 1)
    #expect(await context.store.anchor(for: .steps) == oldAnchor)
    #expect(await context.store.commits.isEmpty)
  }

  @Test("Cancellation during send preserves the committed anchor")
  func cancellationRollback() async throws {
    let sender = TransactionSender(outcomes: [.success], delay: .seconds(1))
    let context = try await makeContext(sender: sender)
    let task = Task {
      await context.coordinator.sync(trigger: .manual, metrics: [.steps])
    }
    await Task.yield()
    task.cancel()

    let report = await task.value

    #expect(report.failures.contains { $0.category == .cancelled })
    #expect(await context.store.anchor(for: .steps) == oldAnchor)
  }

  @Test("Transform or query failure preserves the committed anchor")
  func transformRollback() async throws {
    let query = FakeMetricQueryService()
    await query.configureQueryError(.queryFailed)
    let context = try await makeContext(query: query)

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.failures == [.init(metricID: .steps, category: .healthKit)])
    #expect(await context.store.anchor(for: .steps) == oldAnchor)
  }

  @Test("Checkpoint write failure is reported after send without claiming success")
  func checkpointFailure() async throws {
    let store = TransactionCheckpointStore(
      anchors: [.steps: oldAnchor],
      commitFails: true
    )
    let context = try await makeContext(store: store)

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.synchronizedMetrics == 0)
    #expect(report.failures == [.init(metricID: .steps, category: .checkpoint)])
    #expect(await store.anchor(for: .steps) == oldAnchor)
    #expect(await context.sender.requestIDs.count == 1)
  }

  @Test("A skipped metric whose checkpoint write fails is not recorded as checked")
  func skippedCommitFailureLeavesTheMetricUnchecked() async throws {
    // Changes arrived but the window holds no value, so there is nothing to send and only the
    // anchor to advance. When that write fails the anchor stays where it was, so the same changes
    // come back next run — recording the metric as checked would call it fresh for an hour and
    // leave the retry to the staleness rule instead of the next wake.
    let store = TransactionCheckpointStore(anchors: [.steps: oldAnchor], commitFails: true)
    let context = try await makeContext(query: FakeMetricQueryService(), store: store)

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.failures == [.init(metricID: .steps, category: .checkpoint)])
    #expect(report.collectedMetricIDs.isEmpty)
    #expect(await store.anchor(for: .steps) == oldAnchor)
  }

  @Test("Deletion recomputes and sends the authoritative replacement")
  func deletionReplacement() async throws {
    let query = FakeMetricQueryService()
    await query.configureReading(
      MetricReading(metricID: .bodyMass, timestamp: now, value: 79),
      for: .bodyMass
    )
    let changes = MetricChanges(
      addedSampleIDs: [],
      deletedSampleIDs: [UUID()],
      candidateAnchor: candidateAnchor
    )
    let context = try await makeContext(metric: .bodyMass, query: query, changes: changes)

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.bodyMass])

    #expect(report.synchronizedMetrics == 1)
    #expect(await context.store.anchor(for: .bodyMass) == candidateAnchor)
  }

  @Test("Deletion that empties a cumulative metric sends zero and commits")
  func deletionEmptyCumulative() async throws {
    let query = FakeMetricQueryService()
    await query.configureReading(
      MetricReading(metricID: .steps, timestamp: now, value: 0),
      for: .steps
    )
    let context = try await makeContext(query: query)

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.synchronizedMetrics == 1)
    #expect(await context.store.anchor(for: .steps) == candidateAnchor)
  }

  @Test("Deletion that empties a latest metric reports compatibility and rolls back")
  func deletionEmptyLatest() async throws {
    let query = FakeMetricQueryService()
    let changes = MetricChanges(
      addedSampleIDs: [],
      deletedSampleIDs: [UUID()],
      candidateAnchor: candidateAnchor
    )
    let context = try await makeContext(metric: .bodyMass, query: query, changes: changes)

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.bodyMass])

    #expect(report.failures == [.init(metricID: .bodyMass, category: .compatibility)])
    #expect(await context.store.anchor(for: .bodyMass) == oldAnchor)
    #expect(await context.sender.requestIDs.isEmpty)
  }

  @Test("Addition excluded from the latest reading commits and skips")
  func excludedAdditionWithoutCurrentValue() async throws {
    let query = FakeMetricQueryService()
    let changes = MetricChanges(
      addedSampleIDs: [UUID()],
      deletedSampleIDs: [],
      candidateAnchor: candidateAnchor
    )
    let context = try await makeContext(metric: .uvIndex, query: query, changes: changes)

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.uvIndex])

    #expect(report.synchronizedMetrics == 0)
    #expect(report.skippedMetrics == 1)
    #expect(report.failures.isEmpty)
    #expect(await context.store.anchor(for: .uvIndex) == candidateAnchor)
    #expect(await context.sender.requestIDs.isEmpty)
  }

  @Test("Initial historical sleep changes without a current value commit and skip")
  func initialHistoricalSleepWithoutCurrentValue() async throws {
    let query = FakeMetricQueryService()
    let changes = MetricChanges(
      addedSampleIDs: [UUID()],
      deletedSampleIDs: [],
      candidateAnchor: candidateAnchor
    )
    let store = TransactionCheckpointStore(anchors: [:])
    let context = try await makeContext(
      metric: .asleepTime,
      query: query,
      changes: changes,
      store: store
    )

    let report = await context.coordinator.sync(trigger: .manual, metrics: [.asleepTime])

    #expect(report.synchronizedMetrics == 0)
    #expect(report.skippedMetrics == 1)
    #expect(report.failures.isEmpty)
    #expect(await store.anchor(for: .asleepTime) == candidateAnchor)
    #expect(await context.sender.requestIDs.isEmpty)
  }

  @Test("No changes inside the current window neither sends nor advances the anchor")
  func noChanges() async throws {
    let changes = MetricChanges(
      addedSampleIDs: [],
      deletedSampleIDs: [],
      candidateAnchor: candidateAnchor
    )
    let context = try await makeContext(changes: changes)

    // Sent at `now`, so the metric's daily window cannot have rolled over since.
    let report = await context.coordinator.sync(
      trigger: .background,
      metrics: [.steps],
      deadline: nil,
      includesMedications: false,
      lastWindowTouchAt: [.steps: now]
    )

    #expect(report.skippedMetrics == 1)
    #expect(await context.store.anchor(for: .steps) == oldAnchor)
    #expect(await context.sender.requestIDs.isEmpty)
  }

  @Test("A locked HealthKit database preserves the anchor and exports after unlock")
  func lockedDatabaseRecoversAfterUnlock() async throws {
    let changeQuery = LockingTransactionChangeQuery(
      changes: MetricChanges(
        addedSampleIDs: [UUID()],
        deletedSampleIDs: [],
        candidateAnchor: candidateAnchor
      )
    )
    let context = try await makeContext(changeQuery: changeQuery)

    let locked = await context.coordinator.sync(trigger: .background, metrics: [.steps])

    #expect(locked.synchronizedMetrics == 0)
    #expect(locked.skippedMetrics == 1)
    #expect(locked.failures == [.init(metricID: nil, category: .deviceLocked)])
    #expect(await context.store.anchor(for: .steps) == oldAnchor)

    await changeQuery.unlock()
    let unlocked = await context.coordinator.sync(trigger: .background, metrics: [.steps])

    #expect(unlocked.synchronizedMetrics == 1)
    #expect(unlocked.failures.isEmpty)
    #expect(await context.store.anchor(for: .steps) == candidateAnchor)
  }

  @Test("A locked HealthKit database stops querying remaining metrics")
  func lockedDatabaseShortCircuitsRemainingMetrics() async throws {
    let changeQuery = LockingTransactionChangeQuery(
      changes: MetricChanges(
        addedSampleIDs: [UUID()],
        deletedSampleIDs: [],
        candidateAnchor: candidateAnchor
      )
    )
    let context = try await makeContext(
      selectedMetrics: [.steps, .bodyMass],
      changeQuery: changeQuery
    )

    let report = await context.coordinator.sync(
      trigger: .background,
      metrics: [.steps, .bodyMass]
    )

    #expect(report.attemptedMetrics == 2)
    #expect(report.skippedMetrics == 2)
    #expect(report.failures == [.init(metricID: nil, category: .deviceLocked)])
    #expect(await changeQuery.requestedMetrics.count == 1)
  }

  private func makeContext(
    metric: MetricID = .steps,
    selectedMetrics: Set<MetricID>? = nil,
    query suppliedQuery: FakeMetricQueryService? = nil,
    changes: MetricChanges? = nil,
    changeQuery suppliedChangeQuery: (any MetricChangeQuerying)? = nil,
    store suppliedStore: TransactionCheckpointStore? = nil,
    sender: TransactionSender = TransactionSender(outcomes: [.success]),
    retryPolicy: RetryPolicy = .default,
    sleeper: RecordingSleeper = RecordingSleeper(),
    deadline: ExecutionDeadline? = nil
  ) async throws -> TransactionContext {
    let query = suppliedQuery ?? FakeMetricQueryService()
    if suppliedQuery == nil {
      await query.configureReading(
        MetricReading(metricID: metric, timestamp: now, value: metric == .steps ? 8_421 : 80),
        for: metric
      )
    }
    let store = suppliedStore ?? TransactionCheckpointStore(anchors: [metric: oldAnchor])
    let candidate =
      changes
      ?? MetricChanges(
        addedSampleIDs: [UUID()],
        deletedSampleIDs: [],
        candidateAnchor: candidateAnchor
      )
    let changeQuery = suppliedChangeQuery ?? TransactionChangeQuery(changes: candidate)
    let configuration = AppConfiguration(
      baseURL: "https://ha.example.com",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: selectedMetrics ?? [metric],
      backgroundSyncEnabled: true
    )
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    let coordinator = SyncCoordinator(
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      metricQuery: query,
      webhookSender: sender,
      calendar: Calendar(identifier: .gregorian),
      now: { now },
      checkpointStore: store,
      changeQuery: changeQuery,
      retryPolicy: retryPolicy,
      sleeper: sleeper,
      jitterSource: FixedJitterSource(),
      deadline: deadline
    )
    return TransactionContext(
      coordinator: coordinator,
      store: store,
      sender: sender,
      sleeper: sleeper
    )
  }
}

private struct TransactionContext {
  let coordinator: SyncCoordinator
  let store: TransactionCheckpointStore
  let sender: TransactionSender
  let sleeper: RecordingSleeper
}

actor TransactionCheckpointStore: SyncCheckpointStore {
  private var anchors: [MetricID: Data]
  private let commitFails: Bool
  private(set) var commits: [MetricID] = []

  init(anchors: [MetricID: Data], commitFails: Bool = false) {
    self.anchors = anchors
    self.commitFails = commitFails
  }

  func anchor(for metric: MetricID) -> Data? {
    anchors[metric]
  }

  func commit(anchor: Data, for metric: MetricID) throws {
    try Task.checkCancellation()
    if commitFails {
      throw TransactionFailure.checkpoint
    }
    anchors[metric] = anchor
    commits.append(metric)
  }

  func reset(metric: MetricID) {
    anchors[metric] = nil
  }

  func resetAll() {
    anchors.removeAll()
  }
}

actor TransactionChangeQuery: MetricChangeQuerying {
  let changes: MetricChanges

  init(changes: MetricChanges) {
    self.changes = changes
  }

  func changes(for metric: MetricID, committedAnchor: Data?) -> MetricChanges {
    changes
  }
}

actor LockingTransactionChangeQuery: MetricChangeQuerying {
  private let changesResult: MetricChanges
  private var isLocked = true
  private(set) var requestedMetrics: [MetricID] = []

  init(changes: MetricChanges) {
    changesResult = changes
  }

  func changes(for metric: MetricID, committedAnchor: Data?) throws -> MetricChanges {
    requestedMetrics.append(metric)
    if isLocked {
      throw MetricChangeQueryError.databaseInaccessible
    }
    return changesResult
  }

  func unlock() {
    isLocked = false
  }
}

actor TransactionSender: HealthBridgeSending {
  enum Outcome: Sendable {
    case success
    case failure(NetworkFailure)
    case mismatchedRequestID
    case notApplied
    case zeroUpdated
  }

  private var outcomes: [Outcome]
  private let delay: Duration
  private(set) var requestIDs: [String] = []

  init(outcomes: [Outcome], delay: Duration = .zero) {
    self.outcomes = outcomes
    self.delay = delay
  }

  func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement {
    try await response(requestID: requestID)
  }

  func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement {
    try await response(requestID: requestID)
  }

  func send(
    batch: [LiveBatchEntry],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    try await response(requestID: requestID, entryCount: batch.count)
  }

  private func response(requestID: String, entryCount: Int = 1) async throws -> LiveAcknowledgement
  {
    requestIDs.append(requestID)
    if delay > .zero {
      try await Task.sleep(for: delay)
    }
    let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
    switch outcome {
    case .failure(let failure): throw failure
    case .success:
      return acknowledgement(
        requestID: requestID, applied: true, updated: 1, entryCount: entryCount)
    case .mismatchedRequestID:
      return acknowledgement(
        requestID: "live.different", applied: true, updated: 1, entryCount: entryCount)
    case .notApplied:
      return acknowledgement(
        requestID: requestID, applied: false, updated: 0, entryCount: entryCount)
    case .zeroUpdated:
      return acknowledgement(
        requestID: requestID, applied: true, updated: 0, entryCount: entryCount)
    }
  }

  private func acknowledgement(
    requestID: String,
    applied: Bool,
    updated: Int,
    entryCount: Int = 1
  ) -> LiveAcknowledgement {
    LiveAcknowledgement(
      ok: true,
      applied: applied,
      integrationVersion: "1.2.1",
      requestType: "live",
      protocolVersion: 1,
      requestID: requestID,
      receivedEntities: entryCount,
      updatedEntities: updated == 1 ? entryCount : updated,
      skippedEntities: applied ? 0 : entryCount,
      lastSyncUpdated: true,
      error: nil
    )
  }
}

actor RecordingSleeper: SyncSleeper {
  private(set) var delays: [TimeInterval] = []

  func sleep(for delay: TimeInterval) throws {
    try Task.checkCancellation()
    delays.append(delay)
  }
}

struct FixedJitterSource: JitterSource {
  func nextUnit() -> Double { 0 }
}

private enum TransactionFailure: Error {
  case checkpoint
}
