import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Medication synchronization transaction")
struct MedicationSyncCoordinatorTests {
  private let now = Date(timeIntervalSince1970: 1_788_052_900)
  private let medicationID = MedicationIdentifier.make(from: Data("fixture-medication".utf8))

  @Test("Disabled medication setting reads sends and checkpoints nothing")
  func disabled() async throws {
    let fixture = try await makeFixture(enabled: false)

    let report = await fixture.coordinator.sync(trigger: .manual)

    #expect(report.attempted == false)
    #expect(await fixture.reader.readCount == 0)
    #expect(await fixture.sender.requestIDs.isEmpty)
    #expect(try await fixture.checkpoints.load() == nil)
  }

  @Test("Commits the candidate only after an exact medication acknowledgement")
  func transaction() async throws {
    let fixture = try await makeFixture(enabled: true)

    let report = await fixture.coordinator.sync(trigger: .manual)

    #expect(report.synchronized)
    #expect(report.failure == nil)
    #expect(await fixture.sender.medicationCounts == [1])
    #expect(try await fixture.checkpoints.load() == fixture.candidate)
  }

  @Test("Count mismatch and checkpoint failure never claim success")
  func rollback() async throws {
    let mismatch = try await makeFixture(enabled: true, senderMode: .countMismatch)
    let mismatchReport = await mismatch.coordinator.sync(trigger: .manual)
    #expect(mismatchReport.failure == .protocolMismatch)
    #expect(try await mismatch.checkpoints.load() == nil)

    let failingStore = FailingMedicationCheckpointStore()
    let checkpoint = try await makeFixture(enabled: true, checkpoints: failingStore)
    let checkpointReport = await checkpoint.coordinator.sync(trigger: .manual)
    #expect(checkpointReport.failure == .checkpoint)
    #expect(checkpointReport.synchronized == false)
  }

  @Test("Exact no-change is skipped and a removed medication fails closed")
  func changes() async throws {
    let unchanged = try await makeFixture(enabled: true, hasChanges: false)
    let unchangedReport = await unchanged.coordinator.sync(trigger: .background)
    #expect(unchangedReport.skipped)
    #expect(await unchanged.sender.requestIDs.isEmpty)

    let removed = try await makeFixture(enabled: true, removedIDs: [medicationID])
    let removedReport = await removed.coordinator.sync(trigger: .manual)
    #expect(removedReport.failure == .compatibility)
    #expect(await removed.sender.requestIDs.isEmpty)
  }

  @Test("No authorized medication is a quiet skip")
  func emptyAuthorization() async throws {
    let fixture = try await makeFixture(enabled: true, concepts: [], doses: [])

    let report = await fixture.coordinator.sync(trigger: .manual)

    #expect(report.attempted)
    #expect(report.skipped)
    #expect(report.failure == nil)
    #expect(await fixture.sender.requestIDs.isEmpty)
    #expect(try await fixture.checkpoints.load() == nil)
  }

  @Test("Transient retries reuse one opaque request ID")
  func retry() async throws {
    let fixture = try await makeFixture(enabled: true, senderMode: .transientOnce)

    let report = await fixture.coordinator.sync(trigger: .shortcut)

    #expect(report.synchronized)
    let ids = await fixture.sender.requestIDs
    #expect(ids.count == 2)
    #expect(Set(ids).count == 1)
  }

  @Test("An exhausted deadline skips reading and sending")
  func deadlineExceeded() async throws {
    let fixture = try await makeFixture(enabled: true)

    let report = await fixture.coordinator.sync(
      trigger: .appRefresh,
      deadline: ExecutionDeadline(expiresAt: now.addingTimeInterval(-1))
    )

    #expect(report.failure == .deadlineExceeded)
    #expect(await fixture.reader.readCount == 0)
    #expect(await fixture.sender.requestIDs.isEmpty)
  }

  private func makeFixture(
    enabled: Bool,
    senderMode: MedicationSender.Mode = .success,
    checkpoints: any MedicationCheckpointStore = InMemoryMedicationCheckpointStore(),
    hasChanges: Bool = true,
    removedIDs: Set<String> = [],
    concepts: [MedicationConcept]? = nil,
    doses: [MedicationDose]? = nil
  ) async throws -> Fixture {
    let configuration = AppConfiguration(
      baseURL: "https://ha.example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "fixture-user",
      selectedMetrics: [.steps],
      backgroundSyncEnabled: false,
      medicationSyncEnabled: enabled
    )
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    let candidate = MedicationCheckpoint(
      anchor: Data([1, 2, 3]),
      medicationIDs: [medicationID],
      sourceFingerprint: "opaque-fingerprint"
    )
    let reader = MedicationReader(
      result: MedicationReadResult(
        concepts: concepts ?? [MedicationConcept(id: medicationID, name: "Example")],
        doses: doses ?? [
          MedicationDose(
            medicationID: medicationID,
            status: .taken,
            schedule: .scheduled,
            doseQuantity: 1,
            unit: "tablet"
          )
        ],
        candidateCheckpoint: candidate,
        hasChanges: hasChanges,
        removedMedicationIDs: removedIDs
      )
    )
    let sender = MedicationSender(mode: senderMode)
    let coordinator = MedicationSyncCoordinator(
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      reader: reader,
      sender: sender,
      checkpointStore: checkpoints,
      requestIDGenerator: RequestIDGenerator(
        uuidProvider: { UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")! }
      ),
      now: { now },
      retryPolicy: RetryPolicy(maximumAttempts: 2, baseDelay: 0, maximumDelay: 0),
      sleeper: MedicationSleeper(),
      jitterSource: MedicationJitter()
    )
    return Fixture(
      coordinator: coordinator,
      reader: reader,
      sender: sender,
      checkpoints: checkpoints,
      candidate: candidate
    )
  }

  private struct Fixture {
    let coordinator: MedicationSyncCoordinator
    let reader: MedicationReader
    let sender: MedicationSender
    let checkpoints: any MedicationCheckpointStore
    let candidate: MedicationCheckpoint
  }
}

private actor MedicationReader: MedicationReading {
  private let result: MedicationReadResult
  private(set) var readCount = 0

  init(result: MedicationReadResult) { self.result = result }
  func requestAuthorization() {}
  func read(
    committedCheckpoint: MedicationCheckpoint?,
    now: Date,
    calendar: Calendar
  ) -> MedicationReadResult {
    readCount += 1
    return result
  }
}

private actor MedicationSender: MedicationHealthBridgeSending {
  enum Mode { case success, countMismatch, transientOnce }
  private let mode: Mode
  private(set) var requestIDs: [String] = []
  private(set) var medicationCounts: [Int] = []

  init(mode: Mode) { self.mode = mode }

  func send(
    medications: MedicationPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) throws -> LiveAcknowledgement {
    requestIDs.append(requestID)
    medicationCounts.append(medications.records.count)
    if mode == .transientOnce, requestIDs.count == 1 {
      throw NetworkFailure.server(statusCode: 503)
    }
    let acknowledgement = LiveAcknowledgement(
      ok: true,
      applied: true,
      integrationVersion: "1.2.1",
      requestType: "live",
      protocolVersion: 1,
      requestID: requestID,
      receivedEntities: 1,
      updatedEntities: mode == .countMismatch ? 0 : medications.records.count,
      skippedEntities: 0,
      lastSyncUpdated: true,
      error: nil
    )
    do {
      try acknowledgement.validateMedications(
        requestID: requestID,
        medicationCount: medications.records.count
      )
    } catch {
      throw NetworkFailure.protocolMismatch
    }
    return acknowledgement
  }
}

private actor FailingMedicationCheckpointStore: MedicationCheckpointStore {
  func load() -> MedicationCheckpoint? { nil }
  func save(_ checkpoint: MedicationCheckpoint) throws { throw Failure.expected }
  func reset() {}
  private enum Failure: Error { case expected }
}

private struct MedicationSleeper: SyncSleeper {
  func sleep(for delay: TimeInterval) {}
}

private actor MedicationJitter: JitterSource {
  func nextUnit() -> Double { 0 }
}
