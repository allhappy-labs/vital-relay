import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Inbound pairing synchronization")
struct InboundSyncCoordinatorTests {
  private let now = Date(timeIntervalSince1970: 1_788_052_900)
  private let updatedAt = Date(timeIntervalSince1970: 1_788_052_801)

  @Test("Fetches normalizes saves and commits only after confirmed save")
  func successfulTransaction() async throws {
    let pairing = makePairing()
    let writer = RecordingHealthSampleWriter()
    let checkpoints = InMemoryPairingCheckpointStore()
    let coordinator = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState()],
      writer: writer,
      checkpoints: checkpoints
    )

    let report = await coordinator.sync(trigger: .manual)

    #expect(report.attemptedPairings == 1)
    #expect(report.savedPairings == 1)
    #expect(report.skippedPairings == 0)
    #expect(report.failures.isEmpty)
    let write = try #require(await writer.saved.first)
    #expect(write.destination == .bodyMass)
    #expect(write.value == 70)
    #expect(write.date == updatedAt)
    let checkpoint = try #require(try await checkpoints.checkpoint(for: pairing.id))
    #expect(checkpoint.syncIdentifier == write.syncIdentifier)
    #expect(checkpoint.syncVersion == write.syncVersion)
  }

  @Test("Skips an exact checkpoint and writes a changed state")
  func duplicatePrevention() async throws {
    let pairing = makePairing()
    let writer = RecordingHealthSampleWriter()
    let checkpoints = InMemoryPairingCheckpointStore()
    let first = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState()],
      writer: writer,
      checkpoints: checkpoints
    )
    _ = await first.sync(trigger: .manual)

    let duplicate = await first.sync(trigger: .manual)
    #expect(duplicate.savedPairings == 0)
    #expect(duplicate.skippedPairings == 1)
    #expect(await writer.saved.count == 1)

    let changed = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState(value: "71")],
      writer: writer,
      checkpoints: checkpoints
    )
    let changedReport = await changed.sync(trigger: .manual)
    #expect(changedReport.savedPairings == 1)
    #expect(await writer.saved.count == 2)
  }

  @Test("Unavailable states skip while malformed unit and bounds fail validation")
  func validationOutcomes() async throws {
    let pairing = makePairing()
    for unavailable in ["unknown", "Unavailable", "NONE"] {
      let coordinator = try await makeCoordinator(
        pairings: [pairing],
        states: [pairing.entityID: makeState(value: unavailable)]
      )
      let report = await coordinator.sync(trigger: .manual)
      #expect(report.skippedPairings == 1)
      #expect(report.failures.isEmpty)
    }

    for invalid in [makeState(unit: "lb"), makeState(value: "900")] {
      let coordinator = try await makeCoordinator(
        pairings: [pairing],
        states: [pairing.entityID: invalid]
      )
      let report = await coordinator.sync(trigger: .manual)
      #expect(report.savedPairings == 0)
      #expect(report.failures.map(\.category) == [.validation])
    }
  }

  @Test("Classifies authenticated fetch failures without exposing state")
  func networkFailure() async throws {
    let pairing = makePairing()
    let coordinator = try await makeCoordinator(
      pairings: [pairing],
      states: [:],
      fetchErrors: [pairing.entityID: NetworkFailure.unauthorized]
    )

    let report = await coordinator.sync(trigger: .manual)

    #expect(report.failures == [.init(pairingID: pairing.id, category: .unauthorized)])
    #expect(!String(describing: report).contains("sensor.body_mass"))
    #expect(!String(describing: report).contains("70"))
  }

  @Test("Classifies forbidden and missing entity responses separately")
  func authenticatedFailureClassification() async throws {
    let first = makePairing()
    let second = Pairing(
      entityID: "sensor.water",
      destination: .dietaryWater,
      sourceUnit: .millilitres,
      destinationUnit: .millilitres,
      transformation: .identity,
      isEnabled: true
    )
    let coordinator = try await makeCoordinator(
      pairings: [first, second],
      states: [:],
      fetchErrors: [first.entityID: .forbidden, second.entityID: .notFound]
    )

    let report = await coordinator.sync(trigger: .manual)

    #expect(Set(report.failures.map(\.category)) == [.forbidden, .notFound])
  }

  @Test("Save and checkpoint failures preserve the old checkpoint")
  func rollback() async throws {
    let pairing = makePairing()
    let saveFailure = RecordingHealthSampleWriter(error: TestFailure.expected)
    let checkpoints = InMemoryPairingCheckpointStore()
    let failingSave = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState()],
      writer: saveFailure,
      checkpoints: checkpoints
    )
    let saveReport = await failingSave.sync(trigger: .manual)
    #expect(saveReport.failures.map(\.category) == [.healthKit])
    #expect(try await checkpoints.checkpoint(for: pairing.id) == nil)

    let checkpointFailure = FailingPairingCheckpointStore()
    let writer = RecordingHealthSampleWriter()
    let failingCheckpoint = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState()],
      writer: writer,
      checkpoints: checkpointFailure
    )
    let checkpointReport = await failingCheckpoint.sync(trigger: .manual)
    #expect(checkpointReport.savedPairings == 0)
    #expect(checkpointReport.failures.map(\.category) == [.checkpoint])
    #expect(await writer.saved.count == 1)
  }

  @Test("Cancellation during save does not commit a checkpoint")
  func cancellationRollback() async throws {
    let pairing = makePairing()
    let writer = RecordingHealthSampleWriter(delay: .seconds(1))
    let checkpoints = InMemoryPairingCheckpointStore()
    let coordinator = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState()],
      writer: writer,
      checkpoints: checkpoints
    )

    let task = Task { await coordinator.sync(trigger: .manual) }
    try await Task.sleep(for: .milliseconds(20))
    task.cancel()
    let report = await task.value

    #expect(report.failures.map(\.category) == [.cancelled])
    #expect(await writer.saved.isEmpty)
    #expect(try await checkpoints.checkpoint(for: pairing.id) == nil)
  }

  @Test("Concurrent triggers coalesce each pairing transaction")
  func concurrentTriggers() async throws {
    let pairing = makePairing()
    let writer = RecordingHealthSampleWriter(delay: .milliseconds(50))
    let coordinator = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState()],
      writer: writer
    )

    async let first = coordinator.sync(trigger: .manual)
    async let second = coordinator.sync(trigger: .manual)
    let reports = await [first, second]

    #expect(reports.allSatisfy { $0.savedPairings == 1 })
    #expect(await writer.saved.count == 1)
  }

  @Test("Independent pairings progress when one fails")
  func independentProgress() async throws {
    let body = makePairing()
    let water = Pairing(
      entityID: "sensor.water",
      destination: .dietaryWater,
      sourceUnit: .millilitres,
      destinationUnit: .millilitres,
      transformation: .identity,
      isEnabled: true
    )
    let writer = RecordingHealthSampleWriter()
    let coordinator = try await makeCoordinator(
      pairings: [body, water],
      states: [water.entityID: makeState(entityID: water.entityID, value: "500", unit: "mL")],
      fetchErrors: [body.entityID: NetworkFailure.notFound],
      writer: writer
    )

    let report = await coordinator.sync(trigger: .manual)

    #expect(report.attemptedPairings == 2)
    #expect(report.savedPairings == 1)
    #expect(report.failures == [.init(pairingID: body.id, category: .notFound)])
  }

  @Test("An exhausted deadline fails pairings without fetching or writing")
  func deadlineExceeded() async throws {
    let pairing = makePairing()
    let writer = RecordingHealthSampleWriter()
    let coordinator = try await makeCoordinator(
      pairings: [pairing],
      states: [pairing.entityID: makeState()],
      writer: writer
    )

    let report = await coordinator.sync(
      trigger: .appRefresh,
      deadline: ExecutionDeadline(expiresAt: now.addingTimeInterval(-1))
    )

    #expect(report.savedPairings == 0)
    #expect(report.failures == [.init(pairingID: pairing.id, category: .deadlineExceeded)])
    #expect(await writer.saved.isEmpty)
  }

  private func makeCoordinator(
    pairings: [Pairing],
    states: [String: HomeAssistantState],
    fetchErrors: [String: NetworkFailure] = [:],
    writer: RecordingHealthSampleWriter = RecordingHealthSampleWriter(),
    checkpoints: any PairingCheckpointStore = InMemoryPairingCheckpointStore()
  ) async throws -> InboundSyncCoordinator {
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-access-token", for: .accessToken)
    return InboundSyncCoordinator(
      pairingStore: try InMemoryPairingStore(pairings: pairings),
      configurationStore: InMemoryConfigurationStore(
        configuration: AppConfiguration(
          baseURL: "https://ha.example.invalid",
          allowsConfirmedLocalHTTP: false,
          healthBridgeUserID: "fixture-user",
          selectedMetrics: [.steps],
          backgroundSyncEnabled: false
        )
      ),
      credentialStore: credentials,
      stateFetcher: StubStateFetcher(states: states, errors: fetchErrors),
      writer: writer,
      checkpointStore: checkpoints,
      now: { now }
    )
  }

  private func makePairing() -> Pairing {
    Pairing(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
      entityID: "sensor.body_mass",
      destination: .bodyMass,
      sourceUnit: .kilograms,
      destinationUnit: .kilograms,
      transformation: .identity,
      isEnabled: true
    )
  }

  private func makeState(
    entityID: String = "sensor.body_mass",
    value: String = "70",
    unit: String? = "kg"
  ) -> HomeAssistantState {
    HomeAssistantState(
      entityID: entityID,
      state: value,
      lastChanged: updatedAt,
      lastUpdated: updatedAt,
      attributes: .init(unitOfMeasurement: unit)
    )
  }

  private enum TestFailure: Error { case expected }
}

private actor StubStateFetcher: HomeAssistantStateFetching {
  let states: [String: HomeAssistantState]
  let errors: [String: NetworkFailure]

  init(states: [String: HomeAssistantState], errors: [String: NetworkFailure]) {
    self.states = states
    self.errors = errors
  }

  func fetchState(
    entityID: String,
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) throws -> HomeAssistantState {
    if let error = errors[entityID] { throw error }
    guard let state = states[entityID] else { throw NetworkFailure.notFound }
    return state
  }
}

private actor RecordingHealthSampleWriter: HealthSampleWriting {
  let error: (any Error)?
  let delay: Duration
  private(set) var saved: [HealthSampleWrite] = []

  init(error: (any Error)? = nil, delay: Duration = .zero) {
    self.error = error
    self.delay = delay
  }

  func requestWriteAuthorization(for destinations: Set<HealthObjectTypeID>) {}

  func save(_ sample: HealthSampleWrite) async throws {
    if delay > .zero { try await Task.sleep(for: delay) }
    try Task.checkCancellation()
    if let error { throw error }
    saved.append(sample)
  }
}

private actor FailingPairingCheckpointStore: PairingCheckpointStore {
  func checkpoint(for pairingID: UUID) -> PairingCheckpoint? { nil }
  func commit(_ checkpoint: PairingCheckpoint) throws { throw Failure.expected }
  func reset(pairingID: UUID) {}
  func resetAll() {}

  private enum Failure: Error { case expected }
}
