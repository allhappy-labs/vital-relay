import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppModelExperimentalFeaturesTests: XCTestCase {
  func testPurchaseRequiredPreservesServerCapabilityAndManualSync() async {
    var configuration = configuration
    configuration.experimentalBackfillEnabled = true
    let live = ExperimentalSyncCoordinator()
    let model = AppModel(
      bidirectionalSyncCoordinator: live,
      backfillCoordinator: FakeBackfillCoordinator(
        report: BackfillReport(
          attemptedMetrics: 1, committedMetrics: 0, committedPoints: 0,
          capability: .temporarilyUnavailable,
          failures: [.init(metricID: nil, category: .purchaseRequired)])),
      initialConfiguration: configuration, isOnboardingComplete: true)
    await model.importHistory(metrics: [.steps], requestedStart: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(model.currentError, .purchaseRequired)
    XCTAssertEqual(model.historicalImportCapability, .unprobed)
    XCTAssertTrue(model.lastBackfillReport?.requiresPurchase == true)
    await model.syncNow()
    let triggers = await live.triggers
    XCTAssertEqual(triggers, [.manual])
  }
  private let configuration = AppConfiguration(
    baseURL: "https://ha.example.invalid",
    allowsConfirmedLocalHTTP: false,
    healthBridgeUserID: "fixture-user",
    selectedMetrics: [.steps, .bodyMass],
    backgroundSyncEnabled: false
  )

  func testBackfillRequiresOptInAndPublishesOnlyCommittedCountsAndCapability() async throws {
    let store = InMemoryConfigurationStore(configuration: configuration)
    let backfill = FakeBackfillCoordinator(
      report: BackfillReport(
        attemptedMetrics: 2,
        committedMetrics: 0,
        skippedMetrics: 0,
        committedPoints: 0,
        capability: .incompatible(reason: .unsupportedRecorder),
        failures: [.init(metricID: nil, category: .compatibility)]
      )
    )
    let live = ExperimentalSyncCoordinator()
    let model = AppModel(
      bidirectionalSyncCoordinator: live,
      backfillCoordinator: backfill,
      backfillCheckpointStore: InMemoryBackfillCheckpointStore(),
      configurationStore: store,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )

    XCTAssertFalse(model.experimentalBackfillEnabled)
    await model.setExperimentalBackfillEnabled(true)
    XCTAssertTrue(model.experimentalBackfillEnabled)
    let enabledConfiguration = try await store.load()
    XCTAssertTrue(enabledConfiguration.experimentalBackfillEnabled)

    await model.importHistory(
      metrics: [.steps, .bodyMass],
      requestedStart: Date(timeIntervalSince1970: 1_788_000_000)
    )

    XCTAssertFalse(model.isBackfillRunning)
    XCTAssertEqual(
      model.historicalImportCapability,
      .incompatible(reason: .unsupportedRecorder)
    )
    XCTAssertEqual(model.lastBackfillReport?.committedPoints, 0)
    XCTAssertEqual(model.currentError, .compatibility)

    await model.syncNow()
    let liveTriggers = await live.triggers
    XCTAssertEqual(liveTriggers, [.manual])
  }

  func testBackfillPublishesNoHistoryAsSkippedWithoutAnError() async {
    var enabledConfiguration = configuration
    enabledConfiguration.experimentalBackfillEnabled = true
    let report = BackfillReport(
      attemptedMetrics: 85,
      committedMetrics: 16,
      skippedMetrics: 69,
      committedPoints: 370,
      capability: .available(protocolVersion: 1),
      failures: []
    )
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      backfillCoordinator: FakeBackfillCoordinator(report: report),
      initialConfiguration: enabledConfiguration,
      isOnboardingComplete: true
    )

    await model.importHistory(
      metrics: [.steps, .bodyMass],
      requestedStart: Date(timeIntervalSince1970: 1_788_000_000)
    )

    XCTAssertEqual(model.lastBackfillReport?.skippedMetrics, 69)
    XCTAssertEqual(model.lastBackfillReport?.failures.count, 0)
    XCTAssertNil(model.currentError)
  }

  func testMedicationAuthorizationListsOnlyAuthorizedConceptsAndPersistsOptIn() async throws {
    let store = InMemoryConfigurationStore(configuration: configuration)
    let medication = FakeMedicationAccess(
      concepts: [
        MedicationConcept(
          id: MedicationIdentifier.make(from: Data("first".utf8)),
          name: "Example medication"
        ),
        MedicationConcept(
          id: MedicationIdentifier.make(from: Data("archived".utf8)),
          name: "Archived medication",
          isArchived: true
        ),
      ]
    )
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: store,
      medicationAccess: medication,
      medicationSyncAvailable: true,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )

    let concepts = await model.requestMedicationAuthorization()

    XCTAssertEqual(concepts.compactMap(\.name), ["Example medication"])
    let authorizationRequests = await medication.authorizationRequests
    XCTAssertEqual(authorizationRequests, 1)
    await model.setMedicationSyncEnabled(true)
    XCTAssertTrue(model.medicationSyncEnabled)
    let enabledConfiguration = try await store.load()
    XCTAssertTrue(enabledConfiguration.medicationSyncEnabled)
  }

  func testUnavailableMedicationAPICannotBeEnabled() async throws {
    let store = InMemoryConfigurationStore(configuration: configuration)
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: store,
      medicationSyncAvailable: false,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )

    let concepts = await model.requestMedicationAuthorization()
    await model.setMedicationSyncEnabled(true)

    XCTAssertTrue(concepts.isEmpty)
    XCTAssertFalse(model.medicationSyncEnabled)
    let storedConfiguration = try await store.load()
    XCTAssertFalse(storedConfiguration.medicationSyncEnabled)
    XCTAssertEqual(model.currentError, .compatibility)
  }
}

private actor FakeBackfillCoordinator: BackfillCoordinating {
  let report: BackfillReport

  init(report: BackfillReport) {
    self.report = report
  }

  func importHistory(metrics: Set<MetricID>, requestedStart: Date) -> BackfillReport {
    report
  }
}

private actor FakeMedicationAccess: MedicationAccessProviding {
  let concepts: [MedicationConcept]
  private(set) var authorizationRequests = 0

  init(concepts: [MedicationConcept]) {
    self.concepts = concepts
  }

  func requestAuthorizationAndList() -> [MedicationConcept] {
    authorizationRequests += 1
    return concepts
  }
}

private actor ExperimentalSyncCoordinator: BidirectionalSyncCoordinating {
  private(set) var triggers: [SyncTrigger] = []

  func sync(trigger: SyncTrigger) -> BidirectionalSyncOutcome {
    triggers.append(trigger)
    let now = Date(timeIntervalSince1970: 1_788_035_400)
    return .performed(
      BidirectionalSyncReport(
        trigger: trigger,
        outbound: SyncReport(
          trigger: trigger,
          attemptedMetrics: 1,
          synchronizedMetrics: 1,
          skippedMetrics: 0,
          failures: [],
          startedAt: now,
          finishedAt: now
        ),
        inbound: nil,
        startedAt: now,
        finishedAt: now
      )
    )
  }
}
