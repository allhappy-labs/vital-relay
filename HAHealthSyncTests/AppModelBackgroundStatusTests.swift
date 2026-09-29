import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppModelBackgroundStatusTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_788_035_400)

  func testEnablingAttemptPublishingWithNonAdminTokenStaysOff() async throws {
    let store = InMemoryConfigurationStore(configuration: configuration())
    let publisher = StubAttemptPublisher(error: NetworkFailure.unauthorized)
    let model = makeModel(store: store, publisher: publisher)

    let result = await model.setPublishSyncAttempts(true)

    XCTAssertEqual(result, .requiresAdministrator)
    XCTAssertFalse(model.publishSyncAttempts)
    let stored = try await store.load()
    XCTAssertFalse(stored.publishSyncAttempts)
  }

  func testEnablingAttemptPublishingSavesAfterSuccessfulTest() async throws {
    let store = InMemoryConfigurationStore(configuration: configuration())
    let publisher = StubAttemptPublisher(error: nil)
    let model = makeModel(store: store, publisher: publisher)

    let result = await model.setPublishSyncAttempts(true)

    XCTAssertEqual(result, .enabled)
    XCTAssertTrue(model.publishSyncAttempts)
    let stored = try await store.load()
    XCTAssertTrue(stored.publishSyncAttempts)
    let testCount = await publisher.testCount
    XCTAssertEqual(testCount, 1)
  }

  func testDisablingAttemptPublishingDoesNotPublish() async throws {
    var enabled = configuration()
    enabled.publishSyncAttempts = true
    let store = InMemoryConfigurationStore(configuration: enabled)
    let publisher = StubAttemptPublisher(error: nil)
    let model = makeModel(store: store, publisher: publisher, initial: enabled)

    let result = await model.setPublishSyncAttempts(false)

    XCTAssertEqual(result, .disabled)
    let stored = try await store.load()
    XCTAssertFalse(stored.publishSyncAttempts)
    let testCount = await publisher.testCount
    XCTAssertEqual(testCount, 0)
  }

  func testEarliestNextAutomaticSyncFollowsThePolicy() {
    let attempted = makeModel(
      status: SyncStatusSnapshot(lastAttemptedAt: now.addingTimeInterval(-600))
    )
    XCTAssertEqual(attempted.earliestNextAutomaticSync, now.addingTimeInterval(2_400))

    let offline = makeModel(
      status: SyncStatusSnapshot(
        lastAttemptedAt: now.addingTimeInterval(-600),
        lastFailure: SyncStatusFailure(metricID: nil, category: .offline, at: now)
      )
    )
    XCTAssertEqual(offline.earliestNextAutomaticSync, now.addingTimeInterval(120))

    let locked = makeModel(
      status: SyncStatusSnapshot(
        lastAttemptedAt: now.addingTimeInterval(-600),
        lastFailure: SyncStatusFailure(metricID: nil, category: .deviceLocked, at: now)
      )
    )
    XCTAssertEqual(locked.earliestNextAutomaticSync, now)

    XCTAssertNil(makeModel(status: SyncStatusSnapshot()).earliestNextAutomaticSync)

    var disabled = configuration()
    disabled.backgroundSyncEnabled = false
    XCTAssertNil(
      makeModel(
        initial: disabled,
        status: SyncStatusSnapshot(lastAttemptedAt: now)
      ).earliestNextAutomaticSync
    )
  }

  func testLastAutomaticEventIgnoresUserTriggeredRuns() {
    let automatic = event(trigger: .appRefresh)
    let manual = event(trigger: .manual)
    let model = makeModel(status: SyncStatusSnapshot(recentEvents: [automatic, manual]))

    XCTAssertEqual(model.lastAutomaticEvent, automatic)
  }

  func testLastFullSweepComesFromTheFreshnessStore() async {
    let sweptAt = now.addingTimeInterval(-900)
    let model = makeModel(
      status: SyncStatusSnapshot(
        recentEvents: [
          sweepEvent(starvedMetrics: 2),
          event(trigger: .healthKitObserver),
        ]
      ),
      freshness: InMemoryMetricFreshnessStore(
        snapshot: MetricFreshnessSnapshot(lastFullSweepAt: sweptAt)
      )
    )

    await model.refreshSyncStatus()
    XCTAssertEqual(model.lastFullSweepAt, sweptAt)
  }

  func testLastFullSweepIsEmptyBeforeTheFirstSweep() async {
    let model = makeModel(
      status: SyncStatusSnapshot(recentEvents: [event(trigger: .healthKitObserver)]),
      freshness: InMemoryMetricFreshnessStore()
    )

    await model.refreshSyncStatus()

    XCTAssertNil(model.lastFullSweepAt)
  }

  private func configuration() -> AppConfiguration {
    AppConfiguration(
      baseURL: "https://ha.example.com",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps],
      backgroundSyncEnabled: true,
      backgroundSyncFrequency: .batterySaver
    )
  }

  private func makeModel(
    store: InMemoryConfigurationStore? = nil,
    publisher: StubAttemptPublisher? = nil,
    initial: AppConfiguration? = nil,
    status: SyncStatusSnapshot = SyncStatusSnapshot(),
    freshness: (any MetricFreshnessStore)? = nil
  ) -> AppModel {
    let fixedNow = now
    return AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: store ?? InMemoryConfigurationStore(configuration: configuration()),
      syncAttemptPublisher: publisher,
      metricFreshnessStore: freshness,
      initialConfiguration: initial ?? configuration(),
      isOnboardingComplete: true,
      initialSyncStatus: status,
      now: { fixedNow }
    )
  }

  private func sweepEvent(starvedMetrics: Int) -> SyncStatusEvent {
    SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: .appRefresh,
        outbound: nil,
        inbound: nil,
        startedAt: now,
        finishedAt: now,
        scopeReason: .sweepDue,
        requestedMetrics: 88,
        starvedMetrics: starvedMetrics
      )
    )
  }

  private func event(trigger: SyncTrigger) -> SyncStatusEvent {
    SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: trigger,
        outbound: nil,
        inbound: nil,
        startedAt: now,
        finishedAt: now
      )
    )
  }
}

private actor StubAttemptPublisher: SyncAttemptPublishing {
  private let error: (any Error)?
  private(set) var testCount = 0

  init(error: (any Error)?) {
    self.error = error
  }

  func publish(_ event: SyncStatusEvent, deadline: ExecutionDeadline?) -> SyncFailureCategory? {
    nil
  }

  func publishTest() throws {
    testCount += 1
    if let error { throw error }
  }
}
