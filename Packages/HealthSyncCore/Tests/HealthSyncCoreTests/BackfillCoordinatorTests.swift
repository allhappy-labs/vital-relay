import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Experimental backfill coordinator")
struct BackfillCoordinatorTests {
  @Test func revocationAfterFirstBatchRetainsAcknowledgedBoundary() async throws {
    let checkpoints = RecordingBackfillCheckpointStore()
    let access = ImportCheckpointAccess {
      await checkpoints.load().checkpoints.isEmpty ? .unlocked : .locked
    }
    let points = (0...721).map {
      BackfillPoint(timestamp: now.addingTimeInterval(Double($0 - 721)), value: Double($0))
    }
    let fixture = try await makeCoordinator(
      enabled: true, checkpoints: checkpoints, points: points, access: access)
    let report = await fixture.coordinator.importHistory(
      metrics: [.steps], requestedStart: now.addingTimeInterval(-3600))
    #expect(report.requiresPurchase)
    #expect(await fixture.sender.requests.count == 1)
    #expect(
      await checkpoints.load().checkpoints[.steps]?.committedThrough == points[719].timestamp)
    let acknowledgedState = try #require(await checkpoints.savedStates.first)
    #expect(acknowledgedState.capability == .available(protocolVersion: 1))
    #expect(await checkpoints.load() == acknowledgedState)
    #expect(await checkpoints.savedStates.count == 1)
    #expect(report.capability == acknowledgedState.capability)
  }
  @Test func lockedImportLeavesCheckpointBytesUnchanged() async throws {
    let fixture = try await makeCoordinator(enabled: true, access: ImportPaidAccessFixture(.locked))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let before = try encoder.encode(await fixture.checkpoints.load())
    let report = await fixture.coordinator.importHistory(
      metrics: [.steps], requestedStart: now.addingTimeInterval(-3600))
    #expect(report.committedPoints == 0)
    #expect(report.requiresPurchase)
    #expect(await fixture.live.calls.isEmpty)
    #expect(await fixture.query.calls == 0)
    #expect(await fixture.sender.requests.isEmpty)
    #expect(try encoder.encode(await fixture.checkpoints.load()) == before)
  }
  private let now = Date(timeIntervalSince1970: 1_788_052_900)

  @Test("Disabled setting performs no live query or webhook work")
  func disabled() async throws {
    let fixture = try await makeCoordinator(enabled: false)

    let report = await fixture.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )

    #expect(report.capability == .disabledByUser)
    #expect(await fixture.live.calls.isEmpty)
    #expect(await fixture.query.calls == 0)
    #expect(await fixture.sender.requests.isEmpty)
  }

  @Test("Creates live entity then commits only a committed backfill window")
  func successfulTransaction() async throws {
    let fixture = try await makeCoordinator(enabled: true)

    let report = await fixture.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )

    #expect(report.committedMetrics == 1)
    #expect(report.committedPoints == 2)
    #expect(report.capability == .available(protocolVersion: 1))
    #expect(await fixture.live.calls == [[.steps]])
    let state = try await fixture.checkpoints.load()
    #expect(state.checkpoints[.steps]?.committedThrough == now.addingTimeInterval(-600))
    let requests = await fixture.sender.requests
    #expect(requests.count == 1)
    #expect(requests[0].data["steps"]?.count == 2)
  }

  @Test("A clean no-change live prerequisite still imports history")
  func skippedLivePrerequisite() async throws {
    let fixture = try await makeCoordinator(enabled: true, liveMode: .skipped)

    let report = await fixture.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )

    #expect(report.committedMetrics == 1)
    #expect(report.committedPoints == 2)
    #expect(report.failures.isEmpty)
    #expect(await fixture.query.calls == 1)
    #expect(await fixture.sender.requests.count == 1)
    #expect(try await fixture.checkpoints.load().checkpoints[.steps] != nil)
  }

  @Test("A metric without eligible history is skipped without a failure")
  func noEligibleHistory() async throws {
    let insufficientHistories: [[BackfillPoint]] = [
      [],
      [.init(timestamp: now, value: 8_421)],
    ]

    for points in insufficientHistories {
      let fixture = try await makeCoordinator(enabled: true, points: points)

      let report = await fixture.coordinator.importHistory(
        metrics: [.steps],
        requestedStart: now.addingTimeInterval(-3_600)
      )

      #expect(report.committedMetrics == 0)
      #expect(report.skippedMetrics == 1)
      #expect(report.failures.isEmpty)
      #expect(await fixture.sender.requests.isEmpty)
      #expect(try await fixture.checkpoints.load().checkpoints.isEmpty)
    }
  }

  @Test("A partial multi-chunk commit advances only through the accepted history")
  func partialChunkCheckpoint() async throws {
    let points = (0...721).map { offset in
      BackfillPoint(
        timestamp: now.addingTimeInterval(Double(offset - 721)),
        value: Double(offset)
      )
    }
    let fixture = try await makeCoordinator(
      enabled: true,
      outcomes: [
        .success(acknowledgement()),
        .failure(BackfillClientError.invalidBackfill),
      ],
      points: points
    )

    let report = await fixture.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )

    #expect(report.committedMetrics == 0)
    #expect(report.failures.map(\.category) == [.validation])
    let requests = await fixture.sender.requests
    #expect(requests.count == 2)
    #expect(requests[0].data["steps"]?.count == 721)
    #expect(requests[1].data["steps"]?.count == 2)
    let checkpoint = try #require(try await fixture.checkpoints.load().checkpoints[.steps])
    #expect(checkpoint.committedThrough == points[719].timestamp)
    #expect(checkpoint.committedThrough < points.last!.timestamp)
  }

  @Test("A retry resumes after the committed historical boundary without recreating live state")
  func resumesFromCheckpoint() async throws {
    let committedThrough = now.addingTimeInterval(-1_200)
    let checkpoints = InMemoryBackfillCheckpointStore(
      state: BackfillState(
        capability: .available(protocolVersion: 1),
        checkpoints: [
          .steps: BackfillCheckpoint(
            metricID: .steps,
            windowStart: now.addingTimeInterval(-3_600),
            committedThrough: committedThrough,
            requestID: "backfill.01234567"
          )
        ]
      )
    )
    let points = [
      BackfillPoint(timestamp: committedThrough, value: 6_000),
      BackfillPoint(timestamp: now.addingTimeInterval(-600), value: 7_000),
      BackfillPoint(timestamp: now, value: 8_421),
    ]
    let fixture = try await makeCoordinator(
      enabled: true,
      checkpoints: checkpoints,
      points: points
    )

    let report = await fixture.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )

    #expect(report.committedMetrics == 1)
    #expect(await fixture.live.calls.isEmpty)
    #expect(await fixture.query.intervals == [DateInterval(start: committedThrough, end: now)])
    let requestPoints = try #require(await fixture.sender.requests.first?.data["steps"])
    #expect(requestPoints == Array(points.suffix(2)))
    #expect(
      try await fixture.checkpoints.load().checkpoints[.steps]?.committedThrough
        == now.addingTimeInterval(-600)
    )
  }

  @Test("Incompatible recorder disables only backfill and leaves live callable")
  func incompatibleRecorder() async throws {
    let fixture = try await makeCoordinator(
      enabled: true,
      outcomes: [.failure(BackfillClientError.unsupportedRecorder)]
    )

    let report = await fixture.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )
    _ = await fixture.live.sync(trigger: .manual, metrics: [.bodyMass])

    #expect(report.capability == .incompatible(reason: .unsupportedRecorder))
    #expect(report.failures.map(\.category) == [.compatibility])
    #expect(await fixture.live.calls == [[.steps], [.bodyMass]])
    #expect(try await fixture.checkpoints.load().checkpoints.isEmpty)
  }

  @Test("Transient retry uses the same request ID and invalid request does not retry")
  func retryPolicy() async throws {
    let transient = try await makeCoordinator(
      enabled: true,
      outcomes: [
        .failure(BackfillClientError.recorderUnavailable),
        .success(acknowledgement()),
      ]
    )
    let report = await transient.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )
    let identifiers = await transient.sender.requests.map(\.requestID)
    #expect(report.committedMetrics == 1)
    #expect(identifiers.count == 2)
    #expect(Set(identifiers).count == 1)

    let invalid = try await makeCoordinator(
      enabled: true,
      outcomes: [.failure(BackfillClientError.invalidBackfill)]
    )
    let invalidReport = await invalid.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )
    #expect(invalidReport.failures.map(\.category) == [.validation])
    #expect(await invalid.sender.requests.count == 1)
  }

  @Test("Cancellation and checkpoint failures never claim a commit")
  func rollback() async throws {
    let checkpoints = FailingBackfillCheckpointStore()
    let fixture = try await makeCoordinator(enabled: true, checkpoints: checkpoints)

    let report = await fixture.coordinator.importHistory(
      metrics: [.steps],
      requestedStart: now.addingTimeInterval(-3_600)
    )

    #expect(report.committedMetrics == 0)
    #expect(report.failures.map(\.category) == [.checkpoint])

    let cancelledFixture = try await makeCoordinator(enabled: true)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await cancelledFixture.coordinator.importHistory(
        metrics: [.steps],
        requestedStart: now.addingTimeInterval(-3_600)
      )
    }
    let cancelled = await task.value
    #expect(cancelled.committedMetrics == 0)
    #expect(cancelled.failures.map(\.category) == [.cancelled])
    #expect(await cancelledFixture.sender.requests.isEmpty)
  }

  private func makeCoordinator(
    enabled: Bool,
    outcomes: [Result<BackfillAcknowledgement, any Error>] = [],
    checkpoints: any BackfillCheckpointStore = InMemoryBackfillCheckpointStore(),
    points: [BackfillPoint]? = nil,
    liveMode: BackfillLiveCoordinator.Mode = .synchronized,
    access: any PaidFeatureAccessing = ImportPaidAccessFixture()
  ) async throws -> Fixture {
    var configuration = AppConfiguration(
      baseURL: "https://ha.example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "fixture-user",
      selectedMetrics: [.steps],
      backgroundSyncEnabled: false
    )
    configuration.experimentalBackfillEnabled = enabled
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    let live = BackfillLiveCoordinator(now: now, mode: liveMode)
    let query = BackfillPointQuery(now: now, points: points)
    let sender = BackfillSender(outcomes: outcomes, fallback: acknowledgement())
    let coordinator = BackfillCoordinator(
      access: access,
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      liveCoordinator: live,
      pointQuery: query,
      sender: sender,
      checkpointStore: checkpoints,
      requestIDGenerator: RequestIDGenerator(
        uuidProvider: { UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")! }
      ),
      now: { now },
      retryPolicy: RetryPolicy(maximumAttempts: 2, baseDelay: 0, maximumDelay: 0),
      sleeper: BackfillImmediateSleeper(),
      jitterSource: BackfillZeroJitter()
    )
    return Fixture(
      coordinator: coordinator,
      live: live,
      query: query,
      sender: sender,
      checkpoints: checkpoints
    )
  }

  private func acknowledgement() -> BackfillAcknowledgement {
    BackfillAcknowledgement(
      ok: true,
      committed: true,
      protocolVersion: 1,
      requestID: "backfill.01234567-89ab-cdef-0123-456789abcdef",
      recorderSchema: 53,
      database: "sqlite",
      received: 2,
      inserted: 2,
      skipped: 0,
      entities: 1,
      statisticsPolicy: "history_only"
    )
  }

  private struct Fixture {
    let coordinator: BackfillCoordinator
    let live: BackfillLiveCoordinator
    let query: BackfillPointQuery
    let sender: BackfillSender
    let checkpoints: any BackfillCheckpointStore
  }
}

private actor BackfillLiveCoordinator: SyncCoordinating {
  enum Mode: Sendable {
    case synchronized
    case skipped
  }

  private let now: Date
  private let mode: Mode
  private(set) var calls: [Set<MetricID>] = []

  init(now: Date, mode: Mode = .synchronized) {
    self.now = now
    self.mode = mode
  }

  func sync(trigger: SyncTrigger, metrics: Set<MetricID>?) -> SyncReport {
    calls.append(metrics ?? [])
    let metricCount = metrics?.count ?? 0
    return SyncReport(
      trigger: trigger,
      attemptedMetrics: metricCount,
      synchronizedMetrics: mode == .synchronized ? metricCount : 0,
      skippedMetrics: mode == .skipped ? metricCount : 0,
      failures: [],
      startedAt: now,
      finishedAt: now
    )
  }
}

private actor BackfillPointQuery: BackfillPointQuerying {
  private let now: Date
  private let points: [BackfillPoint]?
  private(set) var calls = 0
  private(set) var intervals: [DateInterval] = []

  init(now: Date, points: [BackfillPoint]? = nil) {
    self.now = now
    self.points = points
  }

  func points(
    for definition: MetricDefinition,
    interval: DateInterval,
    calendar: Calendar
  ) -> [BackfillPoint] {
    calls += 1
    intervals.append(interval)
    return points ?? [
      .init(timestamp: now.addingTimeInterval(-600), value: 7_000),
      .init(timestamp: now, value: 8_421),
    ]
  }
}

private actor BackfillSender: HealthBridgeBackfillSending {
  private var outcomes: [Result<BackfillAcknowledgement, any Error>]
  private let fallback: BackfillAcknowledgement
  private(set) var requests: [BackfillRequest] = []

  init(
    outcomes: [Result<BackfillAcknowledgement, any Error>],
    fallback: BackfillAcknowledgement
  ) {
    self.outcomes = outcomes
    self.fallback = fallback
  }

  func send(
    _ request: BackfillRequest,
    baseURL: NormalizedBaseURL
  ) throws -> BackfillAcknowledgement {
    requests.append(request)
    guard !outcomes.isEmpty else { return matching(fallback, requestID: request.requestID) }
    let outcome = outcomes.removeFirst()
    switch outcome {
    case .success(let acknowledgement):
      return matching(acknowledgement, requestID: request.requestID)
    case .failure(let error):
      throw error
    }
  }

  private func matching(
    _ acknowledgement: BackfillAcknowledgement,
    requestID: String
  ) -> BackfillAcknowledgement {
    BackfillAcknowledgement(
      ok: acknowledgement.ok,
      committed: acknowledgement.committed,
      protocolVersion: acknowledgement.protocolVersion,
      requestID: requestID,
      recorderSchema: acknowledgement.recorderSchema,
      database: acknowledgement.database,
      received: acknowledgement.received,
      inserted: acknowledgement.inserted,
      skipped: acknowledgement.skipped,
      entities: acknowledgement.entities,
      statisticsPolicy: acknowledgement.statisticsPolicy
    )
  }
}

private actor RecordingBackfillCheckpointStore: BackfillCheckpointStore {
  private var state = BackfillState()
  private(set) var savedStates: [BackfillState] = []
  func load() -> BackfillState { state }
  func save(_ state: BackfillState) {
    self.state = state
    savedStates.append(state)
  }
  func reset() { state = BackfillState() }
}

private actor FailingBackfillCheckpointStore: BackfillCheckpointStore {
  func load() -> BackfillState { BackfillState() }
  func save(_ state: BackfillState) throws { throw Failure.expected }
  func reset() {}
  private enum Failure: Error { case expected }
}

private struct BackfillImmediateSleeper: SyncSleeper {
  func sleep(for delay: TimeInterval) {}
}

private actor BackfillZeroJitter: JitterSource {
  func nextUnit() -> Double { 0 }
}
