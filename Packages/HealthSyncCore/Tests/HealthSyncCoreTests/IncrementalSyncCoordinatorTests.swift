import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Incremental retry execution")
struct IncrementalSyncCoordinatorTests {
  private let now = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Retries transient failures with one stable request ID")
  func stableRetry() async throws {
    let sender = TransactionSender(
      outcomes: [
        .failure(.timeout),
        .failure(.server(statusCode: 503)),
        .success,
      ]
    )
    let sleeper = RecordingSleeper()
    let coordinator = try await makeCoordinator(sender: sender, sleeper: sleeper)

    let report = await coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.synchronizedMetrics == 1)
    let requestIDs = await sender.requestIDs
    #expect(requestIDs.count == 3)
    #expect(Set(requestIDs).count == 1)
    #expect(await sleeper.delays == [1, 2])
  }

  @Test("A short execution deadline prevents retry sleep and anchor commit")
  func deadline() async throws {
    let sender = TransactionSender(outcomes: [.failure(.timeout), .success])
    let sleeper = RecordingSleeper()
    let store = TransactionCheckpointStore(anchors: [.steps: Data([1])])
    let coordinator = try await makeCoordinator(
      sender: sender,
      sleeper: sleeper,
      store: store,
      deadline: ExecutionDeadline(expiresAt: now.addingTimeInterval(0.5))
    )

    let report = await coordinator.sync(trigger: .background, metrics: [.steps])

    #expect(report.failures == [.init(metricID: .steps, category: .deadlineExceeded)])
    #expect(await sender.requestIDs.count == 1)
    #expect(await sleeper.delays.isEmpty)
    #expect(await store.anchor(for: .steps) == Data([1]))
  }

  @Test("Concurrent incremental triggers coalesce the per-metric transaction")
  func coalescing() async throws {
    let sender = TransactionSender(outcomes: [.success], delay: .milliseconds(50))
    let coordinator = try await makeCoordinator(sender: sender)

    async let first = coordinator.sync(trigger: .manual, metrics: [.steps])
    async let second = coordinator.sync(trigger: .background, metrics: [.steps])
    let reports = await [first, second]

    #expect(reports[0] == reports[1])
    #expect(await sender.requestIDs.count == 1)
  }

  private func makeCoordinator(
    sender: TransactionSender,
    sleeper: RecordingSleeper = RecordingSleeper(),
    store: TransactionCheckpointStore? = nil,
    deadline: ExecutionDeadline? = nil
  ) async throws -> SyncCoordinator {
    let query = FakeMetricQueryService()
    await query.configureReading(
      MetricReading(metricID: .steps, timestamp: now, value: 8_421),
      for: .steps
    )
    let configuration = AppConfiguration(
      baseURL: "https://ha.example.com",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps],
      backgroundSyncEnabled: true
    )
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    return SyncCoordinator(
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      metricQuery: query,
      webhookSender: sender,
      calendar: Calendar(identifier: .gregorian),
      now: { now },
      checkpointStore: store ?? TransactionCheckpointStore(anchors: [.steps: Data([1])]),
      changeQuery: TransactionChangeQuery(
        changes: MetricChanges(
          addedSampleIDs: [UUID()],
          deletedSampleIDs: [],
          candidateAnchor: Data([2])
        )
      ),
      sleeper: sleeper,
      jitterSource: FixedJitterSource(),
      deadline: deadline
    )
  }
}
