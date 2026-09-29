import Foundation
import Testing

@testable import HealthSyncCore

@Suite("App Intent sync handler")
struct AppIntentSyncHandlerTests {
  private let date = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Uses one shared bidirectional run with the Shortcut trigger")
  func success() async {
    let coordinator = RecordingBidirectionalCoordinator(
      outcome: .performed(report(synchronized: 2, saved: 1))
    )
    let handler = AppIntentSyncHandler(coordinator: coordinator)

    let result = await handler.synchronize()

    #expect(
      result
        == .init(
          succeeded: true,
          synchronizedMetricCount: 2,
          synchronizedPairingCount: 1,
          failureCategory: nil
        )
    )
    #expect(await coordinator.triggers == [.shortcut])
  }

  @Test("A directional failure remains privacy safe")
  func failure() async throws {
    let pairingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let coordinator = RecordingBidirectionalCoordinator(
      outcome: .performed(
        report(
          synchronized: 2,
          saved: 0,
          inboundFailures: [.init(pairingID: pairingID, category: .validation)]
        )
      )
    )
    let result = await AppIntentSyncHandler(coordinator: coordinator).synchronize()
    let text = try #require(String(data: JSONEncoder().encode(result), encoding: .utf8))

    #expect(result.failureCategory == .validation)
    #expect(result.synchronizedMetricCount == 2)
    #expect(!text.contains(pairingID.uuidString))
    #expect(!text.contains("entity"))
    #expect(!text.contains("value"))
  }

  @Test("Setup failures map directly without directional results")
  func setupFailure() async {
    let coordinator = RecordingBidirectionalCoordinator(
      outcome: .performed(
        BidirectionalSyncReport(
          trigger: .shortcut,
          outbound: nil,
          inbound: nil,
          setupFailureCategory: .configuration,
          startedAt: date,
          finishedAt: date
        )
      )
    )

    let result = await AppIntentSyncHandler(coordinator: coordinator).synchronize()

    #expect(
      result
        == .init(
          succeeded: false,
          synchronizedMetricCount: 0,
          failureCategory: .configuration
        )
    )
  }

  @Test("A completed run with nothing new succeeds quietly")
  func noSavedData() async {
    let coordinator = RecordingBidirectionalCoordinator(
      outcome: .performed(report(synchronized: 0, saved: 0))
    )

    let result = await AppIntentSyncHandler(coordinator: coordinator).synchronize()

    #expect(
      result
        == .init(
          succeeded: true,
          synchronizedMetricCount: 0,
          synchronizedPairingCount: 0,
          failureCategory: nil
        )
    )
  }

  @Test("A locked device is its own result and keeps import counts")
  func lockedDevice() async {
    let lockedReport = BidirectionalSyncReport(
      trigger: .shortcut,
      outbound: SyncReport(
        trigger: .shortcut, attemptedMetrics: 2, synchronizedMetrics: 0, skippedMetrics: 2,
        failures: [.init(metricID: nil, category: .deviceLocked)], startedAt: date, finishedAt: date
      ),
      inbound: InboundSyncReport(
        trigger: .shortcut, attemptedPairings: 1, savedPairings: 1, skippedPairings: 0,
        failures: [], startedAt: date, finishedAt: date
      ),
      startedAt: date,
      finishedAt: date
    )
    let coordinator = RecordingBidirectionalCoordinator(outcome: .performed(lockedReport))

    let result = await AppIntentSyncHandler(coordinator: coordinator).synchronize()

    #expect(
      result
        == .init(
          succeeded: false,
          synchronizedMetricCount: 0,
          synchronizedPairingCount: 1,
          failureCategory: .deviceLocked
        )
    )
  }

  @Test("A locked device mixed with other failures reports the other failure")
  func lockedDeviceWithOtherFailures() async {
    let mixedReport = BidirectionalSyncReport(
      trigger: .shortcut,
      outbound: SyncReport(
        trigger: .shortcut, attemptedMetrics: 2, synchronizedMetrics: 0, skippedMetrics: 1,
        failures: [
          .init(metricID: nil, category: .deviceLocked),
          .init(metricID: .steps, category: .offline),
        ],
        startedAt: date, finishedAt: date
      ),
      inbound: nil,
      startedAt: date,
      finishedAt: date
    )
    let coordinator = RecordingBidirectionalCoordinator(outcome: .performed(mixedReport))

    let result = await AppIntentSyncHandler(coordinator: coordinator).synchronize()

    #expect(result.succeeded == false)
    #expect(result.failureCategory == .offline)
  }

  @Test("Shortcut throttling fails closed")
  func unexpectedThrottle() async {
    let coordinator = RecordingBidirectionalCoordinator(
      outcome: .throttled(nextEligibleAt: date)
    )

    let result = await AppIntentSyncHandler(coordinator: coordinator).synchronize()

    #expect(result.succeeded == false)
    #expect(result.failureCategory == .unknown)
  }

  @Test("A locked Shortcut returns a purchase result before sync starts")
  func purchaseRequired() async throws {
    let base = RecordingBidirectionalCoordinator(outcome: .throttled(nextEligibleAt: date))
    let handler = AppIntentSyncHandler(
      coordinator: PaidSyncCoordinator(base: base, access: MutableShortcutAccess())
    )

    let result = await handler.synchronize()
    let encoded = try #require(String(data: JSONEncoder().encode(result), encoding: .utf8))

    #expect(result.requiresPurchase)
    #expect(!result.succeeded)
    #expect(result.synchronizedMetricCount == 0)
    #expect(result.synchronizedPairingCount == 0)
    #expect(result.failureCategory == nil)
    #expect(await base.triggers.isEmpty)
    #expect(!encoded.contains("fixture-secret"))
    #expect(!encoded.contains("fixture-token"))
    #expect(!encoded.contains("8421"))
  }

  private func report(
    synchronized: Int,
    saved: Int,
    inboundFailures: [InboundSyncFailure] = []
  ) -> BidirectionalSyncReport {
    BidirectionalSyncReport(
      trigger: .shortcut,
      outbound: SyncReport(
        trigger: .shortcut,
        attemptedMetrics: 2,
        synchronizedMetrics: synchronized,
        skippedMetrics: 0,
        failures: [],
        startedAt: date,
        finishedAt: date
      ),
      inbound: InboundSyncReport(
        trigger: .shortcut,
        attemptedPairings: max(saved, inboundFailures.count),
        savedPairings: saved,
        skippedPairings: 0,
        failures: inboundFailures,
        startedAt: date,
        finishedAt: date
      ),
      startedAt: date,
      finishedAt: date
    )
  }
}

private actor MutableShortcutAccess: PaidFeatureAccessing {
  func accessState() -> PaidAccessState { .locked }
}

private actor RecordingBidirectionalCoordinator: BidirectionalSyncCoordinating {
  let outcome: BidirectionalSyncOutcome
  private(set) var triggers: [SyncTrigger] = []

  init(outcome: BidirectionalSyncOutcome) {
    self.outcome = outcome
  }

  func sync(trigger: SyncTrigger) -> BidirectionalSyncOutcome {
    triggers.append(trigger)
    return outcome
  }
}
