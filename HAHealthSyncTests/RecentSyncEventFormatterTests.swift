import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class RecentSyncEventFormatterTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_788_035_400)

  func testSuccessfulSummaryDistinguishesChangesFromUnchangedItems() {
    let event = makeEvent(
      synchronizedMetrics: 1,
      skippedMetrics: 87,
      savedPairings: 0,
      skippedPairings: 1
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.summary(event),
      "Exported 1 · 87 unchanged · Imported 0 · 1 unchanged"
    )
  }

  func testLockedSummaryExplainsDeferredExportWithoutCallingItAFailure() {
    let event = makeEvent(
      synchronizedMetrics: 0,
      skippedMetrics: 88,
      savedPairings: 0,
      skippedPairings: 1,
      failures: [.init(metricID: nil, category: .deviceLocked)]
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.summary(event),
      "Export deferred — iPhone locked · Imported 0 · 1 unchanged"
    )
  }

  func testPartialFailureRetainsDirectionalCountsAndGroupsIssues() {
    let event = makeEvent(
      synchronizedMetrics: 5,
      skippedMetrics: 7,
      savedPairings: 0,
      skippedPairings: 1,
      failures: Array(
        repeating: SyncFailureSummary(metricID: .steps, category: .healthKit),
        count: 76
      )
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.summary(event),
      "Exported 5 · 7 unchanged · Imported 0 · 1 unchanged · Issues: 76 HealthKit"
    )
  }

  private func makeEvent(
    synchronizedMetrics: Int,
    skippedMetrics: Int,
    savedPairings: Int,
    skippedPairings: Int,
    failures: [SyncFailureSummary] = []
  ) -> SyncStatusEvent {
    SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: .background,
        outbound: SyncReport(
          trigger: .background,
          attemptedMetrics: synchronizedMetrics + skippedMetrics + failures.count,
          synchronizedMetrics: synchronizedMetrics,
          skippedMetrics: skippedMetrics,
          failures: failures,
          startedAt: date,
          finishedAt: date
        ),
        inbound: InboundSyncReport(
          trigger: .background,
          attemptedPairings: savedPairings + skippedPairings,
          savedPairings: savedPairings,
          skippedPairings: skippedPairings,
          failures: [],
          startedAt: date,
          finishedAt: date
        ),
        startedAt: date,
        finishedAt: date
      )
    )
  }

  func testTriggerTitlesNameTheActualLaunchSource() {
    XCTAssertEqual(RecentSyncEventFormatter.triggerTitle(.healthKitObserver), "Health update")
    XCTAssertEqual(RecentSyncEventFormatter.triggerTitle(.appRefresh), "Background refresh")
    XCTAssertEqual(RecentSyncEventFormatter.triggerTitle(.background), "Background")
    XCTAssertEqual(RecentSyncEventFormatter.triggerTitle(.shortcut), "Shortcut")
    XCTAssertEqual(RecentSyncEventFormatter.triggerTitle(.manual), "Sync now")
    XCTAssertEqual(RecentSyncEventFormatter.triggerTitle(.pullToRefresh), "Pull to refresh")
  }

  func testInterruptedEventsSayTheyDidNotFinish() {
    let event = SyncStatusEvent(
      interrupted: SyncInFlightAttempt(trigger: .appRefresh, startedAt: date, launchID: nil),
      throttledWakesBefore: 3
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.summary(event),
      "Interrupted before finishing · 3 skipped wake-ups"
    )
    XCTAssertEqual(RecentSyncEventFormatter.outcomeLabel(event), "Interrupted")
  }

  func testRunDetailsAppendDurationRequestsAndWakes() {
    let event = SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: .healthKitObserver,
        outbound: SyncReport(
          trigger: .healthKitObserver, attemptedMetrics: 3, synchronizedMetrics: 3,
          skippedMetrics: 0,
          failures: [], startedAt: date, finishedAt: date.addingTimeInterval(6), requestCount: 1
        ),
        inbound: nil,
        startedAt: date,
        finishedAt: date.addingTimeInterval(6)
      ),
      throttledWakesBefore: 1
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.summary(event),
      "Exported 3 · 0 unchanged · Imported 0 · 0 unchanged · 6 s · 1 request · 1 skipped wake-up"
    )
    XCTAssertEqual(RecentSyncEventFormatter.outcomeLabel(event), "Exported 3")
  }

  func testOutcomeLabelsForLockedFailedAndNothingNew() {
    let locked = makeEvent(
      synchronizedMetrics: 0, skippedMetrics: 1, savedPairings: 0, skippedPairings: 0,
      failures: [.init(metricID: nil, category: .deviceLocked)]
    )
    let failed = makeEvent(
      synchronizedMetrics: 0, skippedMetrics: 0, savedPairings: 0, skippedPairings: 0,
      failures: [.init(metricID: .steps, category: .offline)]
    )
    let quiet = makeEvent(
      synchronizedMetrics: 0, skippedMetrics: 2, savedPairings: 0, skippedPairings: 1)

    XCTAssertEqual(RecentSyncEventFormatter.outcomeLabel(locked), "iPhone locked")
    XCTAssertEqual(RecentSyncEventFormatter.outcomeLabel(failed), "Issues")
    XCTAssertEqual(RecentSyncEventFormatter.outcomeLabel(quiet), "Nothing new")
  }

  func testScopeSummaryNamesTheScopeAndHowMuchOfItTheRunChecked() {
    let scoped = makeScopedEvent(
      trigger: .healthKitObserver,
      reason: .changedTypes,
      requestedMetrics: 3,
      collectedMetrics: 3
    )
    let sweep = makeScopedEvent(
      trigger: .appRefresh,
      reason: .sweepDue,
      requestedMetrics: 88,
      collectedMetrics: 88,
      starvedMetrics: 0
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.scopeSummary(scoped),
      "Health update · 3 metrics checked"
    )
    XCTAssertEqual(
      RecentSyncEventFormatter.scopeSummary(sweep),
      "Full sweep · 88 metrics checked"
    )
  }

  func testScopeSummaryShowsATruncatedSweepAndItsStarvedMetrics() {
    let event = makeScopedEvent(
      trigger: .healthKitObserver,
      reason: .sweepDue,
      requestedMetrics: 88,
      collectedMetrics: 40,
      starvedMetrics: 2
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.scopeSummary(event),
      "Full sweep · 40 of 88 metrics checked · 2 starved"
    )
  }

  func testScopeSummaryReportsTheMetricsARunDeferred() {
    let event = makeScopedEvent(
      trigger: .healthKitObserver,
      reason: .sweepDue,
      requestedMetrics: 88,
      collectedMetrics: 40,
      starvedMetrics: 2,
      deferredMetrics: 48
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.scopeSummary(event),
      "Full sweep · 40 of 88 metrics checked · 48 deferred · 2 starved"
    )
  }

  func testScopeSummaryOmitsDeferredWhenTheRunDeferredNothing() {
    let event = makeScopedEvent(
      trigger: .appRefresh,
      reason: .sweepDue,
      requestedMetrics: 88,
      collectedMetrics: 88,
      starvedMetrics: 0,
      deferredMetrics: 0
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.scopeSummary(event),
      "Full sweep · 88 metrics checked"
    )
  }

  func testScopeSummaryOmitsTheCountWhenTheRunRecordedNone() {
    let event = SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: .appRefresh,
        outbound: nil,
        inbound: nil,
        startedAt: date,
        finishedAt: date,
        scopeReason: .sweepDue,
        requestedMetrics: 88
      )
    )

    XCTAssertEqual(RecentSyncEventFormatter.scopeSummary(event), "Full sweep")
  }

  func testEventsWithoutAResolvedScopeHaveNoScopeSummary() {
    let event = makeEvent(
      synchronizedMetrics: 1,
      skippedMetrics: 0,
      savedPairings: 0,
      skippedPairings: 0
    )

    XCTAssertNil(RecentSyncEventFormatter.scopeSummary(event))
  }

  private func makeScopedEvent(
    trigger: SyncTrigger,
    reason: SyncScopeReason,
    requestedMetrics: Int,
    collectedMetrics: Int,
    starvedMetrics: Int? = nil,
    deferredMetrics: Int = 0
  ) -> SyncStatusEvent {
    SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: trigger,
        outbound: SyncReport(
          trigger: trigger,
          attemptedMetrics: requestedMetrics,
          synchronizedMetrics: collectedMetrics,
          skippedMetrics: 0,
          failures: [],
          startedAt: date,
          finishedAt: date,
          collectedMetrics: collectedMetrics,
          deferredMetrics: deferredMetrics
        ),
        inbound: nil,
        startedAt: date,
        finishedAt: date,
        scopeReason: reason,
        requestedMetrics: requestedMetrics,
        starvedMetrics: starvedMetrics
      )
    )
  }

  func testIssueLabelDescribesDeadlineExceededAsOutOfBackgroundTime() {
    let event = makeEvent(
      synchronizedMetrics: 0, skippedMetrics: 0, savedPairings: 0, skippedPairings: 0,
      failures: [.init(metricID: nil, category: .deadlineExceeded)]
    )

    XCTAssertEqual(
      RecentSyncEventFormatter.summary(event),
      "Exported 0 · 0 unchanged · Imported 0 · 0 unchanged · Issues: out of background time"
    )
  }
}
