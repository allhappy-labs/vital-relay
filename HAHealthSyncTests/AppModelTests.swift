import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppModelTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_788_035_400)

  func testSyncNowUsesOneImmediateBidirectionalRun() async {
    let outbound = outboundReport(synchronized: 2)
    let inbound = inboundReport(saved: 1)
    let coordinator = FakeBidirectionalSyncCoordinator(
      outcome: .performed(
        BidirectionalSyncReport(
          trigger: .manual,
          outbound: outbound,
          inbound: inbound,
          startedAt: date,
          finishedAt: date
        )
      )
    )
    let model = AppModel(bidirectionalSyncCoordinator: coordinator)

    await model.syncNow()

    XCTAssertFalse(model.isSyncing)
    XCTAssertEqual(model.lastReport, outbound)
    XCTAssertEqual(model.lastInboundReport, inbound)
    XCTAssertEqual(model.lastSuccessfulSync, date)
    XCTAssertNil(model.currentError)
    let triggers = await coordinator.triggers
    XCTAssertEqual(triggers, [.manual])
  }

  func testSyncNowPublishesOnlyFailureCategory() async {
    let outbound = outboundReport(
      synchronized: 0,
      failures: [.init(metricID: .steps, category: .unauthorized)]
    )
    let model = AppModel(
      bidirectionalSyncCoordinator: FakeBidirectionalSyncCoordinator(
        outcome: .performed(
          BidirectionalSyncReport(
            trigger: .manual,
            outbound: outbound,
            inbound: nil,
            startedAt: date,
            finishedAt: date
          )
        )
      )
    )

    await model.syncNow()

    XCTAssertEqual(model.currentError, .unauthorized)
    XCTAssertNil(model.lastSuccessfulSync)
  }

  func testInboundFailurePreservesOutboundReportWithoutIdentifiers() async {
    let pairingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let inbound = inboundReport(
      saved: 0,
      failures: [.init(pairingID: pairingID, category: .validation)]
    )
    let model = AppModel(
      bidirectionalSyncCoordinator: FakeBidirectionalSyncCoordinator(
        outcome: .performed(
          BidirectionalSyncReport(
            trigger: .manual,
            outbound: outboundReport(synchronized: 2),
            inbound: inbound,
            startedAt: date,
            finishedAt: date
          )
        )
      )
    )

    await model.syncNow()

    XCTAssertEqual(model.currentError, .validation)
    XCTAssertEqual(model.lastReport?.synchronizedMetrics, 2)
    XCTAssertFalse(String(describing: model.currentError).contains(pairingID.uuidString))
    XCTAssertNil(model.lastSuccessfulSync)
  }

  func testSyncNowConfirmsWhatItSent() async {
    let model = AppModel(
      bidirectionalSyncCoordinator: FakeBidirectionalSyncCoordinator(
        outcome: .performed(
          BidirectionalSyncReport(
            trigger: .manual,
            outbound: outboundReport(synchronized: 2),
            inbound: inboundReport(saved: 1),
            startedAt: date,
            finishedAt: date
          )
        )
      )
    )

    await model.syncNow()

    XCTAssertEqual(model.manualSyncFeedback, .synced(3))
    model.clearManualSyncFeedback()
    XCTAssertNil(model.manualSyncFeedback)
  }

  /// A run that had nothing to send is the case the button used to look broken on: it returns at
  /// once and leaves `lastSuccessfulSync` alone, because that records the last time something was
  /// actually sent.
  func testSyncNowSaysUpToDateWhenNothingNeededSending() async {
    let model = AppModel(
      bidirectionalSyncCoordinator: FakeBidirectionalSyncCoordinator(
        outcome: .performed(
          BidirectionalSyncReport(
            trigger: .manual,
            outbound: outboundReport(synchronized: 0),
            inbound: inboundReport(saved: 0),
            startedAt: date,
            finishedAt: date
          )
        )
      )
    )

    await model.syncNow()

    XCTAssertEqual(model.manualSyncFeedback, .upToDate)
    XCTAssertNil(model.lastSuccessfulSync)
  }

  func testAFailedSyncConfirmsNothing() async {
    let model = AppModel(
      bidirectionalSyncCoordinator: FakeBidirectionalSyncCoordinator(
        outcome: .performed(
          BidirectionalSyncReport(
            trigger: .manual,
            outbound: outboundReport(
              synchronized: 0,
              failures: [.init(metricID: .steps, category: .unauthorized)]
            ),
            inbound: nil,
            startedAt: date,
            finishedAt: date
          )
        )
      )
    )

    await model.syncNow()

    XCTAssertNil(model.manualSyncFeedback)
    XCTAssertEqual(model.currentError, .unauthorized)
  }

  func testUnexpectedManualThrottleDoesNotPublishReports() async {
    let model = AppModel(
      bidirectionalSyncCoordinator: FakeBidirectionalSyncCoordinator(
        outcome: .throttled(nextEligibleAt: date)
      )
    )

    await model.syncNow()

    XCTAssertNil(model.lastReport)
    XCTAssertNil(model.lastInboundReport)
    XCTAssertFalse(model.isSyncing)
  }

  private func outboundReport(
    synchronized: Int,
    failures: [SyncFailureSummary] = []
  ) -> SyncReport {
    SyncReport(
      trigger: .manual,
      attemptedMetrics: max(synchronized, failures.count),
      synchronizedMetrics: synchronized,
      skippedMetrics: 0,
      failures: failures,
      startedAt: date,
      finishedAt: date
    )
  }

  private func inboundReport(
    saved: Int,
    failures: [InboundSyncFailure] = []
  ) -> InboundSyncReport {
    InboundSyncReport(
      trigger: .manual,
      attemptedPairings: max(saved, failures.count),
      savedPairings: saved,
      skippedPairings: 0,
      failures: failures,
      startedAt: date,
      finishedAt: date
    )
  }
}

private actor FakeBidirectionalSyncCoordinator: BidirectionalSyncCoordinating {
  private let outcome: BidirectionalSyncOutcome
  private(set) var triggers: [SyncTrigger] = []

  init(outcome: BidirectionalSyncOutcome) {
    self.outcome = outcome
  }

  func sync(trigger: SyncTrigger) -> BidirectionalSyncOutcome {
    triggers.append(trigger)
    return outcome
  }
}
