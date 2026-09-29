import Foundation
import HealthKit
import HealthSyncCore

enum HealthKitObserverEvent: Sendable, Equatable {
  case changed
  case databaseInaccessible
  case failed
}

/// What one observer callback reports: the event, the object types HealthKit named as changed,
/// and the completion handler that must run exactly once. An empty type set means HealthKit
/// could not name what changed, which the scope policy reads as an unknown change.
typealias HealthKitObserverUpdate =
  @Sendable (
    HealthKitObserverEvent,
    Set<HealthObjectTypeID>,
    @escaping @Sendable () -> Void
  ) -> Void

protocol HealthKitBackgroundDeliveryClient: Sendable {
  func isHealthDataAvailable() async -> Bool
  /// Installs a single observer covering every type. One query keeps the changed set in one
  /// callback, so a wake that touched several types is one run scoped to all of them.
  ///
  /// Throws `HealthKitObserverError.observerAlreadyInstalled` when one is already installed:
  /// silently keeping the old query would observe a stale type set for the rest of the process.
  func installObserver(
    for types: Set<HealthObjectTypeID>,
    update: @escaping HealthKitObserverUpdate
  ) async throws
  func removeObservers() async
  func enableBackgroundDelivery(for type: HealthObjectTypeID) async throws
  func disableBackgroundDelivery(for type: HealthObjectTypeID) async
}

/// The HealthKit object types that have changed since the last run drained them.
///
/// In-memory only: a process that dies loses it, and the next launch's first run is a full
/// sweep, so nothing is missed.
actor ChangedTypeLedger {
  private var namedTypes: Set<HealthObjectTypeID> = []
  /// Whether a change HealthKit declined to name has been recorded since the last drain.
  private var hasUnknownChange = false
  private var hasPendingChange = false

  /// Whether nothing has been recorded since the last drain.
  ///
  /// A change that names no types is still pending: HealthKit reporting nil is an unknown
  /// change that must become a full sweep, and tracking only the named types would drop it.
  var isEmpty: Bool { !hasPendingChange }

  func record(_ types: Set<HealthObjectTypeID>) {
    if types.isEmpty {
      hasUnknownChange = true
    } else {
      namedTypes.formUnion(types)
    }
    hasPendingChange = true
  }

  /// The change signal for the next run, cleared as it is handed over.
  ///
  /// An unknown change recorded since the last drain wins over any named types drained with it:
  /// the empty set it returns is the marker `SyncScopePolicy` reads as an unknown change, and
  /// the full sweep that follows covers the named types anyway. Returning the named types
  /// instead would claim the whole wake was understood and leave the unnamed change unswept
  /// until the next hourly sweep.
  func drain() -> Set<HealthObjectTypeID> {
    defer {
      namedTypes.removeAll()
      hasUnknownChange = false
      hasPendingChange = false
    }
    return hasUnknownChange ? [] : namedTypes
  }
}

enum HealthKitObserverError: Error, Equatable, Sendable {
  /// Installing over a live query would leave it observing a stale type set; remove first.
  case observerAlreadyInstalled
}

actor HealthKitObserverManager: BackgroundSyncManaging {
  private struct ActiveWork {
    let id: UUID
    /// Reports whether the coordinator's cooldown refused the run, which is what decides against
    /// an in-wake follow-up: the follow-up would be refused by the same cooldown.
    let task: Task<Bool, Never>
  }

  private let client: any HealthKitBackgroundDeliveryClient
  private let coordinator: any BidirectionalSyncCoordinating
  private let statusStore: any SyncStatusStore
  private let now: @Sendable () -> Date
  private let executionLimit: Duration
  private let coalescingDelay: Duration
  private let ledger = ChangedTypeLedger()

  private var metricsByType: [HealthObjectTypeID: Set<MetricID>] = [:]
  /// The types the single installed observer query covers.
  private var observedTypes: Set<HealthObjectTypeID> = []
  /// The types background delivery is switched on for, which stays a per-type registration.
  private var deliveryTypes: Set<HealthObjectTypeID> = []
  private var states: [MetricID: BackgroundRegistrationState] = [:]
  private var activeWork: ActiveWork?
  /// Whether a callback has *arrived* with a change no run has drained yet. Narrower than "the
  /// ledger is non-empty" on purpose: a run that hands back what it could not handle refills the
  /// ledger without this flag, because that is not a new arrival and must not buy a follow-up
  /// run. Only the decision to start a follow-up reads this; what a run covers comes from the
  /// ledger itself.
  ///
  /// A run reads this synchronously as it finishes, in the same actor step that clears the run
  /// slot. Asking the ledger there means awaiting it, and a change recorded during that await
  /// lands after the answer: the callback joins the finished run it can still see, and the run
  /// decides there is nothing to follow up. The change would then sit in the ledger with no run
  /// scheduled until the next callback or the hourly sweep.
  private var hasPendingChanges = false

  init(
    client: any HealthKitBackgroundDeliveryClient,
    coordinator: any BidirectionalSyncCoordinating,
    statusStore: any SyncStatusStore,
    now: @escaping @Sendable () -> Date = { Date() },
    executionLimit: Duration = .seconds(20),
    coalescingDelay: Duration = .milliseconds(250)
  ) {
    self.client = client
    self.coordinator = coordinator
    self.statusStore = statusStore
    self.now = now
    self.executionLimit = executionLimit
    self.coalescingDelay = coalescingDelay
  }

  func reconcile(enabled: Bool, metrics: Set<MetricID>) async {
    guard enabled else {
      await stopAll()
      return
    }
    guard await client.isHealthDataAvailable() else {
      await stopObserving()
      await stopBackgroundDelivery()
      for metric in metrics {
        await setState(.unavailable(reason: .healthDataUnavailable), for: metric)
      }
      return
    }

    let selectedDefinitions = MetricRegistry.selectable.filter {
      metrics.contains($0.id) && $0.supportsBackgroundDelivery
    }
    let selectedMetricIDs = Set(selectedDefinitions.map(\.id))
    for metric in metrics.subtracting(selectedMetricIDs) {
      await setState(.unavailable(reason: .backgroundDeliveryUnavailable), for: metric)
    }

    let newMetricsByType = Dictionary(grouping: selectedDefinitions, by: \.healthObjectType)
      .mapValues { Set($0.map(\.id)) }
    let desiredTypes = Set(newMetricsByType.keys)

    for type in deliveryTypes.subtracting(desiredTypes) {
      await client.disableBackgroundDelivery(for: type)
      deliveryTypes.remove(type)
    }

    let deselected = Set(states.keys).subtracting(selectedMetricIDs)
    for metric in deselected {
      await setState(.disabled, for: metric)
    }
    metricsByType = newMetricsByType

    // One query covers exactly the selected types, so any change to that set rebuilds it.
    if observedTypes != desiredTypes {
      await stopObserving()
      guard await installObserver(for: desiredTypes) else { return }
    }

    for type in desiredTypes {
      guard !deliveryTypes.contains(type) else { continue }
      do {
        try await client.enableBackgroundDelivery(for: type)
        deliveryTypes.insert(type)
        for metric in newMetricsByType[type] ?? [] {
          await setState(.registered(at: now()), for: metric)
        }
      } catch {
        await client.disableBackgroundDelivery(for: type)
        for metric in newMetricsByType[type] ?? [] {
          await setState(.failed(category: .healthKit, at: now()), for: metric)
        }
      }
    }

    for type in deliveryTypes {
      for metric in newMetricsByType[type] ?? [] where states[metric] == nil {
        await setState(.registered(at: now()), for: metric)
      }
    }
  }

  func stopAll() async {
    let knownMetrics = Set(states.keys).union(metricsByType.values.flatMap { $0 })
    await stopObserving()
    await stopBackgroundDelivery()
    metricsByType = [:]
    for metric in knownMetrics {
      await setState(.disabled, for: metric)
    }
  }

  func registrationStates() -> [MetricID: BackgroundRegistrationState] {
    states
  }

  /// Installs the single query, reporting whether the selection is now observed. A selection
  /// that resolves to no types at all needs no query and is not a failure.
  private func installObserver(for types: Set<HealthObjectTypeID>) async -> Bool {
    guard !types.isEmpty else { return false }
    do {
      try await client.installObserver(for: types) { [weak self] event, changedTypes, completion in
        guard let self else {
          completion()
          return
        }
        Task {
          await self.receive(event: event, changedTypes: changedTypes, completion: completion)
        }
      }
      observedTypes = types
      return true
    } catch {
      // A throwing install leaves no query behind, so only the delivery registrations of the
      // selection that cannot be observed need unwinding.
      await stopBackgroundDelivery()
      for metric in metricsByType.values.flatMap({ $0 }) {
        await setState(.failed(category: .healthKit, at: now()), for: metric)
      }
      return false
    }
  }

  /// Stops the single query and drops the work and pending changes it produced.
  private func stopObserving() async {
    // A non-empty `observedTypes` is exactly "a query is installed": it is only ever set by a
    // successful install, and an install always covers at least one type.
    if !observedTypes.isEmpty {
      await client.removeObservers()
      observedTypes = []
    }
    if let work = activeWork {
      // The slot is cleared before the wait, so the run handing over cannot start a follow-up
      // for an observer that is going away. The wait itself is what makes the drain below
      // final: a cancelled run puts the change signal it drained back as it ends, and a stop
      // that did not outlive that would leave those types behind for a query that is gone.
      activeWork = nil
      work.task.cancel()
      _ = await work.task.value
    }
    _ = await ledger.drain()
    hasPendingChanges = false
  }

  private func stopBackgroundDelivery() async {
    for type in deliveryTypes {
      await client.disableBackgroundDelivery(for: type)
    }
    deliveryTypes.removeAll()
  }

  /// Every branch completes the callback exactly once. The completion handler is called
  /// explicitly rather than deferred because the changed branch has to release HealthKit at a
  /// precise moment: when its own run is done, before any follow-up.
  private func receive(
    event: HealthKitObserverEvent,
    changedTypes: Set<HealthObjectTypeID>,
    completion: @escaping @Sendable () -> Void
  ) async {
    guard !metricsByType.isEmpty else {
      completion()
      return
    }

    switch event {
    case .changed:
      // Only types this manager observes can scope a run; anything else would claim the change
      // was understood when it covers nothing. Dropping it leaves an unknown change instead.
      await ledger.record(changedTypes.intersection(metricsByType.keys))
      // Recorded before the active run is read, so a run finishing in this window sees the
      // change however the two resume around each other.
      hasPendingChanges = true
      if let existing = activeWork {
        // The types stay in the ledger; the active run or its one follow-up picks them up.
        _ = await existing.task.value
        completion()
        return
      }
      await runThenFollowUp(completion: completion)
    case .databaseInaccessible:
      // The observer remains installed. HealthKit will deliver another opportunity
      // after protected data becomes available, so keep registration truthful.
      completion()
    case .failed:
      // One query covers every type and HealthKit names no type for the error, so the failure
      // belongs to the whole observed selection.
      for metric in metricsByType.values.flatMap({ $0 }) {
        await setState(.failed(category: .healthKit, at: now()), for: metric)
      }
      completion()
    }
  }

  /// Runs this callback's changes, releases HealthKit, then starts at most one follow-up run for
  /// whatever landed while it ran.
  ///
  /// The cap and the early completion are the same budget rule from two sides: a wake that kept
  /// chaining runs would hold this completion handler for minutes of fresh execution limits, and
  /// a held handler is what makes HealthKit throttle or stop background delivery. Changes
  /// recorded after the follow-up started wait for the next wake or the hourly sweep.
  private func runThenFollowUp(completion: @escaping @Sendable () -> Void) async {
    let first = startRun()
    let wasThrottled = await first.task.value
    completion()
    guard activeWork?.id == first.id else { return }

    // `activeWork` deliberately still points at the finished run here: a callback delivered in
    // this window must join it, not find an empty slot and start a second run alongside the
    // follow-up below. Reading the pending flag rather than the ledger keeps the decision and
    // the slot in one actor step, so a change recorded in this window cannot be read as
    // "nothing pending" by the run that is handing over — and the flag answers "did a callback
    // arrive", which is the question here, while the ledger may also hold what the finished run
    // handed back, which buys no follow-up.
    //
    // A throttled run is the one case where pending changes buy no follow-up: the cooldown that
    // refused it refuses the follow-up too, and every such attempt is counted as a throttled
    // wake that iOS never granted. Its own types are back in the ledger for the next wake.
    guard !wasThrottled, hasPendingChanges else {
      activeWork = nil
      return
    }

    let followUp = startRun()
    _ = await followUp.task.value
    if activeWork?.id == followUp.id {
      activeWork = nil
    }
  }

  /// Hands the pending changes to a starting run, or `nil` when another run drained them first.
  /// The flag is cleared as the ledger is handed over, so a change recorded after this point
  /// leads to a run of its own rather than being counted as covered by this one.
  private func drainPendingChanges() async -> Set<HealthObjectTypeID>? {
    hasPendingChanges = false
    let isEmpty = await ledger.isEmpty
    // An empty ledger is not an unknown change: asking for a sweep here would turn a run that
    // has nothing to do into a run over the whole selection.
    guard !isEmpty else { return nil }
    return await ledger.drain()
  }

  /// Starts one coalesced, bounded run and records it as the active work. The task reports
  /// whether the run was throttled.
  private func startRun() -> ActiveWork {
    let coordinator = coordinator
    let executionLimit = executionLimit
    let coalescingDelay = coalescingDelay
    let task = Task { [weak self] in
      if coalescingDelay > .zero {
        try? await Task.sleep(for: coalescingDelay)
      }
      guard !Task.isCancelled, let self else { return false }
      // Draining after the coalescing window is what makes a burst one run over the union.
      guard let changedTypes = await self.drainPendingChanges() else { return false }
      let outcome = await Self.runBounded(
        coordinator: coordinator,
        changedTypes: changedTypes,
        executionLimit: executionLimit
      )
      return await self.restoreUnhandledChanges(after: outcome, changedTypes: changedTypes)
    }
    let work = ActiveWork(id: UUID(), task: task)
    activeWork = work
    return work
  }

  /// Puts back the change signal a run did not handle, and reports whether the run was throttled.
  ///
  /// HealthKit announces a change once. A run that drained the ledger and then did not get
  /// through what it took on has consumed the only notice there was: keeping those types drained
  /// leaves the metrics they name waiting for staleness or the hourly sweep — up to an hour of
  /// added latency for a change the phone already knew about — and a metric an earlier run
  /// checked within the freshness interval is not stale at all, so nothing but the ledger would
  /// bring it back before the next full sweep.
  ///
  /// Re-recording what was drained, rather than holding the ledger until a run reports success,
  /// is what makes this safe under concurrent callbacks. The run needs its scope the moment it
  /// starts, so the signal has to leave the ledger then; `record` unions, so restoring it later
  /// can neither drop a change that arrived while the run was in flight nor count one twice,
  /// and no epoch has to be tracked to tell the two apart. Re-recording an empty set restores
  /// the unknown-change marker, exactly as the original callback did.
  ///
  /// The pending flag is deliberately left alone: a restore is not an arrival, and the
  /// follow-up it would buy is refused by the cooldown this run just started and counted as
  /// another throttled wake iOS never granted. The types wait for the next wake instead, which
  /// drains them whatever the flag says.
  private func restoreUnhandledChanges(
    after outcome: BidirectionalSyncOutcome?,
    changedTypes: Set<HealthObjectTypeID>
  ) async -> Bool {
    if !Self.handledItsScope(outcome) {
      await ledger.record(changedTypes)
    }
    if case .throttled = outcome { return true }
    return false
  }

  /// The categories that say a run stopped early rather than finished: the work behind them was
  /// never attempted, so nothing at all is known about it.
  private static let unfinishedCategories: Set<SyncFailureCategory> = [
    .deviceLocked, .deadlineExceeded, .cancelled,
  ]

  /// Whether the run got through everything the change signal asked of it, which is the only
  /// case where that signal may stay drained. It did not when:
  ///
  /// - the cooldown refused it, so it did no work at all;
  /// - it never answered — the execution limit or a cancellation ended it, and nothing is known
  ///   about what it covered;
  /// - it could not read its configuration or selection, so it reached no metric;
  /// - it deferred metrics, the truncation signal: those keep their anchors and their freshness,
  ///   so the ones a recent run checked are not stale and only the ledger can bring them back;
  /// - it stopped early — a locked device, or a send the deadline abandoned or a cancellation
  ///   cut off, which leaves the rest of the pending entries unsent and unrecorded while
  ///   deferring nothing.
  ///
  /// A metric the run reached and *failed* is deliberately not one of these: it recorded no
  /// check, so it is stale and the scope policy's staleness rule pulls it into the next run.
  /// Holding its type in the ledger as well would pin every later scoped run to it, and to every
  /// other metric of its type. Truncation is the ledger's job; failure is staleness's.
  private static func handledItsScope(_ outcome: BidirectionalSyncOutcome?) -> Bool {
    guard case .performed(let report) = outcome, let outbound = report.outbound else {
      return false
    }
    return outbound.deferredMetrics == 0
      && !outbound.failures.contains { unfinishedCategories.contains($0.category) }
  }

  /// Runs one sync no longer than the execution limit, reporting its outcome — or `nil` when the
  /// limit ran out first and the run's own answer never arrived.
  private static func runBounded(
    coordinator: any BidirectionalSyncCoordinating,
    changedTypes: Set<HealthObjectTypeID>,
    executionLimit: Duration
  ) async -> BidirectionalSyncOutcome? {
    let gate = ObserverRunGate()
    let sync = Task {
      let outcome = await coordinator.sync(
        trigger: .healthKitObserver, changedTypes: changedTypes)
      await gate.open(outcome)
    }
    let timer = Task {
      try? await Task.sleep(for: executionLimit)
      await gate.open(nil)
    }
    let outcome = await withTaskCancellationHandler {
      await gate.wait()
    } onCancel: {
      sync.cancel()
      timer.cancel()
    }
    timer.cancel()
    sync.cancel()
    return outcome
  }

  private func setState(
    _ state: BackgroundRegistrationState,
    for metric: MetricID
  ) async {
    states[metric] = state
    try? await statusStore.setRegistration(state, for: metric)
  }
}

actor HKHealthKitBackgroundDeliveryClient: HealthKitBackgroundDeliveryClient {
  private let healthStore: HKHealthStore
  private var query: HKObserverQuery?

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func isHealthDataAvailable() -> Bool {
    HKHealthStore.isHealthDataAvailable()
  }

  func installObserver(
    for types: Set<HealthObjectTypeID>,
    update: @escaping HealthKitObserverUpdate
  ) throws {
    guard query == nil else { throw HealthKitObserverError.observerAlreadyInstalled }
    guard !types.isEmpty else { throw HealthKitTypeResolverError.unavailableType }
    var descriptors: [HKQueryDescriptor] = []
    // HealthKit reports changes as sample types; this maps them back to the identifiers the
    // scope policy speaks, which is not `rawValue` for every type (a workout is not).
    var typesByIdentifier: [String: HealthObjectTypeID] = [:]
    for type in types.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let sampleType = try HealthKitTypeResolver.objectType(for: type) as? HKSampleType
      else {
        throw HealthKitTypeResolverError.unavailableType
      }
      descriptors.append(HKQueryDescriptor(sampleType: sampleType, predicate: nil))
      typesByIdentifier[sampleType.identifier] = type
    }
    let resolvedTypes = typesByIdentifier
    let observerQuery = HKObserverQuery(queryDescriptors: descriptors) {
      _, changedTypes, completion, error in
      let completionBox = HealthKitObserverCompletion(completion)
      // A nil set is HealthKit declining to name what changed; the empty set forwarded for it
      // is what the scope policy reads as an unknown change, and that is a full sweep.
      let changed = Set((changedTypes ?? []).compactMap { resolvedTypes[$0.identifier] })
      update(Self.event(for: error), changed, completionBox.call)
    }
    query = observerQuery
    healthStore.execute(observerQuery)
  }

  func removeObservers() {
    guard let query else { return }
    self.query = nil
    healthStore.stop(query)
  }

  func enableBackgroundDelivery(for type: HealthObjectTypeID) async throws {
    guard let sampleType = try HealthKitTypeResolver.objectType(for: type) as? HKSampleType else {
      throw HealthKitTypeResolverError.unavailableType
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) {
        success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume(returning: ())
        } else {
          continuation.resume(throwing: HealthKitTypeResolverError.unavailableType)
        }
      }
    }
  }

  func disableBackgroundDelivery(for type: HealthObjectTypeID) async {
    guard let sampleType = try? HealthKitTypeResolver.objectType(for: type) as? HKSampleType
    else { return }
    await withCheckedContinuation { continuation in
      healthStore.disableBackgroundDelivery(for: sampleType) { _, _ in
        continuation.resume()
      }
    }
  }

  nonisolated private static func event(for error: (any Error)?) -> HealthKitObserverEvent {
    guard let error else { return .changed }
    let nsError = error as NSError
    if nsError.domain == HKErrorDomain,
      nsError.code == HKError.Code.errorDatabaseInaccessible.rawValue
    {
      return .databaseInaccessible
    }
    return .failed
  }
}

/// Opens on whichever finishes first, the run or the execution limit, and carries the run's
/// outcome to the waiter when the run won.
private actor ObserverRunGate {
  private var isOpen = false
  private var outcome: BidirectionalSyncOutcome?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func open(_ outcome: BidirectionalSyncOutcome?) {
    guard !isOpen else { return }
    isOpen = true
    self.outcome = outcome
    let pending = waiters
    waiters.removeAll()
    for waiter in pending {
      waiter.resume()
    }
  }

  func wait() async -> BidirectionalSyncOutcome? {
    if isOpen { return outcome }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
    return outcome
  }
}

private final class HealthKitObserverCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var completion: (() -> Void)?

  init(_ completion: @escaping () -> Void) {
    self.completion = completion
  }

  func call() {
    lock.lock()
    let action = completion
    completion = nil
    lock.unlock()
    action?()
  }
}
