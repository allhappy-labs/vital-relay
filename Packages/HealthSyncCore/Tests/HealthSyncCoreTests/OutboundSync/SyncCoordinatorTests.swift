import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Manual sync coordinator")
struct SyncCoordinatorTests {
  private let fixedDate = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Synchronizes all three metrics in one batched request")
  func successfulMetrics() async throws {
    let query = try await populatedQuery()
    let sender = FakeHealthBridgeSender()
    let coordinator = try await makeCoordinator(query: query, sender: sender)

    let report = await coordinator.sync(
      trigger: .manual,
      metrics: [.steps, .bodyMass, .restingHeartRate]
    )

    #expect(report.attemptedMetrics == 3)
    #expect(report.synchronizedMetrics == 3)
    #expect(report.skippedMetrics == 0)
    #expect(report.failures.isEmpty)
    #expect(report.startedAt == fixedDate)
    #expect(report.finishedAt == fixedDate)
    let calls = await sender.calls
    #expect(calls.count == 3)
    #expect(Set(calls.map(\.metricID)) == [.steps, .bodyMass, .restingHeartRate])
    #expect(Set(calls.map(\.requestID)).count == 1)
    #expect(await sender.batchSizes == [3])
    #expect(report.requestCount == 1)
  }

  @Test("Missing HealthKit data is skipped without claiming success")
  func emptyMetricIsSkipped() async throws {
    let query = try await populatedQuery()
    await query.setReading(nil, for: .bodyMass)
    let sender = FakeHealthBridgeSender()
    let coordinator = try await makeCoordinator(query: query, sender: sender)

    let report = await coordinator.sync(
      trigger: .manual,
      metrics: [.steps, .bodyMass, .restingHeartRate]
    )

    #expect(report.synchronizedMetrics == 2)
    #expect(report.skippedMetrics == 1)
    #expect(report.failures.isEmpty)
    #expect(await sender.calls.count == 2)
  }

  @Test("Synchronizes the latest workout through the special payload path")
  func workout() async throws {
    let query = FakeMetricQueryService()
    await query.setWorkout(
      WorkoutSummary(
        activityName: "Running",
        start: fixedDate.addingTimeInterval(-1_800),
        end: fixedDate,
        durationSeconds: 1_800
      )
    )
    let sender = FakeHealthBridgeSender()
    let coordinator = try await makeCoordinator(query: query, sender: sender)

    let report = await coordinator.sync(trigger: .manual, metrics: [.lastAppleWorkout])

    #expect(report.synchronizedMetrics == 1)
    #expect(report.failures.isEmpty)
    #expect(await sender.calls.map(\.metricID) == [.lastAppleWorkout])
  }

  @Test(arguments: [FakeHealthBridgeSender.Mode.mismatchedRequestID, .noEntitiesApplied])
  func invalidAcknowledgementFails(mode: FakeHealthBridgeSender.Mode) async throws {
    let query = FakeMetricQueryService()
    await query.setReading(
      MetricReading(metricID: .steps, timestamp: fixedDate, value: 1),
      for: .steps
    )
    let sender = FakeHealthBridgeSender(mode: mode)
    let coordinator = try await makeCoordinator(query: query, sender: sender)

    let report = await coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.synchronizedMetrics == 0)
    #expect(report.failures == [.init(metricID: .steps, category: .protocolMismatch)])
  }

  @Test("Concurrent calls coalesce into one synchronization")
  func concurrentCallsCoalesce() async throws {
    let query = try await populatedQuery()
    let sender = FakeHealthBridgeSender(delay: .milliseconds(50))
    let coordinator = try await makeCoordinator(query: query, sender: sender)

    async let first = coordinator.sync(trigger: .manual, metrics: [.steps, .bodyMass])
    async let second = coordinator.sync(trigger: .manual, metrics: [.steps, .bodyMass])
    let reports = await [first, second]

    #expect(reports[0] == reports[1])
    #expect(await sender.calls.count == 2)
  }

  @Test("Cancellation stops work and remains privacy safe")
  func cancellation() async throws {
    let query = try await populatedQuery()
    let sender = FakeHealthBridgeSender(delay: .seconds(1))
    let coordinator = try await makeCoordinator(query: query, sender: sender)
    let task = Task {
      await coordinator.sync(trigger: .manual, metrics: [.steps, .bodyMass])
    }

    await Task.yield()
    task.cancel()
    let report = await task.value

    #expect(report.synchronizedMetrics == 0)
    #expect(report.failures.contains { $0.category == .cancelled })
  }

  @Test("Report contains no health values or credentials")
  func reportIsPrivacySafe() async throws {
    let query = try await populatedQuery()
    let coordinator = try await makeCoordinator(
      query: query,
      sender: FakeHealthBridgeSender()
    )
    let report = await coordinator.sync(trigger: .manual, metrics: [.steps])

    let data = try JSONEncoder().encode(report)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.contains("8421"))
    #expect(!text.contains("fixture-webhook-secret"))
    #expect(!text.contains("ha.example.com"))
    #expect(!text.contains("\"value\""))
  }

  @Test("Records privacy-safe attempt and terminal status")
  func recordsStatus() async throws {
    let query = try await populatedQuery()
    let statusStore = InMemorySyncStatusStore()
    let coordinator = try await makeCoordinator(
      query: query,
      sender: FakeHealthBridgeSender(),
      statusStore: statusStore
    )

    let report = await coordinator.sync(trigger: .background, metrics: [.steps])

    let snapshot = await statusStore.snapshot()
    #expect(snapshot.lastAttemptedAt == fixedDate)
    #expect(snapshot.lastSuccessfulAt == fixedDate)
    #expect(snapshot.recentEvents == [SyncStatusEvent(report: report)])
  }

  @Test("Status persistence failure is surfaced after successful delivery")
  func statusFailure() async throws {
    let query = try await populatedQuery()
    let coordinator = try await makeCoordinator(
      query: query,
      sender: FakeHealthBridgeSender(),
      statusStore: FailingSyncStatusStore()
    )

    let report = await coordinator.sync(trigger: .manual, metrics: [.steps])

    #expect(report.synchronizedMetrics == 1)
    #expect(report.failures == [.init(metricID: nil, category: .checkpoint)])
  }

  @Test("Full sync merges an enabled medication result into the shared report")
  func fullSyncIncludesMedication() async throws {
    let medicationCoordinator = FakeMedicationSyncCoordinator(
      report: MedicationSyncReport(
        attempted: true,
        synchronized: true,
        skipped: false,
        failure: nil
      )
    )
    let coordinator = try await makeCoordinator(
      query: populatedQuery(),
      sender: FakeHealthBridgeSender(),
      medicationCoordinator: medicationCoordinator,
      medicationEnabled: true
    )

    let report = await coordinator.sync(trigger: .shortcut, metrics: nil)

    #expect(report.attemptedMetrics == 4)
    #expect(report.synchronizedMetrics == 4)
    #expect(report.skippedMetrics == 0)
    #expect(report.failures.isEmpty)
    #expect(await medicationCoordinator.triggers == [.shortcut])
  }

  @Test("Medication failure is privacy-safe and does not claim success")
  func medicationFailure() async throws {
    let medicationCoordinator = FakeMedicationSyncCoordinator(
      report: MedicationSyncReport(
        attempted: true,
        synchronized: false,
        skipped: false,
        failure: .compatibility
      )
    )
    let coordinator = try await makeCoordinator(
      query: populatedQuery(),
      sender: FakeHealthBridgeSender(),
      medicationCoordinator: medicationCoordinator,
      medicationEnabled: true
    )

    let report = await coordinator.sync(trigger: .manual, metrics: nil)

    #expect(report.attemptedMetrics == 4)
    #expect(report.synchronizedMetrics == 3)
    #expect(report.failures == [.init(metricID: nil, category: .compatibility)])
  }

  @Test("Metric-scoped observer sync does not run medication synchronization")
  func scopedSyncExcludesMedication() async throws {
    let medicationCoordinator = FakeMedicationSyncCoordinator(
      report: MedicationSyncReport(
        attempted: true,
        synchronized: true,
        skipped: false,
        failure: nil
      )
    )
    let coordinator = try await makeCoordinator(
      query: populatedQuery(),
      sender: FakeHealthBridgeSender(),
      medicationCoordinator: medicationCoordinator,
      medicationEnabled: true
    )

    let report = await coordinator.sync(trigger: .background, metrics: [.steps])

    #expect(report.attemptedMetrics == 1)
    #expect(report.synchronizedMetrics == 1)
    #expect(await medicationCoordinator.triggers.isEmpty)
  }

  @Test("A run that includes medications synchronizes them alongside a metric set")
  func medicationFlagDrivesMedicationSync() async throws {
    let medicationCoordinator = FakeMedicationSyncCoordinator(
      report: MedicationSyncReport(
        attempted: true,
        synchronized: true,
        skipped: false,
        failure: nil
      )
    )
    let coordinator = try await makeCoordinator(
      query: populatedQuery(),
      sender: FakeHealthBridgeSender(),
      medicationCoordinator: medicationCoordinator,
      medicationEnabled: true
    )

    let report = await coordinator.sync(
      trigger: .healthKitObserver,
      metrics: [.steps],
      deadline: nil,
      includesMedications: true,
      lastWindowTouchAt: [:]
    )

    #expect(report.attemptedMetrics == 2)
    #expect(report.synchronizedMetrics == 2)
    #expect(report.failures.isEmpty)
    #expect(await medicationCoordinator.triggers == [.healthKitObserver])
  }

  @Test("A run that excludes medications leaves them untouched")
  func medicationFlagSuppressesMedicationSync() async throws {
    let medicationCoordinator = FakeMedicationSyncCoordinator(
      report: MedicationSyncReport(
        attempted: true,
        synchronized: true,
        skipped: false,
        failure: nil
      )
    )
    let coordinator = try await makeCoordinator(
      query: populatedQuery(),
      sender: FakeHealthBridgeSender(),
      medicationCoordinator: medicationCoordinator,
      medicationEnabled: true
    )

    let report = await coordinator.sync(
      trigger: .healthKitObserver,
      metrics: [.steps],
      deadline: nil,
      includesMedications: false,
      lastWindowTouchAt: [:]
    )

    #expect(report.attemptedMetrics == 1)
    #expect(report.synchronizedMetrics == 1)
    #expect(await medicationCoordinator.triggers.isEmpty)
  }

  private func populatedQuery() async throws -> FakeMetricQueryService {
    let query = FakeMetricQueryService()
    await query.setReading(
      MetricReading(metricID: .steps, timestamp: fixedDate, value: 8_421),
      for: .steps
    )
    await query.setReading(
      MetricReading(metricID: .bodyMass, timestamp: fixedDate, value: 80),
      for: .bodyMass
    )
    await query.setReading(
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
    let configuration = AppConfiguration(
      baseURL: "https://ha.example.com",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "oleh",
      selectedMetrics: [.steps, .bodyMass, .restingHeartRate],
      backgroundSyncEnabled: false,
      medicationSyncEnabled: medicationEnabled
    )
    let configurationStore = InMemoryConfigurationStore(configuration: configuration)
    let credentialStore = InMemoryCredentialStore()
    try await credentialStore.write("fixture-webhook-secret", for: .webhookSecret)

    return SyncCoordinator(
      configurationStore: configurationStore,
      credentialStore: credentialStore,
      metricQuery: query,
      webhookSender: sender,
      calendar: Calendar(identifier: .gregorian),
      now: { fixedDate },
      statusStore: statusStore,
      medicationSyncCoordinator: medicationCoordinator
    )
  }
}

actor FakeMedicationSyncCoordinator: MedicationSynchronizing {
  let report: MedicationSyncReport
  private(set) var triggers: [SyncTrigger] = []

  init(report: MedicationSyncReport) {
    self.report = report
  }

  func sync(trigger: SyncTrigger) -> MedicationSyncReport {
    triggers.append(trigger)
    return report
  }
}

private actor FailingSyncStatusStore: SyncStatusStore {
  func snapshot() throws -> SyncStatusSnapshot { throw Failure.expected }
  func recordAttempt(trigger: SyncTrigger, at: Date) throws { throw Failure.expected }
  func record(report: SyncReport) throws { throw Failure.expected }
  func record(report: BidirectionalSyncReport) throws { throw Failure.expected }
  func recordInterruptedAttemptIfNeeded() throws -> SyncStatusEvent? { throw Failure.expected }
  func recordThrottledWake() throws { throw Failure.expected }
  func setRegistration(_ state: BackgroundRegistrationState, for metric: MetricID) throws {
    throw Failure.expected
  }
  func reset() throws { throw Failure.expected }

  private enum Failure: Error { case expected }
}

actor FakeHealthBridgeSender: HealthBridgeSending {
  enum Mode: Sendable {
    case success
    case mismatchedRequestID
    case noEntitiesApplied
  }

  struct Call: Sendable {
    let metricID: MetricID
    let requestID: String
  }

  let mode: Mode
  let delay: Duration
  private(set) var calls: [Call] = []
  private(set) var batchSizes: [Int] = []

  init(mode: Mode = .success, delay: Duration = .zero) {
    self.mode = mode
    self.delay = delay
  }

  func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement {
    if delay > .zero {
      try await Task.sleep(for: delay)
    }
    calls.append(Call(metricID: reading.metricID, requestID: requestID))

    switch mode {
    case .success:
      return acknowledgement(requestID: requestID, applied: true)
    case .mismatchedRequestID:
      return acknowledgement(requestID: "live.different", applied: true)
    case .noEntitiesApplied:
      return acknowledgement(requestID: requestID, applied: false)
    }
  }

  func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement {
    if delay > .zero {
      try await Task.sleep(for: delay)
    }
    calls.append(Call(metricID: .lastAppleWorkout, requestID: requestID))
    switch mode {
    case .success:
      return acknowledgement(requestID: requestID, applied: true)
    case .mismatchedRequestID:
      return acknowledgement(requestID: "live.different", applied: true)
    case .noEntitiesApplied:
      return acknowledgement(requestID: requestID, applied: false)
    }
  }

  func send(
    batch: [LiveBatchEntry],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    if delay > .zero {
      try await Task.sleep(for: delay)
    }
    batchSizes.append(batch.count)
    for entry in batch {
      let metricID: MetricID =
        switch entry {
        case .reading(let reading): reading.metricID
        case .workout: .lastAppleWorkout
        }
      calls.append(Call(metricID: metricID, requestID: requestID))
    }
    let applied = mode == .success
    return LiveAcknowledgement(
      ok: applied,
      applied: applied,
      integrationVersion: "1.2.1",
      requestType: "live",
      protocolVersion: 1,
      requestID: mode == .mismatchedRequestID ? "live.different" : requestID,
      receivedEntities: batch.count,
      updatedEntities: applied ? batch.count : 0,
      skippedEntities: applied ? 0 : batch.count,
      lastSyncUpdated: true,
      error: applied ? nil : "no_entities_applied"
    )
  }

  private func acknowledgement(requestID: String, applied: Bool) -> LiveAcknowledgement {
    LiveAcknowledgement(
      ok: applied,
      applied: applied,
      integrationVersion: "1.2.1",
      requestType: "live",
      protocolVersion: 1,
      requestID: requestID,
      receivedEntities: 1,
      updatedEntities: applied ? 1 : 0,
      skippedEntities: applied ? 0 : 1,
      lastSyncUpdated: true,
      error: applied ? nil : "no_entities_applied"
    )
  }
}

extension FakeMetricQueryService {
  fileprivate func setReading(_ reading: MetricReading?, for metricID: MetricID) {
    readings[metricID] = reading
  }
}
