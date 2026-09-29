import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitObserverManagerTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_788_035_400)

  func testOneObserverCarriesEverySelectedTypeAndIsReplacedWhenTheSelectionChanges() async {
    let client = FakeHealthKitBackgroundClient()
    let manager = makeManager(client: client)

    await manager.reconcile(enabled: true, metrics: [.steps, .sleepDuration, .sleepREM])
    await manager.reconcile(enabled: true, metrics: [.steps, .sleepDuration, .sleepREM])

    let installed = await client.installedTypeSets
    let enabled = await client.enabled
    XCTAssertEqual(installed, [[.stepCount, .sleepAnalysis]])
    XCTAssertEqual(Set(enabled), [.stepCount, .sleepAnalysis])
    let removeCountAfterInstall = await client.removeObserversCount
    XCTAssertEqual(removeCountAfterInstall, 0)
    let states = await manager.registrationStates()
    XCTAssertEqual(states[.steps], .registered(at: date))
    XCTAssertEqual(states[.sleepDuration], .registered(at: date))
    XCTAssertEqual(states[.sleepREM], .registered(at: date))

    await manager.reconcile(enabled: true, metrics: [.sleepDuration])

    let reinstalled = await client.installedTypeSets
    let disabled = await client.disabled
    let reconciledStates = await manager.registrationStates()
    XCTAssertEqual(reinstalled, [[.stepCount, .sleepAnalysis], [.sleepAnalysis]])
    let removeCountAfterChange = await client.removeObserversCount
    XCTAssertEqual(removeCountAfterChange, 1)
    XCTAssertEqual(disabled, [.stepCount])
    XCTAssertEqual(reconciledStates[.steps], .disabled)
  }

  func testUnsupportedAndUnavailableTypesRecordValueFreeStates() async {
    let unavailableClient = FakeHealthKitBackgroundClient(isAvailable: false)
    let unavailableManager = makeManager(client: unavailableClient)
    await unavailableManager.reconcile(enabled: true, metrics: [.steps])
    let unavailableStates = await unavailableManager.registrationStates()
    XCTAssertEqual(unavailableStates[.steps], .unavailable(reason: .healthDataUnavailable))

    let failingClient = FakeHealthKitBackgroundClient(failingTypes: [.stepCount])
    let failingManager = makeManager(client: failingClient)
    await failingManager.reconcile(enabled: true, metrics: [.steps])
    let failingStates = await failingManager.registrationStates()
    XCTAssertEqual(failingStates[.steps], .failed(category: .healthKit, at: date))
  }

  func testChangedTypeReachesTheRunItScopes() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator()
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(120))

    let triggers = await coordinator.triggers
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(triggers, [.healthKitObserver])
    XCTAssertEqual(changedTypeSets, [[.stepCount]])
    XCTAssertEqual(completion.count, 1)
  }

  func testUnknownChangeReachesTheRunAsAnEmptyTypeSet() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator()
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps])
    let completion = CompletionCounter()

    await client.send(.changed, types: [], completion: completion)
    try? await Task.sleep(for: .milliseconds(120))

    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[]])
    XCTAssertEqual(completion.count, 1)
  }

  func testCallbackDuringARunStartsExactlyOneFollowUpRunCarryingTheNewType() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(delay: .milliseconds(150))
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(40))
    await client.send(.changed, types: [.bodyMass], completion: completion)
    try? await Task.sleep(for: .milliseconds(600))

    let changedTypeSets = await coordinator.changedTypeSets
    let maximumConcurrentCalls = await coordinator.maximumConcurrentCalls
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.bodyMass]])
    XCTAssertEqual(maximumConcurrentCalls, 1)
    XCTAssertEqual(completion.count, 2)
  }

  func testUnknownChangeDuringARunIsNotLost() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(delay: .milliseconds(150))
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(40))
    await client.send(.changed, types: [], completion: completion)
    try? await Task.sleep(for: .milliseconds(600))

    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount], []])
    XCTAssertEqual(completion.count, 2)
  }

  func testBurstInsideTheCoalescingWindowRunsOnceWithTheUnionOfTypes() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator()
    let manager = HealthKitObserverManager(
      client: client,
      coordinator: coordinator,
      statusStore: InMemorySyncStatusStore(),
      now: { Date(timeIntervalSince1970: 1_788_035_400) },
      executionLimit: .seconds(1),
      coalescingDelay: .milliseconds(80)
    )
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass, .sleepDuration])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    await client.send(.changed, types: [.bodyMass], completion: completion)
    await client.send(.changed, types: [.sleepAnalysis], completion: completion)
    try? await Task.sleep(for: .milliseconds(500))

    let changedTypeSets = await coordinator.changedTypeSets
    let maximumConcurrentCalls = await coordinator.maximumConcurrentCalls
    XCTAssertEqual(changedTypeSets, [[.stepCount, .bodyMass, .sleepAnalysis]])
    XCTAssertEqual(maximumConcurrentCalls, 1)
    XCTAssertEqual(completion.count, 3)
  }

  func testARefillingLedgerStopsAfterOneFollowUpAndReleasesTheCallbackEarly() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(delay: .milliseconds(200))
    let manager = makeManager(
      client: client,
      coordinator: coordinator,
      executionLimit: .seconds(3)
    )
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let firstCallback = CompletionCounter()
    let refillCallbacks = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: firstCallback)
    // Refills land throughout the first run (0-200ms) and its follow-up (200-400ms).
    for _ in 0..<6 {
      try? await Task.sleep(for: .milliseconds(50))
      await client.send(.changed, types: [.bodyMass], completion: refillCallbacks)
    }

    // Polled rather than read at whatever moment the wall clock has reached: the follow-up is
    // still running, and the first callback is already released rather than held across it.
    let releasedEarly = await waitUntilSettled {
      guard firstCallback.count == 1 else { return false }
      let progress = await coordinator.progress
      return progress.runs == 2 && !progress.isIdle
    }
    XCTAssertTrue(releasedEarly)

    let settled = await waitUntilSettled {
      guard refillCallbacks.count == 6 else { return false }
      return await coordinator.isIdle
    }
    XCTAssertTrue(settled)
    let totalRuns = await coordinator.triggers.count
    let maximumConcurrentCalls = await coordinator.maximumConcurrentCalls
    XCTAssertEqual(totalRuns, 2)
    XCTAssertEqual(maximumConcurrentCalls, 1)
  }

  func testCallbacksArrivingAsRunsFinishNeverOverlapTwoSyncs() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(delay: .milliseconds(1))
    let manager = makeManager(
      client: client,
      coordinator: coordinator,
      executionLimit: .seconds(3)
    )
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    // Sustained, concurrent, freshly arriving callbacks across hundreds of run boundaries. A run
    // slot cleared before an awaited check looks free to a callback delivered in that window,
    // and the manager would then have two syncs in flight at once.
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<4 {
        group.addTask {
          for _ in 0..<150 {
            await client.send(.changed, types: [.stepCount, .bodyMass], completion: completion)
            try? await Task.sleep(for: .microseconds(500))
          }
        }
      }
    }
    // `runThenFollowUp` releases a callback before it starts the follow-up run, so the last
    // completion is not the last run: the guard only means something once the coordinator is
    // idle as well.
    let settled = await waitUntilSettled {
      guard completion.count == 600 else { return false }
      return await coordinator.isIdle
    }

    XCTAssertTrue(settled)
    let maximumConcurrentCalls = await coordinator.maximumConcurrentCalls
    XCTAssertEqual(maximumConcurrentCalls, 1)
    XCTAssertEqual(completion.count, 600)
  }

  /// A guard on the hand-off contract, not a reproducer: measured at 0 strandings in 100 runs
  /// against the manager before the pending flag, because the callback reaches the manager actor
  /// after the finished run has already cleared its slot.
  func testAChangeRecordedAsARunFinishesStillGetsItsOwnRun() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator()
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let firstCallback = CompletionCounter()
    let handoffCallback = CompletionCounter()
    let observer = client.liveHandler

    // The second callback is delivered from inside the first one's completion handler: the
    // moment the run has finished and the manager is deciding whether to follow up. The
    // finished run is still in the slot there, so the callback joins it and schedules nothing
    // — the manager has to notice the change before it clears the slot, or it waits for the
    // next callback or the hourly sweep.
    await client.send(.changed, types: [.stepCount]) {
      firstCallback.increment()
      observer.send(.changed, types: [.bodyMass], completion: handoffCallback.increment)
    }

    let ranTheHandoff = await waitUntilSettled {
      await coordinator.changedTypeSets.count == 2
    }
    XCTAssertTrue(ranTheHandoff)
    let changedTypeSets = await coordinator.changedTypeSets
    let maximumConcurrentCalls = await coordinator.maximumConcurrentCalls
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.bodyMass]])
    XCTAssertEqual(maximumConcurrentCalls, 1)
    XCTAssertEqual(firstCallback.count, 1)
    XCTAssertEqual(handoffCallback.count, 1)
  }

  func testThrottledCallbackStillCompletesExactlyOnce() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(
      outcome: .throttled(nextEligibleAt: date.addingTimeInterval(900))
    )
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(30))

    let triggers = await coordinator.triggers
    XCTAssertEqual(triggers, [.healthKitObserver])
    XCTAssertEqual(completion.count, 1)
  }

  func testAThrottledRunPutsItsChangedTypesBackForTheNextRun() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(
      outcome: .throttled(nextEligibleAt: date.addingTimeInterval(900))
    )
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    let refused = await waitUntilSettled { await coordinator.changedTypeSets.count == 1 }
    XCTAssertTrue(refused)
    await coordinator.setOutcome(nil)
    await client.send(.changed, types: [.bodyMass], completion: completion)

    let ranAgain = await waitUntilSettled { await coordinator.changedTypeSets.count == 2 }
    XCTAssertTrue(ranAgain)
    // The cooldown refused the wake, so it consumed nothing: `stepCount` would otherwise wait for
    // staleness or the hourly sweep, up to an hour later.
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.stepCount, .bodyMass]])
    XCTAssertEqual(completion.count, 2)
  }

  func testAThrottledRunStartsNoFollowUpRun() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(
      delay: .milliseconds(150),
      outcome: .throttled(nextEligibleAt: date.addingTimeInterval(900))
    )
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(40))
    // Lands while the first run is in flight, which is what normally buys one follow-up run.
    await client.send(.changed, types: [.bodyMass], completion: completion)

    let settled = await waitUntilSettled {
      guard completion.count == 2 else { return false }
      return await coordinator.isIdle
    }
    XCTAssertTrue(settled)
    // A follow-up would be refused by the same cooldown the first run just hit, and counted as
    // another throttled wake iOS never granted.
    try? await Task.sleep(for: .milliseconds(250))
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount]])
  }

  func testARunCutShortByTheExecutionLimitPutsItsChangedTypesBack() async {
    let client = FakeHealthKitBackgroundClient()
    // The run never answers inside the limit, so the manager abandons it without knowing what
    // it covered — exactly what an 18 s budget does to a cold HealthKit.
    let coordinator = ObserverBidirectionalCoordinator(delay: .seconds(5))
    let manager = makeManager(
      client: client,
      coordinator: coordinator,
      executionLimit: .milliseconds(20)
    )
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    let cutShort = await waitUntilSettled { completion.count == 1 }
    XCTAssertTrue(cutShort)
    await client.send(.changed, types: [.bodyMass], completion: completion)

    let ranAgain = await waitUntilSettled { await coordinator.changedTypeSets.count == 2 }
    XCTAssertTrue(ranAgain)
    // HealthKit never re-announces a change it already reported, so a run that was cut short
    // before it could handle `stepCount` has to hand it back: otherwise nothing covers it until
    // the metric goes stale or the next full sweep, whichever comes first.
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.stepCount, .bodyMass]])
  }

  func testARunTheBudgetTruncatedPutsItsChangedTypesBack() async {
    let client = FakeHealthKitBackgroundClient()
    // The run answered, but left part of its scope untouched: the metrics it never reached keep
    // whatever freshness they had, so staleness alone would not bring them back either.
    let coordinator = ObserverBidirectionalCoordinator(
      outcome: .performed(observerReport(deferredMetrics: 1))
    )
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    let truncated = await waitUntilSettled { completion.count == 1 }
    XCTAssertTrue(truncated)
    await client.send(.changed, types: [.bodyMass], completion: completion)

    let ranAgain = await waitUntilSettled { await coordinator.changedTypeSets.count == 2 }
    XCTAssertTrue(ranAgain)
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.stepCount, .bodyMass]])
  }

  func testARunWhoseSendTheDeadlineAbandonedPutsItsChangedTypesBack() async {
    let client = FakeHealthKitBackgroundClient()
    // Collection finished, so nothing was deferred, but the budget ran out mid-send: the values
    // still on the phone recorded no check, and a metric checked minutes ago is not stale.
    let coordinator = ObserverBidirectionalCoordinator(
      outcome: .performed(
        observerReport(failures: [.init(metricID: .steps, category: .deadlineExceeded)])
      )
    )
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    let abandoned = await waitUntilSettled { completion.count == 1 }
    XCTAssertTrue(abandoned)
    await client.send(.changed, types: [.bodyMass], completion: completion)

    let ranAgain = await waitUntilSettled { await coordinator.changedTypeSets.count == 2 }
    XCTAssertTrue(ranAgain)
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.stepCount, .bodyMass]])
  }

  func testARunThatFailedAMetricStillConsumesItsChangedTypes() async {
    let client = FakeHealthKitBackgroundClient()
    // The run reached everything and one metric's query failed. That metric records no check, so
    // it is stale and the next run covers it; keeping its type in the ledger would pin every
    // later scoped run to it and to every other metric of its type.
    let coordinator = ObserverBidirectionalCoordinator(
      outcome: .performed(
        observerReport(failures: [.init(metricID: .steps, category: .healthKit)])
      )
    )
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    let ran = await waitUntilSettled { completion.count == 1 }
    XCTAssertTrue(ran)
    await client.send(.changed, types: [.bodyMass], completion: completion)

    let ranAgain = await waitUntilSettled { await coordinator.changedTypeSets.count == 2 }
    XCTAssertTrue(ranAgain)
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.bodyMass]])
  }

  func testARunThatCoveredItsScopeConsumesItsChangedTypes() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator()
    let manager = makeManager(client: client, coordinator: coordinator)
    await manager.reconcile(enabled: true, metrics: [.steps, .bodyMass])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    let ran = await waitUntilSettled { completion.count == 1 }
    XCTAssertTrue(ran)
    await client.send(.changed, types: [.bodyMass], completion: completion)

    let ranAgain = await waitUntilSettled { await coordinator.changedTypeSets.count == 2 }
    XCTAssertTrue(ranAgain)
    // A run that reached everything it was scoped to has handled those types; handing them back
    // would make every later scoped run re-query metrics that are already up to date.
    let changedTypeSets = await coordinator.changedTypeSets
    XCTAssertEqual(changedTypeSets, [[.stepCount], [.bodyMass]])
  }

  func testCompletionHandlerRunsAtTheLimitEvenWhenSyncIgnoresCancellation() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = UncancellableCoordinator(duration: 1.0)
    let manager = HealthKitObserverManager(
      client: client,
      coordinator: coordinator,
      statusStore: InMemorySyncStatusStore(),
      now: { Date(timeIntervalSince1970: 1_788_035_400) },
      executionLimit: .milliseconds(50),
      coalescingDelay: .zero
    )
    await manager.reconcile(enabled: true, metrics: [.steps])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(completion.count, 1)
  }

  func testStopAllCancelsInFlightRunAndReturnsCompletionPromptly() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = CancellationRecordingCoordinator()
    let manager = HealthKitObserverManager(
      client: client,
      coordinator: coordinator,
      statusStore: InMemorySyncStatusStore(),
      now: { Date(timeIntervalSince1970: 1_788_035_400) },
      executionLimit: .seconds(10),
      coalescingDelay: .zero
    )
    await manager.reconcile(enabled: true, metrics: [.steps])
    let completion = CompletionCounter()

    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(50))
    await manager.stopAll()
    try? await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(completion.count, 1)
    let observedCancellation = await coordinator.wasCancelledAfterSleep
    XCTAssertTrue(observedCancellation)
  }

  func testLockedDatabaseKeepsObserverRegisteredAndShortExecutionStillCompletes() async {
    let client = FakeHealthKitBackgroundClient()
    let coordinator = ObserverBidirectionalCoordinator(delay: .seconds(1))
    let manager = makeManager(
      client: client,
      coordinator: coordinator,
      executionLimit: .milliseconds(10)
    )
    await manager.reconcile(enabled: true, metrics: [.steps])
    let completion = CompletionCounter()

    await client.send(.databaseInaccessible, types: [], completion: completion)
    await client.send(.changed, types: [.stepCount], completion: completion)
    try? await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(completion.count, 2)
    let removeCount = await client.removeObserversCount
    XCTAssertEqual(removeCount, 0)
    let states = await manager.registrationStates()
    XCTAssertEqual(states[.steps], .registered(at: date))
  }

  func testStopAllRemovesTheObserverAndDisablesRegistration() async {
    let client = FakeHealthKitBackgroundClient()
    let manager = makeManager(client: client)
    await manager.reconcile(enabled: true, metrics: [.steps])

    await manager.stopAll()

    let disabled = await client.disabled
    let states = await manager.registrationStates()
    let removeCount = await client.removeObserversCount
    XCTAssertEqual(removeCount, 1)
    XCTAssertEqual(disabled, [.stepCount])
    XCTAssertEqual(states[.steps], .disabled)
  }

  /// Polls until the work under test has settled, so a test waits for what the manager did
  /// rather than for a fixed interval that is either flaky or slow.
  private func waitUntilSettled(
    timeout: Duration = .seconds(5),
    _ condition: () async -> Bool
  ) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: timeout)
    while clock.now < end {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
  }

  private func makeManager(
    client: FakeHealthKitBackgroundClient,
    coordinator: ObserverBidirectionalCoordinator = ObserverBidirectionalCoordinator(),
    executionLimit: Duration = .seconds(1)
  ) -> HealthKitObserverManager {
    let fixedDate = date
    return HealthKitObserverManager(
      client: client,
      coordinator: coordinator,
      statusStore: InMemorySyncStatusStore(),
      now: { fixedDate },
      executionLimit: executionLimit,
      coalescingDelay: .zero
    )
  }
}

final class ChangedTypeLedgerTests: XCTestCase {
  func testDrainReturnsAndClearsTheUnionOfEveryRecordedSet() async {
    let ledger = ChangedTypeLedger()
    let startsEmpty = await ledger.isEmpty
    XCTAssertTrue(startsEmpty)

    await ledger.record([.stepCount])
    await ledger.record([.bodyMass, .stepCount])

    let isEmptyAfterRecording = await ledger.isEmpty
    XCTAssertFalse(isEmptyAfterRecording)
    let drained = await ledger.drain()
    XCTAssertEqual(drained, [.stepCount, .bodyMass])
    let isEmptyAfterDrain = await ledger.isEmpty
    XCTAssertTrue(isEmptyAfterDrain)
    let drainedAgain = await ledger.drain()
    XCTAssertEqual(drainedAgain, [])
  }

  func testAnUnknownChangeDrainsAsTheUnknownMarkerEvenAlongsideNamedTypes() async {
    let ledger = ChangedTypeLedger()

    await ledger.record([.stepCount])
    await ledger.record([])

    // The empty set is what the scope policy reads as an unknown change, so the wake becomes a
    // full sweep instead of a run scoped to `stepCount` that never looks at what went unnamed.
    let drained = await ledger.drain()
    XCTAssertEqual(drained, [])
    let isEmptyAfterDrain = await ledger.isEmpty
    XCTAssertTrue(isEmptyAfterDrain)
    let drainedAgain = await ledger.drain()
    XCTAssertEqual(drainedAgain, [])
  }

  func testAnUnknownChangeIsPendingEvenThoughItNamesNoTypes() async {
    let ledger = ChangedTypeLedger()

    await ledger.record([])

    let isEmptyAfterRecording = await ledger.isEmpty
    XCTAssertFalse(isEmptyAfterRecording)
    let drained = await ledger.drain()
    XCTAssertEqual(drained, [])
    let isEmptyAfterDrain = await ledger.isEmpty
    XCTAssertTrue(isEmptyAfterDrain)
  }
}

/// What a run that answered for its whole scope reports: it deferred nothing, so the changed
/// types it drained are handled and must not come back. `deferredMetrics` models the budget
/// cutting a run short after it started sending.
private func observerReport(
  trigger: SyncTrigger = .healthKitObserver,
  deferredMetrics: Int = 0,
  failures: [SyncFailureSummary] = []
) -> BidirectionalSyncReport {
  let date = Date(timeIntervalSince1970: 1_788_035_400)
  return BidirectionalSyncReport(
    trigger: trigger,
    outbound: SyncReport(
      trigger: trigger,
      attemptedMetrics: 1,
      synchronizedMetrics: 1,
      skippedMetrics: 0,
      failures: failures,
      startedAt: date,
      finishedAt: date,
      collectedMetrics: 1,
      deferredMetrics: deferredMetrics
    ),
    inbound: nil,
    startedAt: date,
    finishedAt: date
  )
}

private actor FakeHealthKitBackgroundClient: HealthKitBackgroundDeliveryClient {
  let isAvailable: Bool
  let failingTypes: Set<HealthObjectTypeID>
  private(set) var installedTypeSets: [Set<HealthObjectTypeID>] = []
  private(set) var enabled: [HealthObjectTypeID] = []
  private(set) var removeObserversCount = 0
  private(set) var disabled: [HealthObjectTypeID] = []
  /// The installed handler, callable without awaiting this actor, so a test can deliver a
  /// callback from inside a completion handler — where a real HealthKit callback can land.
  nonisolated let liveHandler = ObserverHandlerBox()
  private var handler: HealthKitObserverUpdate?

  init(isAvailable: Bool = true, failingTypes: Set<HealthObjectTypeID> = []) {
    self.isAvailable = isAvailable
    self.failingTypes = failingTypes
  }

  func isHealthDataAvailable() -> Bool { isAvailable }

  func installObserver(
    for types: Set<HealthObjectTypeID>,
    update: @escaping HealthKitObserverUpdate
  ) throws {
    // Mirrors the real client: installing over a live query would observe a stale type set.
    if handler != nil { throw Failure.alreadyInstalled }
    if !failingTypes.isDisjoint(with: types) { throw Failure.expected }
    installedTypeSets.append(types)
    handler = update
    liveHandler.set(update)
  }

  func removeObservers() {
    removeObserversCount += 1
    handler = nil
    liveHandler.set(nil)
  }

  func enableBackgroundDelivery(for type: HealthObjectTypeID) throws {
    if failingTypes.contains(type) { throw Failure.expected }
    enabled.append(type)
  }

  func disableBackgroundDelivery(for type: HealthObjectTypeID) {
    disabled.append(type)
  }

  func send(
    _ event: HealthKitObserverEvent,
    types: Set<HealthObjectTypeID>,
    completion: CompletionCounter
  ) {
    handler?(event, types, completion.increment)
  }

  func send(
    _ event: HealthKitObserverEvent,
    types: Set<HealthObjectTypeID>,
    completion: @escaping @Sendable () -> Void
  ) {
    handler?(event, types, completion)
  }

  private enum Failure: Error {
    case expected
    case alreadyInstalled
  }
}

private actor ObserverBidirectionalCoordinator: BidirectionalSyncCoordinating {
  private let delay: Duration
  private var outcome: BidirectionalSyncOutcome?
  private(set) var triggers: [SyncTrigger] = []
  private(set) var changedTypeSets: [Set<HealthObjectTypeID>] = []
  private(set) var maximumConcurrentCalls = 0
  private var concurrentCalls = 0

  /// Whether no run is in flight, so a test can settle on the manager having finished rather
  /// than on the callbacks having been released.
  var isIdle: Bool { concurrentCalls == 0 }

  /// How many runs have started and whether one is still going, read in one actor step so a poll
  /// cannot see the count from before a run started and the idleness from after it finished.
  var progress: (runs: Int, isIdle: Bool) { (triggers.count, concurrentCalls == 0) }

  init(
    delay: Duration = .zero,
    outcome: BidirectionalSyncOutcome? = nil
  ) {
    self.delay = delay
    self.outcome = outcome
  }

  /// Switches the outcome every later run returns, so a test can let a cooldown lapse.
  func setOutcome(_ outcome: BidirectionalSyncOutcome?) {
    self.outcome = outcome
  }

  func sync(trigger: SyncTrigger) async -> BidirectionalSyncOutcome {
    await sync(trigger: trigger, changedTypes: [])
  }

  func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>
  ) async -> BidirectionalSyncOutcome {
    triggers.append(trigger)
    changedTypeSets.append(changedTypes)
    concurrentCalls += 1
    maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
    defer { concurrentCalls -= 1 }
    if delay > .zero { try? await Task.sleep(for: delay) }
    if let outcome { return outcome }
    return .performed(observerReport(trigger: trigger))
  }
}

private actor UncancellableCoordinator: BidirectionalSyncCoordinating {
  let duration: TimeInterval

  init(duration: TimeInterval) {
    self.duration = duration
  }

  func sync(trigger: SyncTrigger) async -> BidirectionalSyncOutcome {
    let duration = duration
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
        continuation.resume()
      }
    }
    return .performed(observerReport(trigger: trigger))
  }
}

private actor CancellationRecordingCoordinator: BidirectionalSyncCoordinating {
  private(set) var wasCancelledAfterSleep = false

  func sync(trigger: SyncTrigger) async -> BidirectionalSyncOutcome {
    try? await Task.sleep(for: .seconds(5))
    wasCancelledAfterSleep = Task.isCancelled
    return .performed(observerReport(trigger: trigger))
  }
}

/// Holds the installed observer handler outside any actor, so a callback can be delivered from
/// synchronous code such as a completion handler.
private final class ObserverHandlerBox: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: HealthKitObserverUpdate?

  func set(_ handler: HealthKitObserverUpdate?) {
    lock.withLock { self.handler = handler }
  }

  func send(
    _ event: HealthKitObserverEvent,
    types: Set<HealthObjectTypeID>,
    completion: @escaping @Sendable () -> Void
  ) {
    lock.withLock { handler }?(event, types, completion)
  }
}

private final class CompletionCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storedCount = 0

  var count: Int { lock.withLock { storedCount } }

  func increment() {
    lock.withLock { storedCount += 1 }
  }
}
