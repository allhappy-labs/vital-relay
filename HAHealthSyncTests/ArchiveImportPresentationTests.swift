import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class ArchiveImportPresentationTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_700_000_000)

  func testPendingApprovalBlocksImportAndShowsFingerprintWithoutValues() async throws {
    let coordinator = ArchivePresentationCoordinator()
    let model = makeModel(
      coordinator: coordinator,
      probe: { try archiveCapability(ownerState: .pending) },
      supportsIOS27: true)
    await model.refreshArchiveAvailability()

    XCTAssertTrue(model.isFullHistoryAvailable)
    XCTAssertFalse(model.canArchiveHistory)
    await model.importReadableHistory(metrics: [.steps], requestedStart: nil)
    let selection = await coordinator.selection
    XCTAssertNil(selection)
    let description = ArchiveImportPresentation.ownerDescription(
      state: model.archiveCapability?.ownerState,
      fingerprint: model.archiveCapability?.fingerprint)
    XCTAssertTrue(description.contains("pending"))
    XCTAssertTrue(description.contains("0123456789ab"))
    XCTAssertFalse(description.contains("secret"))
    var report = ArchiveImportReport()
    report.archiveState = .paused
    report.failures = [.init(category: .configuration, issue: .ownerPending)]
    XCTAssertTrue(ArchiveImportPresentation.archiveStatus(report).contains("approval"))
    XCTAssertTrue(
      ArchiveImportPresentation.recoveryGuidance(report.failures[0])?.contains("administrator")
        == true)
  }

  func testFirstClaimRequestsApprovalAndRetainsFingerprint() async throws {
    let claims = ArchiveClaimCounter()
    let model = makeModel(
      probe: { try archiveCapability(ownerState: .unbound) },
      claim: { try await claims.claim() }, supportsIOS27: true)
    await model.refreshArchiveAvailability()
    await model.requestArchiveOwnerClaim()

    let claimCount = await claims.count
    XCTAssertEqual(claimCount, 1)
    XCTAssertEqual(model.archiveClaimStatus?.ownerState, .pending)
    XCTAssertEqual(model.archiveClaimStatus?.fingerprint, "0123456789ab")
  }

  func testCompleteDeletionDeletesArchiveCredentialButSyncResetKeepsIt() async {
    let deletion = ArchiveCredentialDeletionCounter()
    let model = makeModel(
      credentialDelete: { await deletion.record() }, supportsIOS27: true)
    await model.resetSynchronizationState()
    let afterReset = await deletion.count
    XCTAssertEqual(afterReset, 0)
    await model.deleteAllLocalApplicationData()
    let afterDelete = await deletion.count
    XCTAssertEqual(afterDelete, 1)
    XCTAssertTrue(
      DestructiveActionPresentation.deleteAll.confirmationMessage.contains(
        "administrator must approve"))
  }

  func testEveryReconciliationBlockerOverridesCompletionAndNamesAffectedType() {
    for issue: ArchiveImportIssue in [
      .reconciliationRequired, .authorizationUnproven, .inventoryTooDense, .inventoryUnstable,
    ] {
      var report = ArchiveImportReport()
      report.archiveState = .archived
      report.failures = [.init(type: .stepCount, category: .healthKit, issue: issue)]
      let status = ArchiveImportPresentation.archiveStatus(report)
      XCTAssertTrue(status.contains("cannot be confirmed"), "\(issue): \(status)")
      XCTAssertTrue(status.contains("Steps"), "\(issue): \(status)")
      XCTAssertFalse(status.lowercased().contains("denied"))
    }
  }

  func testIOS27V2DiscoversPerMetricDatesAndRoutesAllHistoryToArchive() async throws {
    let query = ArchivePresentationQuery(
      history: ArchiveHistoryDiscovery(
        types: [.stepCount: .readable(earliest: date, authorizationBoundary: date)],
        metrics: [
          .steps: .readable(earliest: date, authorizationBoundary: date),
          .lastAppleWorkout: .readable(
            earliest: date.addingTimeInterval(86_400), authorizationBoundary: nil),
        ]))
    let coordinator = ArchivePresentationCoordinator()
    let model = makeModel(query: query, coordinator: coordinator, supportsIOS27: true)

    await model.refreshArchiveAvailability()
    XCTAssertTrue(model.isFullHistoryAvailable)
    XCTAssertEqual(
      model.archiveDiscovery?.metrics[.steps],
      .readable(earliest: date, authorizationBoundary: date))
    XCTAssertEqual(
      model.archiveDiscovery?.metrics[.lastAppleWorkout],
      .readable(earliest: date.addingTimeInterval(86_400), authorizationBoundary: nil))
    XCTAssertTrue(model.archiveEligibleDefinitions.contains { $0.id == .lastAppleWorkout })

    await model.importReadableHistory(metrics: [.steps, .lastAppleWorkout], requestedStart: nil)
    let selection = await coordinator.selection
    XCTAssertEqual(
      selection,
      ArchiveImportSelection(metrics: [.steps, .lastAppleWorkout], requestedStart: nil))
    XCTAssertEqual(model.lastArchiveReport?.archivedSamples, 12)
    XCTAssertEqual(model.lastArchiveReport?.projectionStates[.steps], .failed)
  }

  func testOlderOSAndV1CapabilityRetainLegacyWindow() async {
    let oldOS = makeModel(supportsIOS27: false)
    await oldOS.refreshArchiveAvailability()
    XCTAssertFalse(oldOS.isFullHistoryAvailable)
    XCTAssertFalse(oldOS.archiveEligibleDefinitions.contains { $0.id == .lastAppleWorkout })

    let v1 = makeModel(probe: { throw ArchivePresentationError.unsupported }, supportsIOS27: true)
    await v1.refreshArchiveAvailability()
    XCTAssertFalse(v1.isFullHistoryAvailable)
    XCTAssertEqual(
      v1.archiveAvailabilityDescription,
      "Full history requires the Health Bridge archive integration. The 14-day import remains available."
    )
  }

  func testArchiveCapabilityCanBeExplainedBeforeOptInButCannotImport() async {
    let coordinator = ArchivePresentationCoordinator()
    let model = makeModel(coordinator: coordinator, enabled: false, supportsIOS27: true)

    await model.refreshArchiveAvailability()

    XCTAssertTrue(model.isFullHistoryAvailable)
    await model.importReadableHistory(metrics: [.steps], requestedStart: nil)
    let selection = await coordinator.selection
    XCTAssertNil(selection)
  }

  func testNoReadableSamplesStaysAmbiguousAndCannotStartArchive() async {
    let query = ArchivePresentationQuery(
      history: ArchiveHistoryDiscovery(
        types: [.stepCount: .noReadableSamples(authorizationBoundary: nil)],
        metrics: [.steps: .noReadableSamples(authorizationBoundary: nil)]))
    let coordinator = ArchivePresentationCoordinator()
    let model = makeModel(query: query, coordinator: coordinator, supportsIOS27: true)
    await model.refreshArchiveAvailability()

    XCTAssertEqual(
      model.archiveDiscovery?.metrics[.steps], .noReadableSamples(authorizationBoundary: nil))
    await model.importReadableHistory(metrics: [.steps], requestedStart: nil)
    let selection = await coordinator.selection
    XCTAssertNil(selection)
  }

  func testPauseResumeAndProjectionRefreshRemainSeparate() async {
    let coordinator = ArchivePresentationCoordinator()
    let model = makeModel(coordinator: coordinator, supportsIOS27: true)
    await model.refreshArchiveAvailability()
    await model.importReadableHistory(metrics: [.steps], requestedStart: nil)
    await model.pauseArchiveImport()
    let pauseCount = await coordinator.pauseCount
    XCTAssertEqual(pauseCount, 1)
    await model.resumeArchiveImport()
    let resumeCount = await coordinator.resumeCount
    XCTAssertEqual(resumeCount, 1)
    await model.refreshArchiveProjection()
    let projectionCount = await coordinator.projectionCount
    XCTAssertEqual(projectionCount, 1)
    XCTAssertEqual(model.lastArchiveReport?.projectionStates[.steps], .failed)
  }

  func testResetClearsArchivePresentationWithoutDeletingServerCopy() async {
    let model = makeModel(supportsIOS27: true)
    await model.refreshArchiveAvailability()
    await model.resetSynchronizationState()
    XCTAssertNil(model.archiveDiscovery)
    XCTAssertNil(model.lastArchiveReport)
    XCTAssertTrue(
      DestructiveActionPresentation.reset.preserved.contains("Home Assistant health archive"))
    XCTAssertTrue(
      DestructiveActionPresentation.deleteAll.preserved.contains("Home Assistant health archive"))
  }

  func testReconciliationWarningOverridesArchiveCompletionAndPrivacyStatesScope() {
    var report = ArchiveImportReport()
    report.archiveState = .archived
    report.failures = [
      ArchiveImportFailure(type: .stepCount, category: .healthKit, issue: .reconciliationRequired)
    ]

    XCTAssertTrue(ArchiveImportPresentation.archiveStatus(report).contains("cannot be confirmed"))
    XCTAssertTrue(ArchiveImportPresentation.privacyNotice.contains("long-lived copy"))
    XCTAssertTrue(ArchiveImportPresentation.privacyNotice.contains("backups"))
    XCTAssertTrue(ArchiveImportPresentation.deletionHelp.contains("administrator"))
    XCTAssertTrue(ArchiveImportPresentation.deletionHelp.contains("Recorder history"))
  }

  func testReadableDateCopyDistinguishesLimitedBoundaryFromNoSamples() {
    XCTAssertTrue(
      HistoricalEligibleMetricsView.historyDescription(
        .readable(earliest: date, authorizationBoundary: date)
      ).contains("limited access"))
    XCTAssertEqual(
      HistoricalEligibleMetricsView.historyDescription(
        .noReadableSamples(authorizationBoundary: nil)),
      "No readable samples found")
  }

  func testRestartRestoresCommittedProgressAndRequiresReconciliationBeforeResume() async {
    var checkpoint = ArchiveImportCheckpoint()
    checkpoint.selection = ArchiveImportSelection(metrics: [.steps], requestedStart: nil)
    checkpoint.archivedSamples = 27
    checkpoint.uploaderFingerprint = "0123456789ab"
    checkpoint.ownerGeneration = 1
    var type = ArchiveTypeCheckpoint()
    type.reconciliationRequired = true
    checkpoint.types[.stepCount] = type
    let store = InMemoryArchiveCheckpointStore(state: checkpoint)
    let model = makeModel(archiveCheckpointStore: store, supportsIOS27: true)

    await model.refreshArchiveAvailability()

    XCTAssertEqual(model.lastArchiveReport?.archivedSamples, 27)
    XCTAssertEqual(model.lastArchiveReport?.archiveState, .paused)
    XCTAssertEqual(model.lastArchiveReport?.failures.first?.issue, .reconciliationRequired)
  }

  func testSamePhoneReapprovedAtNewGenerationOffersSafeRescan() async {
    var checkpoint = ArchiveImportCheckpoint()
    checkpoint.selection = ArchiveImportSelection(metrics: [.steps], requestedStart: nil)
    checkpoint.uploaderFingerprint = "0123456789ab"
    checkpoint.ownerGeneration = 0
    let model = makeModel(
      archiveCheckpointStore: InMemoryArchiveCheckpointStore(state: checkpoint),
      supportsIOS27: true)

    await model.refreshArchiveAvailability()

    XCTAssertEqual(model.archiveCapability?.ownerGeneration, 1)
    XCTAssertEqual(model.archiveClaimFailure, .checkpointOwnerMismatch)
    XCTAssertFalse(model.canArchiveHistory)
  }

  func testStatisticsRefreshAfterRestartPreservesArchiveCountsAndReconciliation() async {
    let store = InMemoryArchiveCheckpointStore(state: reconciliationCheckpoint(samples: 27))
    let model = makeModel(archiveCheckpointStore: store, supportsIOS27: true)
    await model.refreshArchiveAvailability()

    await model.refreshArchiveProjection()

    XCTAssertEqual(model.lastArchiveReport?.archivedSamples, 27)
    XCTAssertEqual(model.lastArchiveReport?.archiveState, .paused)
    XCTAssertEqual(model.lastArchiveReport?.failures.first?.issue, .reconciliationRequired)
    XCTAssertEqual(model.lastArchiveReport?.projectionStates[.steps], .failed)
  }

  func testProjectionRefreshRevocationPausesAndDisablesResumeUntilApprovalRefresh() async {
    let model = makeModel(coordinator: RevokedProjectionCoordinator(), supportsIOS27: true)
    await model.refreshArchiveAvailability()
    await model.importReadableHistory(metrics: [.steps], requestedStart: nil)
    XCTAssertEqual(model.lastArchiveReport?.archiveState, .archived)

    await model.refreshArchiveProjection()

    XCTAssertEqual(model.lastArchiveReport?.archiveState, .paused)
    XCTAssertEqual(model.archiveClaimFailure, .ownerChanged)
    XCTAssertFalse(model.canArchiveHistory)
    XCTAssertEqual(model.lastArchiveReport?.archivedSamples, 12)
  }

  func testProjectionProgressCallbackBeforeReturnPreservesRestoredArchiveReport() async {
    let store = InMemoryArchiveCheckpointStore(state: reconciliationCheckpoint(samples: 27))
    let coordinator = CallbackArchivePresentationCoordinator()
    let model = makeModel(
      coordinator: coordinator, archiveCheckpointStore: store, supportsIOS27: true)
    await coordinator.setProgress { [weak model] report in
      model?.receiveArchiveProgress(report)
    }
    await model.refreshArchiveAvailability()

    await model.refreshArchiveProjection()

    XCTAssertEqual(model.lastArchiveReport?.archivedSamples, 27)
    XCTAssertEqual(model.lastArchiveReport?.archiveState, .paused)
    XCTAssertEqual(model.lastArchiveReport?.failures.first?.issue, .reconciliationRequired)
    XCTAssertEqual(model.lastArchiveReport?.projectionStates[.steps], .failed)
  }

  func testAvailabilityRefreshPreservesCompletedArchiveAndStatistics() async {
    let store = InMemoryArchiveCheckpointStore(state: reconciliationCheckpoint(samples: 5))
    let model = makeModel(archiveCheckpointStore: store, supportsIOS27: true)
    await model.refreshArchiveAvailability()
    await model.importReadableHistory(metrics: [.steps], requestedStart: nil)
    XCTAssertEqual(model.lastArchiveReport?.archiveState, .archived)

    await model.refreshArchiveAvailability()

    XCTAssertEqual(model.lastArchiveReport?.archiveState, .archived)
    XCTAssertEqual(model.lastArchiveReport?.archivedSamples, 12)
    XCTAssertEqual(model.lastArchiveReport?.projectionStates[.steps], .failed)
  }

  func testAvailabilityRefreshDoesNotPauseActiveArchivePresentation() async {
    let store = InMemoryArchiveCheckpointStore(state: reconciliationCheckpoint(samples: 5))
    let coordinator = SuspendedArchivePresentationCoordinator()
    let model = makeModel(
      coordinator: coordinator, archiveCheckpointStore: store, supportsIOS27: true)
    await model.refreshArchiveAvailability()
    let importTask = Task {
      await model.importReadableHistory(metrics: [.steps], requestedStart: nil)
    }
    await coordinator.waitUntilStarted()
    var progress = ArchiveImportReport()
    progress.archiveState = .importing
    progress.archivedSamples = 8
    model.receiveArchiveProgress(progress)

    await model.refreshArchiveAvailability()

    XCTAssertTrue(model.isArchiveImportRunning)
    XCTAssertEqual(model.lastArchiveReport?.archiveState, .importing)
    XCTAssertEqual(model.lastArchiveReport?.archivedSamples, 8)
    await coordinator.release()
    await importTask.value
  }

  func testDelayedCapabilityProbeCannotRepublishAfterReset() async {
    let gate = ArchiveCapabilityProbeGate()
    let model = makeModel(probe: { try await gate.probe() }, supportsIOS27: true)
    let refreshTask = Task { await model.refreshArchiveAvailability() }
    await gate.waitUntilStarted()

    await model.resetSynchronizationState()
    await gate.release()
    await refreshTask.value

    XCTAssertNil(model.archiveCapability)
    XCTAssertNil(model.archiveDiscovery)
    XCTAssertNil(model.archiveSavedSelection)
    XCTAssertNil(model.lastArchiveReport)
  }

  func testOldProbeFailureCannotEraseNewConnectionCapability() async throws {
    var configuration = AppConfiguration.default
    configuration.baseURL = "https://old.example.invalid"
    configuration.healthBridgeUserID = "old-user"
    configuration.selectedMetrics = [.steps]
    configuration.experimentalBackfillEnabled = true
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    try await credentials.write("fixture-token", for: .accessToken)
    let gate = FirstArchiveCapabilityProbeGate()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      archiveCoordinator: ArchivePresentationCoordinator(),
      archiveQuery: ArchivePresentationQuery(
        history: ArchiveHistoryDiscovery(
          types: [.stepCount: .readable(earliest: date, authorizationBoundary: nil)],
          metrics: [.steps: .readable(earliest: date, authorizationBoundary: nil)])),
      archiveCapabilityProbe: { try await gate.probe() },
      supportsFullHistoryOS: { true },
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      initialConfiguration: configuration)
    let oldRefresh = Task { await model.refreshArchiveAvailability() }
    await gate.waitUntilFirstStarted()

    configuration.baseURL = "https://new.example.invalid"
    configuration.healthBridgeUserID = "new-user"
    await model.updateConnection(
      configuration: configuration, webhookSecret: "", accessToken: "")
    XCTAssertNotNil(model.archiveCapability)
    await gate.failFirst()
    await oldRefresh.value

    XCTAssertEqual(model.currentConfiguration.baseURL, "https://new.example.invalid")
    XCTAssertNotNil(model.archiveCapability)
    XCTAssertNotNil(model.archiveDiscovery)
  }

  func testIntegrationVersionChangeRefreshesArchiveCapability() async throws {
    var configuration = AppConfiguration.default
    configuration.baseURL = "https://ha.example.invalid"
    configuration.healthBridgeUserID = "fixture-user"
    configuration.selectedMetrics = [.steps]
    configuration.experimentalBackfillEnabled = true
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    let counter = ArchiveProbeCounter()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      archiveCoordinator: ArchivePresentationCoordinator(),
      archiveQuery: ArchivePresentationQuery(
        history: ArchiveHistoryDiscovery(
          types: [.stepCount: .readable(earliest: date, authorizationBoundary: nil)],
          metrics: [.steps: .readable(earliest: date, authorizationBoundary: nil)])),
      archiveCapabilityProbe: { try await counter.probe() },
      supportsFullHistoryOS: { true },
      credentialStore: credentials,
      webhookClient: ArchiveVersionedWebhook(),
      initialConfiguration: configuration)

    await model.testWebhookConnection(configuration: configuration)
    await model.testWebhookConnection(configuration: configuration)
    let unchangedCount = await counter.value()
    XCTAssertEqual(unchangedCount, 1)
    await model.testWebhookConnection(configuration: configuration)
    let changedCount = await counter.value()
    XCTAssertEqual(changedCount, 2)
  }

  private func makeModel(
    query: ArchivePresentationQuery? = nil,
    coordinator: any ArchiveImportCoordinating = ArchivePresentationCoordinator(),
    archiveCheckpointStore: (any ArchiveCheckpointStore)? = nil,
    probe: @escaping @Sendable () async throws -> ArchiveCapability = { try archiveCapability() },
    claim: (@Sendable () async throws -> ArchiveOwnerClaimStatus)? = nil,
    credentialDelete: (@Sendable () async throws -> Void)? = nil,
    enabled: Bool = true,
    supportsIOS27: Bool
  ) -> AppModel {
    var configuration = AppConfiguration.default
    configuration.selectedMetrics = [.steps, .lastAppleWorkout]
    configuration.experimentalBackfillEnabled = enabled
    return AppModel(
      bidirectionalSyncCoordinator: nil,
      archiveCoordinator: coordinator,
      archiveCheckpointStore: archiveCheckpointStore,
      archiveQuery: query
        ?? ArchivePresentationQuery(
          history: ArchiveHistoryDiscovery(
            types: [.stepCount: .readable(earliest: date, authorizationBoundary: nil)],
            metrics: [.steps: .readable(earliest: date, authorizationBoundary: nil)])),
      archiveCapabilityProbe: probe,
      archiveOwnerClaim: claim,
      archiveUploaderFingerprint: { "0123456789ab" },
      archiveUploaderCredentialDelete: credentialDelete,
      supportsFullHistoryOS: { supportsIOS27 },
      initialConfiguration: configuration)
  }

  private func reconciliationCheckpoint(samples: Int) -> ArchiveImportCheckpoint {
    var checkpoint = ArchiveImportCheckpoint()
    checkpoint.selection = ArchiveImportSelection(metrics: [.steps], requestedStart: nil)
    checkpoint.archivedSamples = samples
    checkpoint.uploaderFingerprint = "0123456789ab"
    checkpoint.ownerGeneration = 1
    var type = ArchiveTypeCheckpoint()
    type.reconciliationRequired = true
    checkpoint.types[.stepCount] = type
    return checkpoint
  }
}

private enum ArchivePresentationError: Error { case unsupported }

private actor ArchiveProbeCounter {
  private var count = 0
  func probe() throws -> ArchiveCapability {
    count += 1
    return try archiveCapability()
  }
  func value() -> Int { count }
}

private actor ArchiveVersionedWebhook: WebhookConnectionTesting {
  private var count = 0
  func testWebhook(
    baseURL: NormalizedBaseURL, webhookSecret: String, userID: String, requestID: String
  ) -> WebhookConnectionAcknowledgement {
    count += 1
    return WebhookConnectionAcknowledgement(
      ok: true,
      integrationVersion: count == 3 ? "2.2.0" : "2.1.0",
      backfillProtocol: 1,
      backfillAcknowledgement: "committed",
      statisticsPolicy: "history_only")
  }
}

private func archiveCapability(ownerState: ArchiveOwnerState = .active) throws -> ArchiveCapability
{
  let pendingFields =
    ownerState == .pending
    ? ",\"claim_id\":\"claim-1\",\"fingerprint\":\"0123456789ab\",\"expires_at\":\"2026-09-27T00:00:00Z\""
    : ""
  let json = """
    {"ok":true,"request_type":"archive_capability","protocol_version":2,
    "request_id":"test-request","archive_schema_version":3,
    "ownership_contract_version":1,"owner_state":"\(ownerState.rawValue)","owner_generation":1\(pendingFields),
    "max_batch_bytes":1024,
    "max_samples_per_batch":10,"max_deletions_per_batch":10,
    "supported_sample_types":["HKQuantityTypeIdentifierStepCount","HKWorkoutType"],
    "supported_metrics":["steps","last_apple_workout"],
    "archive_available":true,"statistics_available":true}
    """
  return try JSONDecoder().decode(ArchiveCapability.self, from: Data(json.utf8))
}

private actor ArchiveCredentialDeletionCounter {
  private(set) var count = 0
  func record() { count += 1 }
}

private actor ArchiveClaimCounter {
  private(set) var count = 0
  func claim() throws -> ArchiveOwnerClaimStatus {
    count += 1
    let json = """
      {"ok":true,"request_type":"archive_owner_claim","protocol_version":2,
      "request_id":"claim-1","ownership_contract_version":1,"owner_state":"pending",
      "owner_generation":0,"claim_id":"claim-1","fingerprint":"0123456789ab",
      "expires_at":"2026-09-27T00:00:00Z"}
      """
    return try JSONDecoder().decode(ArchiveOwnerClaimStatus.self, from: Data(json.utf8))
  }
}

private actor ArchivePresentationQuery: HealthArchiveQuerying {
  let history: ArchiveHistoryDiscovery
  init(history: ArchiveHistoryDiscovery) { self.history = history }
  func discover(types: Set<HealthObjectTypeID>) -> [HealthObjectTypeID: ReadableHistory] {
    history.types
  }
  func discover(metrics: [MetricDefinition]) -> ArchiveHistoryDiscovery { history }
  func page(
    type: HealthObjectTypeID, interval: DateInterval, cursor: ArchiveScanCursor?, limit: Int
  ) throws -> ArchiveSamplePage { throw ArchivePresentationError.unsupported }
  func changes(type: HealthObjectTypeID, anchor: Data?) throws -> ArchiveChangePage {
    throw ArchivePresentationError.unsupported
  }
}

private actor ArchivePresentationCoordinator: ArchiveImportCoordinating {
  private(set) var selection: ArchiveImportSelection?
  private(set) var pauseCount = 0
  private(set) var resumeCount = 0
  private(set) var projectionCount = 0

  func importHistory(selection: ArchiveImportSelection) -> ArchiveImportReport {
    self.selection = selection
    var report = ArchiveImportReport()
    report.archiveState = .archived
    report.archivedSamples = 12
    report.projectionStates[.steps] = .failed
    return report
  }
  func pause() { pauseCount += 1 }
  func resume() -> ArchiveImportReport {
    resumeCount += 1
    var report = ArchiveImportReport()
    report.archiveState = .archived
    return report
  }
  func refreshProjection() -> ArchiveImportReport {
    projectionCount += 1
    var report = ArchiveImportReport()
    report.archiveState = .archived
    report.projectionStates[.steps] = .failed
    return report
  }
}

private actor RevokedProjectionCoordinator: ArchiveImportCoordinating {
  func importHistory(selection: ArchiveImportSelection) -> ArchiveImportReport {
    var report = ArchiveImportReport()
    report.archiveState = .archived
    report.archivedSamples = 12
    return report
  }
  func pause() {}
  func resume() -> ArchiveImportReport { ArchiveImportReport() }
  func refreshProjection() -> ArchiveImportReport {
    var report = ArchiveImportReport()
    report.archiveState = .paused
    report.failures = [.init(category: .configuration, issue: .ownerChanged)]
    return report
  }
}

private actor SuspendedArchivePresentationCoordinator: ArchiveImportCoordinating {
  private var started = false
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var finishContinuation: CheckedContinuation<Void, Never>?

  func importHistory(selection: ArchiveImportSelection) async -> ArchiveImportReport {
    started = true
    startContinuation?.resume()
    startContinuation = nil
    await withCheckedContinuation { finishContinuation = $0 }
    var report = ArchiveImportReport()
    report.archiveState = .archived
    report.archivedSamples = 12
    return report
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startContinuation = $0 }
  }

  func release() {
    finishContinuation?.resume()
    finishContinuation = nil
  }

  func pause() async { release() }
  func resume() -> ArchiveImportReport { ArchiveImportReport() }
  func refreshProjection() -> ArchiveImportReport { ArchiveImportReport() }
}

private actor CallbackArchivePresentationCoordinator: ArchiveImportCoordinating {
  private var progress: (@MainActor @Sendable (ArchiveImportReport) -> Void)?

  func setProgress(_ callback: @escaping @MainActor @Sendable (ArchiveImportReport) -> Void) {
    progress = callback
  }

  func importHistory(selection: ArchiveImportSelection) -> ArchiveImportReport {
    ArchiveImportReport()
  }

  func pause() {}
  func resume() -> ArchiveImportReport { ArchiveImportReport() }

  func refreshProjection() async -> ArchiveImportReport {
    var report = ArchiveImportReport()
    report.projectionStates[.steps] = .failed
    await progress?(report)
    return report
  }
}

private actor ArchiveCapabilityProbeGate {
  private var started = false
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var resultContinuation: CheckedContinuation<ArchiveCapability, any Error>?

  func probe() async throws -> ArchiveCapability {
    started = true
    startContinuation?.resume()
    startContinuation = nil
    return try await withCheckedThrowingContinuation { resultContinuation = $0 }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startContinuation = $0 }
  }

  func release() {
    do {
      resultContinuation?.resume(returning: try archiveCapability())
    } catch {
      resultContinuation?.resume(throwing: error)
    }
    resultContinuation = nil
  }
}

private actor FirstArchiveCapabilityProbeGate {
  private var calls = 0
  private var firstStarted = false
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var firstResult: CheckedContinuation<ArchiveCapability, any Error>?

  func probe() async throws -> ArchiveCapability {
    calls += 1
    if calls > 1 { return try archiveCapability() }
    firstStarted = true
    startContinuation?.resume()
    startContinuation = nil
    return try await withCheckedThrowingContinuation { firstResult = $0 }
  }

  func waitUntilFirstStarted() async {
    if firstStarted { return }
    await withCheckedContinuation { startContinuation = $0 }
  }

  func failFirst() {
    firstResult?.resume(throwing: ArchivePresentationError.unsupported)
    firstResult = nil
  }
}
