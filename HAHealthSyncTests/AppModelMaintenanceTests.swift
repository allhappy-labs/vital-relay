import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppModelMaintenanceTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_788_035_400)
  private let pairingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

  func testResetClearsOnlySynchronizationStateAndRestartsConfiguredBackgroundSync() async throws {
    let fixture = try await makeFixture()

    await fixture.model.resetSynchronizationState()

    XCTAssertFalse(fixture.model.isPerformingDestructiveAction)
    XCTAssertEqual(fixture.model.maintenanceFailureCount, 0)
    XCTAssertTrue(fixture.model.isOnboardingComplete)
    let configuration = try await fixture.configuration.load()
    let pairings = try await fixture.pairings.all()
    let secret = try await fixture.credentials.read(.webhookSecret)
    let syncAnchor = try await fixture.syncCheckpoints.anchor(for: .steps)
    let pairingCheckpoint = try await fixture.pairingCheckpoints.checkpoint(for: pairingID)
    let backfillState = try await fixture.backfillCheckpoints.load()
    let medicationCheckpoint = try await fixture.medicationCheckpoints.load()
    XCTAssertEqual(configuration, fixture.configured)
    XCTAssertEqual(pairings.count, 1)
    XCTAssertNotNil(secret)
    XCTAssertNil(syncAnchor)
    XCTAssertNil(pairingCheckpoint)
    XCTAssertEqual(backfillState, BackfillState())
    XCTAssertNil(medicationCheckpoint)
    let status = await fixture.status.snapshot()
    XCTAssertNil(status.lastAttemptedAt)
    XCTAssertTrue(status.recentEvents.isEmpty)
    XCTAssertEqual(fixture.runtime.suspendCount, 1)
    XCTAssertEqual(fixture.runtime.reconcileCount, 1)
    let freshnessResets = await fixture.freshness.resetCount
    let freshness = await fixture.freshness.snapshot()
    XCTAssertEqual(freshnessResets, 1)
    XCTAssertEqual(freshness, MetricFreshnessSnapshot())
    XCTAssertNil(fixture.model.lastFullSweepAt)
  }

  func testDeleteAllStopsBackgroundDeletesEveryLocalStoreAndReturnsToOnboarding() async throws {
    let fixture = try await makeFixture()

    await fixture.model.deleteAllLocalApplicationData()

    XCTAssertFalse(fixture.model.isPerformingDestructiveAction)
    XCTAssertEqual(fixture.model.maintenanceFailureCount, 0)
    XCTAssertFalse(fixture.model.isOnboardingComplete)
    XCTAssertEqual(fixture.model.currentConfiguration, .default)
    let configuration = try await fixture.configuration.load()
    let pairings = try await fixture.pairings.all()
    let secret = try await fixture.credentials.read(.webhookSecret)
    let token = try await fixture.credentials.read(.accessToken)
    let syncAnchor = try await fixture.syncCheckpoints.anchor(for: .steps)
    let pairingCheckpoint = try await fixture.pairingCheckpoints.checkpoint(for: pairingID)
    let backfillState = try await fixture.backfillCheckpoints.load()
    let medicationCheckpoint = try await fixture.medicationCheckpoints.load()
    let status = await fixture.status.snapshot()
    XCTAssertEqual(configuration, AppConfiguration.default)
    XCTAssertTrue(pairings.isEmpty)
    XCTAssertNil(secret)
    XCTAssertNil(token)
    XCTAssertNil(syncAnchor)
    XCTAssertNil(pairingCheckpoint)
    XCTAssertEqual(backfillState, BackfillState())
    XCTAssertNil(medicationCheckpoint)
    XCTAssertEqual(status, SyncStatusSnapshot())
    XCTAssertEqual(fixture.runtime.suspendCount, 1)
    XCTAssertEqual(fixture.runtime.reconcileCount, 0)
    let freshnessResets = await fixture.freshness.resetCount
    let freshness = await fixture.freshness.snapshot()
    XCTAssertEqual(freshnessResets, 1)
    XCTAssertEqual(freshness, MetricFreshnessSnapshot())
    XCTAssertNil(fixture.model.lastFullSweepAt)
  }

  func testDiagnosticsAreAllowlistedAndRedactedWithStoredCredentials() async throws {
    let fixture = try await makeFixture()

    let diagnostics = try await fixture.model.diagnosticsText(
      appVersion: "1.0",
      buildVersion: "42",
      osVersion: "iOS 26.5",
      generatedAt: date
    )

    XCTAssertTrue(diagnostics.contains(#""live_protocol_version" : 1"#))
    XCTAssertTrue(diagnostics.contains(#""selected_metric_count" : 2"#))
    XCTAssertFalse(diagnostics.contains("fixture-webhook-secret"))
    XCTAssertFalse(diagnostics.contains("fixture-access-token"))
    XCTAssertFalse(diagnostics.contains("ha.internal.example"))
    XCTAssertFalse(diagnostics.contains("sensor.body_mass"))
    XCTAssertFalse(diagnostics.contains("8421"))
  }

  func testConnectionUpdatePreservesBlankCredentialFields() async throws {
    let fixture = try await makeFixture()
    var updated = fixture.configured
    updated.baseURL = "https://new-ha.example.com"
    updated.healthBridgeUserID = "updated-user"

    await fixture.model.updateConnection(
      configuration: updated,
      webhookSecret: "   ",
      accessToken: ""
    )

    let savedConfiguration = try await fixture.configuration.load()
    let savedWebhookSecret = try await fixture.credentials.read(.webhookSecret)
    let savedAccessToken = try await fixture.credentials.read(.accessToken)
    XCTAssertEqual(savedConfiguration, updated)
    XCTAssertEqual(savedWebhookSecret, "fixture-webhook-secret")
    XCTAssertEqual(savedAccessToken, "fixture-access-token")
    XCTAssertNil(fixture.model.currentError)
    XCTAssertTrue(fixture.model.isOnboardingComplete)
  }

  private func makeFixture() async throws -> MaintenanceFixture {
    let configured = AppConfiguration(
      baseURL: "https://ha.internal.example",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "fixture-user",
      selectedMetrics: [.steps, .bodyMass],
      backgroundSyncEnabled: true,
      experimentalBackfillEnabled: true,
      medicationSyncEnabled: true
    )
    let configuration = InMemoryConfigurationStore(configuration: configured)
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-webhook-secret", for: .webhookSecret)
    try await credentials.write("fixture-access-token", for: .accessToken)
    let pairings = try InMemoryPairingStore(
      pairings: [
        Pairing(
          id: pairingID,
          entityID: "sensor.body_mass",
          destination: .bodyMass,
          sourceUnit: .kilograms,
          destinationUnit: .kilograms,
          transformation: .identity,
          isEnabled: true
        )
      ]
    )
    let syncCheckpoints = InMemorySyncCheckpointStore(anchors: [.steps: Data([1])])
    let identity = SyncIdentity.make(
      pairingID: pairingID,
      entityID: "sensor.body_mass",
      homeAssistantUpdatedAt: date,
      normalizedValue: 80,
      destination: .bodyMass
    )
    let pairingCheckpoints = InMemoryPairingCheckpointStore(
      checkpoints: [
        pairingID: PairingCheckpoint(
          pairingID: pairingID,
          entityID: "sensor.body_mass",
          homeAssistantUpdatedAt: date,
          normalizedValue: 80,
          destination: .bodyMass,
          syncIdentifier: identity.identifier,
          syncVersion: identity.version
        )
      ]
    )
    let backfillCheckpoints = InMemoryBackfillCheckpointStore(
      state: BackfillState(capability: .available(protocolVersion: 1))
    )
    let medicationID = MedicationIdentifier.make(from: Data("fixture-medication".utf8))
    let medicationCheckpoints = InMemoryMedicationCheckpointStore(
      checkpoint: MedicationCheckpoint(
        anchor: Data([2]),
        medicationIDs: [medicationID],
        sourceFingerprint: MedicationIdentifier.fingerprint([medicationID])
      )
    )
    let report = SyncReport(
      trigger: .manual,
      attemptedMetrics: 1,
      synchronizedMetrics: 0,
      skippedMetrics: 0,
      failures: [.init(metricID: .steps, category: .offline)],
      startedAt: date,
      finishedAt: date
    )
    let status = InMemorySyncStatusStore()
    try await status.record(report: report)
    let freshness = RecordingMetricFreshnessStore(
      snapshot: MetricFreshnessSnapshot(
        lastCheckedAt: [.steps: date],
        lastSentAt: [.steps: date],
        lastFullSweepAt: date,
        rotationOffset: 3
      )
    )
    let runtime = MaintenanceRuntime()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      backfillCheckpointStore: backfillCheckpoints,
      configurationStore: configuration,
      credentialStore: credentials,
      backgroundRuntime: runtime,
      statusStore: status,
      pairingStore: pairings,
      pairingCheckpointStore: pairingCheckpoints,
      syncCheckpointStore: syncCheckpoints,
      medicationCheckpointStore: medicationCheckpoints,
      metricFreshnessStore: freshness,
      initialConfiguration: configured,
      isOnboardingComplete: true,
      initialSyncStatus: await status.snapshot()
    )
    return MaintenanceFixture(
      model: model,
      configured: configured,
      configuration: configuration,
      credentials: credentials,
      pairings: pairings,
      syncCheckpoints: syncCheckpoints,
      pairingCheckpoints: pairingCheckpoints,
      backfillCheckpoints: backfillCheckpoints,
      medicationCheckpoints: medicationCheckpoints,
      status: status,
      freshness: freshness,
      runtime: runtime
    )
  }
}

private struct MaintenanceFixture {
  let model: AppModel
  let configured: AppConfiguration
  let configuration: InMemoryConfigurationStore
  let credentials: InMemoryCredentialStore
  let pairings: InMemoryPairingStore
  let syncCheckpoints: InMemorySyncCheckpointStore
  let pairingCheckpoints: InMemoryPairingCheckpointStore
  let backfillCheckpoints: InMemoryBackfillCheckpointStore
  let medicationCheckpoints: InMemoryMedicationCheckpointStore
  let status: InMemorySyncStatusStore
  let freshness: RecordingMetricFreshnessStore
  let runtime: MaintenanceRuntime
}

/// A freshness store that counts resets, so the destructive actions can be shown to clear the
/// freshness the scope policy decides from.
private actor RecordingMetricFreshnessStore: MetricFreshnessStore {
  private(set) var resetCount = 0
  private var stored: MetricFreshnessSnapshot

  init(snapshot: MetricFreshnessSnapshot = MetricFreshnessSnapshot()) {
    stored = snapshot
  }

  func snapshot() -> MetricFreshnessSnapshot { stored }

  func record(_ update: MetricFreshnessUpdate) {
    stored.apply(update)
  }

  func reset() {
    resetCount += 1
    stored = MetricFreshnessSnapshot()
  }
}

@MainActor
private final class MaintenanceRuntime: BackgroundSyncRuntimeControlling {
  private(set) var reconcileCount = 0
  private(set) var suspendCount = 0

  func reconcile() async { reconcileCount += 1 }
  func suspend() async { suspendCount += 1 }
}
