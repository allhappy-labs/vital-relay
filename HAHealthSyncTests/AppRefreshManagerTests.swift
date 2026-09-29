import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppRefreshManagerTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_788_035_400)

  func testReconcileSubmitsTheRequestedDate() {
    let scheduler = FakeAppRefreshScheduler()
    let manager = makeManager(scheduler: scheduler)
    manager.register()

    manager.reconcile(
      enabled: true, earliestBeginDate: now.addingTimeInterval(3_000), retryInterval: 900)

    XCTAssertEqual(scheduler.submissions.last?.date, now.addingTimeInterval(3_000))
    XCTAssertTrue(scheduler.cancellations.isEmpty)
  }

  func testReconcileWithoutDateUsesRetryInterval() {
    let scheduler = FakeAppRefreshScheduler()
    let manager = makeManager(scheduler: scheduler)
    manager.register()

    manager.reconcile(enabled: true, earliestBeginDate: nil, retryInterval: 300)

    XCTAssertEqual(scheduler.submissions.last?.date, now.addingTimeInterval(300))
  }

  func testDisablingCancelsWithoutSubmitting() {
    let scheduler = FakeAppRefreshScheduler()
    let manager = makeManager(scheduler: scheduler)
    manager.register()

    manager.reconcile(enabled: false, earliestBeginDate: nil, retryInterval: 900)

    XCTAssertEqual(scheduler.cancellations, [AppRefreshManager.identifier])
    XCTAssertTrue(scheduler.submissions.isEmpty)
  }

  func testLaunchWaitsForReadinessThenSyncsAndCompletesWithReportResult() async {
    let scheduler = FakeAppRefreshScheduler()
    let delegate = FakeRefreshDelegate(outcome: .performed(report(failure: nil)))
    delegate.readyDelay = .milliseconds(80)
    let manager = makeManager(scheduler: scheduler, delegate: delegate)
    manager.register()
    let task = FakeAppRefreshTask()

    scheduler.launch(task)
    try? await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(delegate.events, [])
    let completed = await waitUntil { !task.completions.isEmpty }

    XCTAssertTrue(completed)
    XCTAssertEqual(delegate.events, ["ready", "eligible", "sync"])
    XCTAssertEqual(task.completions, [true])
  }

  func testFailedReportCompletesAsFailure() async {
    let scheduler = FakeAppRefreshScheduler()
    let delegate = FakeRefreshDelegate(outcome: .performed(report(failure: .offline)))
    let manager = makeManager(scheduler: scheduler, delegate: delegate)
    manager.register()
    let task = FakeAppRefreshTask()

    scheduler.launch(task)
    _ = await waitUntil { !task.completions.isEmpty }

    XCTAssertEqual(task.completions, [false])
  }

  func testThrottledLaunchCompletesSuccessfully() async {
    let scheduler = FakeAppRefreshScheduler()
    let delegate = FakeRefreshDelegate(outcome: .throttled(nextEligibleAt: now))
    let manager = makeManager(scheduler: scheduler, delegate: delegate)
    manager.register()
    let task = FakeAppRefreshTask()

    scheduler.launch(task)
    _ = await waitUntil { !task.completions.isEmpty }

    XCTAssertEqual(task.completions, [true])
  }

  func testIneligibleLaunchCompletesWithoutSyncOrSubmission() async {
    let scheduler = FakeAppRefreshScheduler()
    let delegate = FakeRefreshDelegate(outcome: .throttled(nextEligibleAt: now))
    delegate.eligible = false
    let manager = makeManager(scheduler: scheduler, delegate: delegate)
    manager.register()
    let task = FakeAppRefreshTask()

    scheduler.launch(task)
    _ = await waitUntil { !task.completions.isEmpty }

    XCTAssertEqual(task.completions, [true])
    XCTAssertEqual(delegate.events, ["ready", "eligible"])
    XCTAssertTrue(scheduler.submissions.isEmpty)
  }

  func testExpirationResubmitsAtRetryIntervalAndCompletesExactlyOnce() async {
    let scheduler = FakeAppRefreshScheduler()
    let delegate = FakeRefreshDelegate(outcome: .performed(report(failure: nil)))
    delegate.syncDelay = .milliseconds(200)
    let manager = makeManager(scheduler: scheduler, delegate: delegate)
    manager.register()
    manager.reconcile(
      enabled: true, earliestBeginDate: now.addingTimeInterval(3_000), retryInterval: 600)
    let task = FakeAppRefreshTask()

    scheduler.launch(task)
    _ = await waitUntil { delegate.events.contains("sync") }
    task.expire()
    try? await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(task.completions, [false])
    XCTAssertEqual(scheduler.submissions.last?.date, now.addingTimeInterval(600))
  }

  func testMissingDelegateCompletesAsFailure() async {
    let scheduler = FakeAppRefreshScheduler()
    let manager = makeManager(scheduler: scheduler)
    manager.register()
    let task = FakeAppRefreshTask()

    scheduler.launch(task)
    _ = await waitUntil { !task.completions.isEmpty }

    XCTAssertEqual(task.completions, [false])
  }

  private func makeManager(
    scheduler: FakeAppRefreshScheduler,
    delegate: FakeRefreshDelegate? = nil
  ) -> AppRefreshManager {
    let fixedNow = now
    let manager = AppRefreshManager(scheduler: scheduler, now: { fixedNow })
    manager.launchDelegate = delegate
    retainedDelegate = delegate
    return manager
  }

  private var retainedDelegate: FakeRefreshDelegate?

  private func report(failure: SyncFailureCategory?) -> BidirectionalSyncReport {
    BidirectionalSyncReport(
      trigger: .appRefresh,
      outbound: SyncReport(
        trigger: .appRefresh,
        attemptedMetrics: 1,
        synchronizedMetrics: failure == nil ? 1 : 0,
        skippedMetrics: 0,
        failures: failure.map { [.init(metricID: nil, category: $0)] } ?? [],
        startedAt: now,
        finishedAt: now
      ),
      inbound: nil,
      startedAt: now,
      finishedAt: now
    )
  }
}

@MainActor
private final class FakeRefreshDelegate: AppRefreshLaunchDelegate {
  var eligible = true
  var readyDelay: Duration = .zero
  var syncDelay: Duration = .zero
  let outcome: BidirectionalSyncOutcome
  private(set) var events: [String] = []

  init(outcome: BidirectionalSyncOutcome) {
    self.outcome = outcome
  }

  func waitUntilReady() async {
    if readyDelay > .zero { try? await Task.sleep(for: readyDelay) }
    events.append("ready")
  }

  func isBackgroundWorkEligible() async -> Bool {
    events.append("eligible")
    return eligible
  }

  func performRefreshSync() async -> BidirectionalSyncOutcome {
    events.append("sync")
    if syncDelay > .zero { try? await Task.sleep(for: syncDelay) }
    return outcome
  }
}
