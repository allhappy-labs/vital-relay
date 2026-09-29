import Foundation

public protocol HealthBridgeSending: Sendable {
  func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement
  func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement
  func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement
  func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement
  func send(
    batch: [LiveBatchEntry],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement
}

extension HealthBridgeSending {
  public func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    try await send(
      reading: reading, baseURL: baseURL, webhookSecret: webhookSecret, userID: userID,
      requestID: requestID)
  }

  public func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    try await send(
      workout: workout, baseURL: baseURL, webhookSecret: webhookSecret, userID: userID,
      requestID: requestID)
  }
}

extension HealthBridgeWebhookClient: HealthBridgeSending {}

public protocol SyncCoordinating: Sendable {
  func sync(trigger: SyncTrigger, metrics: Set<MetricID>?) async -> SyncReport
  func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?
  ) async -> SyncReport
  /// Runs a scoped sync. `includesMedications` decides whether medications sync in this run.
  /// `lastWindowTouchAt` is when each metric was last touched by a run — the caller that owns the
  /// freshness snapshot supplies `max(lastSentAt, lastCheckedAt)` per metric — and decides whether
  /// a metric whose samples are unchanged still needs a daily window refresh. Counting a check,
  /// not only a send, keeps a metric that has nothing to report from being queried on every wake.
  /// `orderedMetrics` is the order to collect in — a rotated order puts different metrics first
  /// when the budget only covers part of the selection; `nil` keeps registry order.
  func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?,
    includesMedications: Bool,
    lastWindowTouchAt: [MetricID: Date],
    orderedMetrics: [MetricID]?
  ) async -> SyncReport
}

extension SyncCoordinating {
  public func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?
  ) async -> SyncReport {
    await sync(trigger: trigger, metrics: metrics)
  }

  public func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?,
    includesMedications: Bool,
    lastWindowTouchAt: [MetricID: Date],
    orderedMetrics: [MetricID]?
  ) async -> SyncReport {
    await sync(trigger: trigger, metrics: metrics, deadline: deadline)
  }
}

/// What an in-flight run covers, so a later caller can tell whether that run's report answers its
/// own request. A caller may only join a run that covers everything it asked for; anything else
/// hands it a report for metrics the run never collected.
struct SyncRunCoverage: Sendable, Equatable {
  /// The metrics the run covers. `nil` means every selected metric, for a request whose selection
  /// could not be read; because the set is unknown it matches only another equally unresolved
  /// request, never a named one in either direction.
  let metrics: Set<MetricID>?
  let includesMedications: Bool

  func covers(_ other: SyncRunCoverage) -> Bool {
    guard includesMedications || !other.includesMedications else { return false }
    guard let metrics else { return other.metrics == nil }
    guard let otherMetrics = other.metrics else { return false }
    return otherMetrics.isSubset(of: metrics)
  }
}

public actor SyncCoordinator: SyncCoordinating {
  private struct ActiveRun: Sendable {
    let id: UUID
    let coverage: SyncRunCoverage
    let task: Task<SyncReport, Never>
  }

  private struct Dependencies: Sendable {
    let configurationStore: any ConfigurationStore
    let credentialStore: any CredentialStore
    let metricQuery: any MetricQuerying
    let webhookSender: any HealthBridgeSending
    let requestIDGenerator: RequestIDGenerator
    let calendar: Calendar
    let now: @Sendable () -> Date
    let checkpointStore: (any SyncCheckpointStore)?
    let changeQuery: (any MetricChangeQuerying)?
    let retryPolicy: RetryPolicy
    let sleeper: any SyncSleeper
    let jitterSource: any JitterSource
    let deadline: ExecutionDeadline?
    let statusStore: (any SyncStatusStore)?
    let medicationSyncCoordinator: (any MedicationSynchronizing)?
    /// When each metric was last touched by a run: `max(lastSentAt, lastCheckedAt)`. Set per run.
    var lastWindowTouchAt: [MetricID: Date] = [:]
  }

  public static let maximumBatchSize = 50
  public static let maximumConcurrentCollectors = 8
  /// Collection stops while this much of the budget is left, so whatever was collected can still
  /// be sent. Metrics left uncollected keep their anchors and are picked up by the next run.
  public static let sendReserve: TimeInterval = 8
  /// How long the run waits on the device-lock probe before giving up on it. A locked HealthKit
  /// database answers `databaseInaccessible` at once — 0.02 s on device — so this is far longer
  /// than the lock signal ever needs, and short enough that a probe which merely hangs leaves
  /// the rest of the budget to the other metrics.
  public static let probeTimeout: TimeInterval = 5

  private let dependencies: Dependencies
  private var activeRun: ActiveRun?

  public init(
    configurationStore: any ConfigurationStore,
    credentialStore: any CredentialStore,
    metricQuery: any MetricQuerying,
    webhookSender: any HealthBridgeSending,
    requestIDGenerator: RequestIDGenerator = RequestIDGenerator(),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() },
    checkpointStore: (any SyncCheckpointStore)? = nil,
    changeQuery: (any MetricChangeQuerying)? = nil,
    retryPolicy: RetryPolicy = .default,
    sleeper: any SyncSleeper = ContinuousSyncSleeper(),
    jitterSource: any JitterSource = SystemJitterSource(),
    deadline: ExecutionDeadline? = nil,
    statusStore: (any SyncStatusStore)? = nil,
    medicationSyncCoordinator: (any MedicationSynchronizing)? = nil
  ) {
    dependencies = Dependencies(
      configurationStore: configurationStore,
      credentialStore: credentialStore,
      metricQuery: metricQuery,
      webhookSender: webhookSender,
      requestIDGenerator: requestIDGenerator,
      calendar: calendar,
      now: now,
      checkpointStore: checkpointStore,
      changeQuery: changeQuery,
      retryPolicy: retryPolicy,
      sleeper: sleeper,
      jitterSource: jitterSource,
      deadline: deadline,
      statusStore: statusStore,
      medicationSyncCoordinator: medicationSyncCoordinator
    )
  }

  public func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>? = nil
  ) async -> SyncReport {
    await sync(trigger: trigger, metrics: metrics, deadline: nil)
  }

  public func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?
  ) async -> SyncReport {
    await sync(
      trigger: trigger,
      metrics: metrics,
      deadline: deadline,
      includesMedications: metrics == nil,
      lastWindowTouchAt: [:],
      orderedMetrics: nil
    )
  }

  public func sync(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    deadline: ExecutionDeadline?,
    includesMedications: Bool,
    lastWindowTouchAt: [MetricID: Date],
    orderedMetrics: [MetricID]? = nil
  ) async -> SyncReport {
    // A caller that joins an existing run must not cancel it for the caller that started it.
    let requested = SyncRunCoverage(metrics: metrics, includesMedications: includesMedications)
    if let active = activeRun, active.coverage.covers(requested) {
      return await active.task.value
    }
    // Resolving a nil metric set reads the configuration; a run can start while that read is in
    // flight, so the check runs again below rather than only once, before it.
    let coverage =
      metrics == nil
      ? await selectionCoverage(includesMedications: includesMedications)
      : requested
    while let active = activeRun {
      if active.coverage.covers(coverage) {
        return await active.task.value
      }
      // The active run is narrower than this request: wait it out, then run for this scope.
      _ = await active.task.value
      if activeRun?.id == active.id {
        activeRun = nil
      }
    }

    if Task.isCancelled {
      // Registering a run that is already cancelled would hand its report to anyone joining it.
      let cancelledAt = dependencies.now()
      return Self.setupFailureReport(
        trigger: trigger,
        metrics: coverage.metrics,
        category: .cancelled,
        startedAt: cancelledAt,
        finishedAt: cancelledAt
      )
    }

    var dependencies = dependencies
    dependencies.lastWindowTouchAt = lastWindowTouchAt
    let effectiveDeadline = deadline ?? dependencies.deadline
    let id = UUID()
    let task = Task { [dependencies] in
      await Self.performSync(
        trigger: trigger,
        requestedMetrics: coverage.metrics,
        deadline: effectiveDeadline,
        includesMedications: includesMedications,
        orderedMetrics: orderedMetrics,
        dependencies: dependencies
      )
    }
    activeRun = ActiveRun(id: id, coverage: coverage, task: task)
    let report = await waitForSync(task)
    if activeRun?.id == id {
      activeRun = nil
    }
    return report
  }

  /// What a request for every selected metric covers: the configuration's selection. A selection
  /// that cannot be read stays unresolved, and such a request neither joins nor is joined.
  private func selectionCoverage(includesMedications: Bool) async -> SyncRunCoverage {
    let selected = try? await dependencies.configurationStore.load().selectedMetrics
    return SyncRunCoverage(metrics: selected, includesMedications: includesMedications)
  }

  private func waitForSync(_ task: Task<SyncReport, Never>) async -> SyncReport {
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private static func performSync(
    trigger: SyncTrigger,
    requestedMetrics: Set<MetricID>?,
    deadline: ExecutionDeadline?,
    includesMedications: Bool,
    orderedMetrics: [MetricID]?,
    dependencies: Dependencies
  ) async -> SyncReport {
    let startedAt = dependencies.now()
    var statusWriteFailed = false
    if let statusStore = dependencies.statusStore {
      do {
        try await statusStore.recordAttempt(trigger: trigger, at: startedAt)
      } catch {
        statusWriteFailed = true
      }
    }

    let configuration: AppConfiguration
    do {
      configuration = try await dependencies.configurationStore.load()
      try configuration.validate()
    } catch {
      return await finalize(
        setupFailureReport(
          trigger: trigger,
          metrics: requestedMetrics,
          category: .configuration,
          startedAt: startedAt,
          finishedAt: dependencies.now()
        ),
        statusWriteFailed: statusWriteFailed,
        dependencies: dependencies
      )
    }

    let selectedMetrics = requestedMetrics ?? configuration.selectedMetrics
    let baseURL: NormalizedBaseURL
    do {
      baseURL = try NormalizedBaseURL.parse(
        configuration.baseURL,
        allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP
      )
    } catch {
      return await finalize(
        setupFailureReport(
          trigger: trigger,
          metrics: selectedMetrics,
          category: .configuration,
          startedAt: startedAt,
          finishedAt: dependencies.now()
        ),
        statusWriteFailed: statusWriteFailed,
        dependencies: dependencies
      )
    }

    let webhookSecret: String
    do {
      guard let storedSecret = try await dependencies.credentialStore.read(.webhookSecret),
        !storedSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw CredentialStoreError.blankValue
      }
      webhookSecret = storedSecret
    } catch {
      return await finalize(
        setupFailureReport(
          trigger: trigger,
          metrics: selectedMetrics,
          category: .credential,
          startedAt: startedAt,
          finishedAt: dependencies.now()
        ),
        statusWriteFailed: statusWriteFailed,
        dependencies: dependencies
      )
    }

    var attemptedMetrics = selectedMetrics.count
    var synchronizedMetrics = 0
    var skippedMetrics = 0
    var failures: [SyncFailureSummary] = []
    let definitions = orderedDefinitions(selected: selectedMetrics, order: orderedMetrics)
    let unsupportedMetrics = selectedMetrics.subtracting(Set(definitions.map(\.id)))
    failures.append(
      contentsOf: unsupportedMetrics.map {
        SyncFailureSummary(metricID: $0, category: .configuration)
      }
    )

    let collectionStartedAt = dependencies.now()
    let collection = await collectMetrics(
      definitions: definitions,
      deadline: deadline,
      dependencies: dependencies
    )
    let collectionFinishedAt = dependencies.now()
    skippedMetrics += collection.skippedMetrics
    failures.append(contentsOf: collection.failures)

    let sendResult = await sendPending(
      collection.pending,
      baseURL: baseURL,
      webhookSecret: webhookSecret,
      userID: configuration.healthBridgeUserID,
      deadline: deadline,
      dependencies: dependencies
    )
    let sendFinishedAt = dependencies.now()
    synchronizedMetrics += sendResult.synchronizedMetrics
    failures.append(contentsOf: sendResult.failures)

    if includesMedications,
      let medicationSyncCoordinator = dependencies.medicationSyncCoordinator
    {
      let medicationReport = await medicationSyncCoordinator.sync(
        trigger: trigger, deadline: deadline)
      if medicationReport.attempted {
        attemptedMetrics += 1
      }
      if medicationReport.synchronized {
        synchronizedMetrics += 1
      }
      if medicationReport.skipped {
        skippedMetrics += 1
      }
      if let failure = medicationReport.failure {
        failures.append(.init(metricID: nil, category: failure))
      }
    }

    return await finalize(
      SyncReport(
        trigger: trigger,
        attemptedMetrics: attemptedMetrics,
        synchronizedMetrics: synchronizedMetrics,
        skippedMetrics: skippedMetrics,
        failures: failures,
        startedAt: startedAt,
        finishedAt: dependencies.now(),
        requestCount: sendResult.requestCount,
        collectedMetrics: collection.collectedMetrics,
        deferredMetrics: collection.deferredMetrics,
        collectSeconds: collectionFinishedAt.timeIntervalSince(collectionStartedAt),
        sendSeconds: sendFinishedAt.timeIntervalSince(collectionFinishedAt),
        collectedMetricIDs: collection.collectedMetricIDs,
        synchronizedMetricIDs: sendResult.synchronizedMetricIDs,
        // Everything the run looked at without failing, minus whatever it collected a value
        // for: a metric with a payload is resolved only once Health Bridge has acknowledged it.
        resolvedMetricIDs: collection.collectedMetricIDs
          .subtracting(collection.pending.map(\.metricID))
          .union(sendResult.synchronizedMetricIDs)
      ),
      statusWriteFailed: statusWriteFailed,
      dependencies: dependencies
    )
  }

  private static func finalize(
    _ report: SyncReport,
    statusWriteFailed: Bool,
    dependencies: Dependencies
  ) async -> SyncReport {
    var finalReport = report
    if statusWriteFailed {
      finalReport = addingStatusFailure(to: finalReport)
    }
    if let statusStore = dependencies.statusStore {
      do {
        try await statusStore.record(report: finalReport)
      } catch {
        finalReport = addingStatusFailure(to: finalReport)
      }
    }
    return finalReport
  }

  private static func addingStatusFailure(to report: SyncReport) -> SyncReport {
    guard !report.failures.contains(where: { $0.metricID == nil && $0.category == .checkpoint })
    else {
      return report
    }
    return SyncReport(
      trigger: report.trigger,
      attemptedMetrics: report.attemptedMetrics,
      synchronizedMetrics: report.synchronizedMetrics,
      skippedMetrics: report.skippedMetrics,
      failures: report.failures + [.init(metricID: nil, category: .checkpoint)],
      startedAt: report.startedAt,
      finishedAt: report.finishedAt,
      requestCount: report.requestCount,
      collectedMetrics: report.collectedMetrics,
      deferredMetrics: report.deferredMetrics,
      collectSeconds: report.collectSeconds,
      sendSeconds: report.sendSeconds,
      collectedMetricIDs: report.collectedMetricIDs,
      synchronizedMetricIDs: report.synchronizedMetricIDs,
      resolvedMetricIDs: report.resolvedMetricIDs
    )
  }

  /// The run's collection order: the caller's order first (a full sweep rotates it so a truncated
  /// run starts where the last one stopped), then registry order for anything it does not name.
  private static func orderedDefinitions(
    selected: Set<MetricID>,
    order: [MetricID]?
  ) -> [MetricDefinition] {
    let registryOrder = MetricRegistry.selectable.filter { selected.contains($0.id) }
    guard let order else { return registryOrder }
    let definitionsByID = Dictionary(
      registryOrder.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var ordered: [MetricDefinition] = []
    var placed: Set<MetricID> = []
    for metric in order {
      guard let definition = definitionsByID[metric], placed.insert(metric).inserted else {
        continue
      }
      ordered.append(definition)
    }
    ordered.append(contentsOf: registryOrder.filter { !placed.contains($0.id) })
    return ordered
  }

  private static func commit(
    _ anchor: Data?,
    metric: MetricID,
    dependencies: Dependencies
  ) async throws {
    guard let anchor, let checkpointStore = dependencies.checkpointStore else {
      return
    }
    do {
      try await checkpointStore.commit(anchor: anchor, for: metric)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw SyncCoordinatorInternalError.checkpoint
    }
  }

  private struct PendingMetric: Sendable {
    let metricID: MetricID
    let entry: LiveBatchEntry
    let candidateAnchor: Data?
  }

  private enum CollectedMetric: Sendable {
    case pending(PendingMetric)
    case skipped
    case skippedCommit(Data)
    case failed(SyncFailureCategory)
    case locked
    /// Left for the next run because the budget was down to the send reserve, or because the
    /// collector was still running when the reserve began. Neither skipped nor failed: nothing
    /// was learned about the metric, so it keeps its anchor and its freshness.
    case deferred
    case cancelled
    case deadlineExceeded
  }

  private struct CollectionResult: Sendable {
    var pending: [PendingMetric] = []
    var skippedMetrics = 0
    /// Metrics this run actually looked at, whatever the answer was.
    var collectedMetrics = 0
    /// Which of those metrics the run looked at without the query failing, so their freshness
    /// may advance. A failed query leaves its metric out, keeping it stale for the next run.
    var collectedMetricIDs: Set<MetricID> = []
    /// Metrics the send reserve left for the next run: never scheduled, or deferred because they
    /// would have started past the boundary.
    var deferredMetrics = 0
    var failures: [SyncFailureSummary] = []
  }

  private struct SendResult: Sendable {
    var synchronizedMetrics = 0
    var synchronizedMetricIDs: Set<MetricID> = []
    var requestCount = 0
    var failures: [SyncFailureSummary] = []
  }

  private static func collectMetrics(
    definitions: [MetricDefinition],
    deadline: ExecutionDeadline?,
    dependencies: Dependencies
  ) async -> CollectionResult {
    var result = CollectionResult()
    guard let first = definitions.first else { return result }

    // The first metric doubles as the device-lock probe and is admitted whatever the budget is:
    // the reserve decides how many *more* collectors start, and a run that looks at nothing
    // learns nothing. It is bounded *short* — at `probeTimeout` rather than at the deadline —
    // because the only thing the run is waiting for here is an answer about the device, and a
    // locked database gives that answer at once. A probe bounded at the whole budget was fine
    // while it either answered or failed fast, but a HealthKit query that simply hangs — what a
    // phone coming out of a long lock does — then spent the entire wake on one metric and left
    // the reserve with nothing to admit: an observer run on 20 Sep 2026 burned all 18 s on the
    // probe and deferred all 88 metrics without issuing a request.
    let probeBoundary = deadline.map {
      min($0.expiresAt, dependencies.now().addingTimeInterval(probeTimeout))
    }
    let firstOutcome = await boundedCollect(
      first,
      until: probeBoundary,
      deadline: deadline,
      dependencies: dependencies,
      appliesSendReserve: false
    )
    if case .locked = firstOutcome {
      result.skippedMetrics = definitions.count
      result.failures.append(.init(metricID: nil, category: .deviceLocked))
      return result
    }
    // A probe that ran out of time said nothing, and nothing is not a lock: the run carries on
    // through the remaining metrics with whatever budget is left, so one hung query cannot block
    // the other 87. The probe's own metric is deferred below — it keeps its anchor and its
    // freshness, and is not retried here, because a query that just hung would only hang again.

    let remaining = Array(definitions.dropFirst())
    // Where collection has to be over, whatever HealthKit is still doing, so what was collected
    // can still be sent.
    let boundary = deadline?.expiresAt.addingTimeInterval(-sendReserve)
    let (collected, scheduledCount) = await withTaskGroup(
      of: (Int, CollectedMetric).self,
      returning: ([(Int, CollectedMetric)], Int).self
    ) { group in
      var results: [(Int, CollectedMetric)] = []
      var nextIndex = 0
      var lockEncountered = false
      while nextIndex < min(remaining.count, maximumConcurrentCollectors) {
        guard hasSendReserve(deadline, dependencies: dependencies) else { break }
        group.addTask { [index = nextIndex] in
          (
            index,
            await boundedCollect(
              remaining[index], until: boundary, deadline: deadline, dependencies: dependencies)
          )
        }
        nextIndex += 1
      }
      while let outcome = await group.next() {
        results.append(outcome)
        if case .locked = outcome.1 {
          lockEncountered = true
          group.cancelAll()
        }
        if !lockEncountered, !Task.isCancelled, nextIndex < remaining.count,
          hasSendReserve(deadline, dependencies: dependencies)
        {
          group.addTask { [index = nextIndex] in
            (
              index,
              await boundedCollect(
                remaining[index], until: boundary, deadline: deadline, dependencies: dependencies)
            )
          }
          nextIndex += 1
        }
      }
      return (results.sorted { $0.0 < $1.0 }, nextIndex)
    }

    let outcomes = [(first, firstOutcome)] + collected.map { (remaining[$0.0], $0.1) }
    let lockEncountered = outcomes.contains {
      if case .locked = $0.1 { return true }
      return false
    }
    // One failure row per category, not one per metric: these outcomes arrive in batches of up
    // to `maximumConcurrentCollectors`, and the row lands in a persisted event. The row is a
    // label, never the accounting — every outcome below counts itself.
    var recordedCancellation = false
    var recordedDeadline = false
    for (definition, outcome) in outcomes {
      switch outcome {
      case .pending(let metric):
        result.collectedMetrics += 1
        result.collectedMetricIDs.insert(definition.id)
        result.pending.append(metric)
      case .skipped:
        result.collectedMetrics += 1
        result.collectedMetricIDs.insert(definition.id)
        result.skippedMetrics += 1
      case .skippedCommit(let anchor):
        result.collectedMetrics += 1
        do {
          try await commit(anchor, metric: definition.id, dependencies: dependencies)
          // Checked only once the anchor is actually committed: a failed write leaves the same
          // changes waiting for the next run, and calling the metric fresh for an hour would
          // hand that retry to the staleness rule instead of the next wake.
          result.collectedMetricIDs.insert(definition.id)
          result.skippedMetrics += 1
        } catch {
          result.failures.append(
            .init(metricID: definition.id, category: failureCategory(for: error))
          )
        }
      case .failed(let category):
        result.collectedMetrics += 1
        result.failures.append(.init(metricID: definition.id, category: category))
      case .locked:
        result.skippedMetrics += 1
      case .deferred:
        result.deferredMetrics += 1
      case .cancelled:
        if lockEncountered {
          result.skippedMetrics += 1
        } else {
          // A cancelled collector leaves its metric exactly as a deferred one does: anchor
          // intact, freshness unrecorded. Counting it is what keeps the run's arithmetic whole —
          // cancellation reaches all eight concurrent collectors in one pass, and recording only
          // the first, as a failure, dropped the other seven from every count there is.
          result.deferredMetrics += 1
          if !recordedCancellation {
            recordedCancellation = true
            result.failures.append(.init(metricID: definition.id, category: .cancelled))
          }
        }
      case .deadlineExceeded:
        // Also untouched, so also deferred. The failure row is what says the budget ran out; the
        // count is what says how much of the selection that cost.
        result.deferredMetrics += 1
        if !recordedDeadline {
          recordedDeadline = true
          result.failures.append(.init(metricID: definition.id, category: .deadlineExceeded))
        }
      }
    }
    if lockEncountered {
      result.skippedMetrics += remaining.count - scheduledCount
      result.failures.append(.init(metricID: nil, category: .deviceLocked))
    } else {
      // Every metric no collector was ever started for: the reserve refused it, or the run was
      // cancelled before its turn came. Both leave it untouched, which is what deferred means —
      // counting only the first would let a cancelled sweep report that it deferred nothing.
      result.deferredMetrics += remaining.count - scheduledCount
    }
    return result
  }

  /// Collects one metric, giving up at `boundary` and deferring it instead.
  ///
  /// The reserve can only bound collection if it bounds a collector that is already running:
  /// `collect` awaits HealthKit work that carries no timeout and does not observe cancellation
  /// promptly, so a collector admitted just before the boundary can otherwise run past it — and
  /// past the deadline — while the reserve, which only gates admission, has nothing left to
  /// refuse. Work that outlives the boundary is abandoned rather than awaited; awaiting it is
  /// exactly what makes the bound no bound at all. The metric keeps its anchor and its freshness,
  /// so the next run picks it up.
  private static func boundedCollect(
    _ definition: MetricDefinition,
    until boundary: Date?,
    deadline: ExecutionDeadline?,
    dependencies: Dependencies,
    appliesSendReserve: Bool = true
  ) async -> CollectedMetric {
    // No boundary, or one already behind us: `collect`'s own entry checks answer without
    // suspending, and they tell a budget that is gone from one that is merely down to the
    // reserve. Wrapping those would flatten both into a deferral.
    guard let boundary, boundary.timeIntervalSince(dependencies.now()) > 0 else {
      return await collect(
        definition,
        deadline: deadline,
        dependencies: dependencies,
        appliesSendReserve: appliesSendReserve
      )
    }
    return await bounded(until: boundary, dependencies: dependencies) {
      await collect(
        definition,
        deadline: deadline,
        dependencies: dependencies,
        appliesSendReserve: appliesSendReserve
      )
    } ?? .deferred
  }

  /// Runs `work` with a wall-clock bound, answering `nil` when the bound arrives first. The work
  /// is abandoned, not awaited: a structured child would have to be waited for, and the calls
  /// this bounds — HealthKit queries, a stalled name lookup — are the ones that do not come back
  /// when cancelled. A `nil` boundary is no bound.
  private static func bounded<Value: Sendable>(
    until boundary: Date?,
    dependencies: Dependencies,
    _ work: @escaping @Sendable () async -> Value
  ) async -> Value? {
    guard let boundary else { return await work() }
    let window = boundary.timeIntervalSince(dependencies.now())
    guard window > 0 else { return nil }
    let gate = BoundedWorkGate<Value>()
    let worker = Task { await gate.open(await work()) }
    let timer = Task {
      try? await Task.sleep(for: .seconds(window))
      await gate.open(nil)
    }
    let value = await withTaskCancellationHandler {
      await gate.wait()
    } onCancel: {
      worker.cancel()
      timer.cancel()
    }
    timer.cancel()
    worker.cancel()
    return value
  }

  /// Whether there is budget left for another collector on top of the send reserve. A run with no
  /// deadline always has room.
  private static func hasSendReserve(
    _ deadline: ExecutionDeadline?,
    dependencies: Dependencies
  ) -> Bool {
    guard let deadline else { return true }
    return deadline.remaining(now: dependencies.now()) > sendReserve
  }

  private static func collect(
    _ definition: MetricDefinition,
    deadline: ExecutionDeadline?,
    dependencies: Dependencies,
    appliesSendReserve: Bool = true
  ) async -> CollectedMetric {
    if Task.isCancelled { return .cancelled }
    if let deadline, deadline.remaining(now: dependencies.now()) <= 0 {
      return .deadlineExceeded
    }
    // A collector that starts once the budget is down to the reserve would spend the time the
    // pending entries need to reach Home Assistant.
    if appliesSendReserve, !hasSendReserve(deadline, dependencies: dependencies) {
      return .deferred
    }

    let candidateAnchor: Data?
    let hadCommittedAnchor: Bool
    let hasDeletedSamples: Bool
    if let checkpointStore = dependencies.checkpointStore,
      let changeQuery = dependencies.changeQuery
    {
      let committedAnchor: Data?
      do {
        committedAnchor = try await checkpointStore.anchor(for: definition.id)
      } catch is CancellationError {
        return .cancelled
      } catch {
        return .failed(.checkpoint)
      }
      hadCommittedAnchor = committedAnchor != nil

      let changes: MetricChanges
      do {
        changes = try await changeQuery.changes(
          for: definition.id,
          committedAnchor: committedAnchor
        )
      } catch is CancellationError {
        return .cancelled
      } catch MetricChangeQueryError.databaseInaccessible {
        return .locked
      } catch {
        return .failed(.healthKit)
      }
      // Every window a metric can have is anchored to the local day, so a value goes stale at
      // local midnight with or without new samples: a metric not touched yet today is collected
      // again, at most once per day. A touch exactly at local midnight counts as today's. There
      // is nothing new to commit for a refresh: a nil candidate sends the value and leaves the
      // anchor where it is.
      let startOfToday = dependencies.calendar.startOfDay(for: dependencies.now())
      let needsWindowRefresh =
        (dependencies.lastWindowTouchAt[definition.id] ?? .distantPast) < startOfToday
      guard changes.hasChanges || needsWindowRefresh else { return .skipped }
      candidateAnchor = changes.hasChanges ? changes.candidateAnchor : nil
      hasDeletedSamples = !changes.deletedSampleIDs.isEmpty
    } else {
      candidateAnchor = nil
      hadCommittedAnchor = false
      hasDeletedSamples = false
    }

    if definition.aggregation == .latestWorkout {
      let summary: WorkoutSummary?
      do {
        summary = try await dependencies.metricQuery.latestWorkout(now: dependencies.now())
      } catch is CancellationError {
        return .cancelled
      } catch {
        return .failed(failureCategory(for: error))
      }
      guard let summary else {
        guard let candidateAnchor else { return .skipped }
        return hadCommittedAnchor ? .failed(.compatibility) : .skippedCommit(candidateAnchor)
      }
      do {
        let payload = try WorkoutTransformer.transform(summary, lastSynced: dependencies.now())
        return .pending(
          PendingMetric(
            metricID: definition.id,
            entry: .workout(payload),
            candidateAnchor: candidateAnchor
          )
        )
      } catch {
        return .failed(failureCategory(for: error))
      }
    }

    let reading: MetricReading?
    do {
      reading = try await dependencies.metricQuery.currentReading(
        for: definition,
        now: dependencies.now(),
        calendar: dependencies.calendar
      )
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .failed(.healthKit)
    }
    guard let reading else {
      guard let candidateAnchor else { return .skipped }
      return !hadCommittedAnchor || !hasDeletedSamples
        ? .skippedCommit(candidateAnchor) : .failed(.compatibility)
    }
    return .pending(
      PendingMetric(
        metricID: definition.id,
        entry: .reading(reading),
        candidateAnchor: candidateAnchor
      )
    )
  }

  private static func sendPending(
    _ pending: [PendingMetric],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    deadline: ExecutionDeadline?,
    dependencies: Dependencies
  ) async -> SendResult {
    var result = SendResult()
    var start = 0
    while start < pending.count {
      let chunk = Array(pending[start..<min(start + maximumBatchSize, pending.count)])
      start += chunk.count
      if Task.isCancelled {
        result.failures.append(.init(metricID: chunk[0].metricID, category: .cancelled))
        break
      }
      let shouldStop =
        chunk.count == 1
        ? await sendIndividually(
          chunk, baseURL: baseURL, webhookSecret: webhookSecret, userID: userID,
          deadline: deadline, dependencies: dependencies, into: &result)
        : await sendBatch(
          chunk, baseURL: baseURL, webhookSecret: webhookSecret, userID: userID,
          deadline: deadline, dependencies: dependencies, into: &result)
      if shouldStop { break }
    }
    return result
  }

  private static func sendBatch(
    _ chunk: [PendingMetric],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    deadline: ExecutionDeadline?,
    dependencies: Dependencies,
    into result: inout SendResult
  ) async -> Bool {
    let requestID = dependencies.requestIDGenerator.live()
    let entries = chunk.map(\.entry)
    let batchResult: LiveBatchResult
    do {
      batchResult = try await sendWithRetry(
        deadline: deadline,
        dependencies: dependencies,
        requestCount: &result.requestCount
      ) { timeout in
        try await dependencies.webhookSender.send(
          batch: entries,
          baseURL: baseURL,
          webhookSecret: webhookSecret,
          userID: userID,
          requestID: requestID,
          timeout: timeout
        )
      } interpret: { acknowledgement in
        try acknowledgement.batchResult(requestID: requestID, entryCount: entries.count)
      }
    } catch {
      let category = failureCategory(for: error)
      if category == .validation {
        return await sendIndividually(
          chunk, baseURL: baseURL, webhookSecret: webhookSecret, userID: userID,
          deadline: deadline, dependencies: dependencies, into: &result)
      }
      result.failures.append(
        contentsOf: chunk.map { .init(metricID: $0.metricID, category: category) }
      )
      return category == .cancelled || category == .deadlineExceeded
    }

    switch batchResult {
    case .applied:
      for metric in chunk {
        do {
          try await commit(
            metric.candidateAnchor, metric: metric.metricID, dependencies: dependencies)
          result.synchronizedMetrics += 1
          result.synchronizedMetricIDs.insert(metric.metricID)
        } catch {
          result.failures.append(
            .init(metricID: metric.metricID, category: failureCategory(for: error))
          )
        }
      }
      return false
    case .partial:
      return await sendIndividually(
        chunk, baseURL: baseURL, webhookSecret: webhookSecret, userID: userID,
        deadline: deadline, dependencies: dependencies, into: &result)
    }
  }

  private static func sendIndividually(
    _ chunk: [PendingMetric],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    deadline: ExecutionDeadline?,
    dependencies: Dependencies,
    into result: inout SendResult
  ) async -> Bool {
    for metric in chunk {
      if Task.isCancelled {
        result.failures.append(.init(metricID: metric.metricID, category: .cancelled))
        return true
      }
      let requestID = dependencies.requestIDGenerator.live()
      do {
        try await sendWithRetry(
          deadline: deadline,
          dependencies: dependencies,
          requestCount: &result.requestCount
        ) { timeout in
          switch metric.entry {
          case .reading(let reading):
            try await dependencies.webhookSender.send(
              reading: reading, baseURL: baseURL, webhookSecret: webhookSecret,
              userID: userID, requestID: requestID, timeout: timeout)
          case .workout(let payload):
            try await dependencies.webhookSender.send(
              workout: payload, baseURL: baseURL, webhookSecret: webhookSecret,
              userID: userID, requestID: requestID, timeout: timeout)
          }
        } interpret: { acknowledgement in
          try acknowledgement.validate(requestID: requestID)
        }
        try await commit(
          metric.candidateAnchor, metric: metric.metricID, dependencies: dependencies)
        result.synchronizedMetrics += 1
        result.synchronizedMetricIDs.insert(metric.metricID)
      } catch {
        let category = failureCategory(for: error)
        result.failures.append(.init(metricID: metric.metricID, category: category))
        if category == .cancelled || category == .deadlineExceeded {
          return true
        }
      }
    }
    return false
  }

  /// What one bounded attempt answered.
  private enum SendAttempt: Sendable {
    case acknowledgement(LiveAcknowledgement)
    case cancelled
    case failed(NetworkFailure)
  }

  /// One send attempt, with its error reduced to a `NetworkFailure` so an attempt abandoned at
  /// the deadline can cross back out of the bound as a `Sendable` value.
  private static func attempt(
    _ operation: @escaping @Sendable (TimeInterval) async throws -> LiveAcknowledgement,
    timeout: TimeInterval
  ) async -> SendAttempt {
    do {
      return .acknowledgement(try await operation(timeout))
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .failed(networkFailure(for: error))
    }
  }

  private static func sendWithRetry<Value>(
    deadline: ExecutionDeadline?,
    dependencies: Dependencies,
    requestCount: inout Int,
    operation: @escaping @Sendable (TimeInterval) async throws -> LiveAcknowledgement,
    interpret: (LiveAcknowledgement) throws -> Value
  ) async throws -> Value {
    var completedAttempts = 0
    while true {
      try Task.checkCancellation()
      let timeout: TimeInterval
      do {
        timeout = try ExecutionDeadline.requestTimeout(for: deadline, now: dependencies.now())
      } catch {
        throw SyncCoordinatorInternalError.deadline
      }
      completedAttempts += 1
      requestCount += 1
      // The timeout is handed down, not relied on: `URLRequest.timeoutInterval` bounds how long a
      // transfer may stay idle rather than how long it may take, and the name lookup that runs
      // ahead of it observes no timeout at all. The deadline is only a deadline if the run stops
      // waiting when it expires.
      let attempt = await bounded(until: deadline?.expiresAt, dependencies: dependencies) {
        await attempt(operation, timeout: timeout)
      }
      guard let attempt else { throw SyncCoordinatorInternalError.deadline }

      let failure: NetworkFailure
      switch attempt {
      case .acknowledgement(let acknowledgement):
        do {
          return try interpret(acknowledgement)
        } catch {
          failure = .protocolMismatch
        }
      case .cancelled:
        throw CancellationError()
      case .failed(let networkFailure):
        failure = networkFailure
      }

      guard
        let delay = dependencies.retryPolicy.delay(
          after: failure,
          completedAttempts: completedAttempts,
          jitterUnit: await dependencies.jitterSource.nextUnit()
        )
      else {
        throw failure
      }
      if let deadline {
        do {
          _ = try deadline.validate(wait: delay, now: dependencies.now())
        } catch {
          throw SyncCoordinatorInternalError.deadline
        }
      }
      try await dependencies.sleeper.sleep(for: delay)
    }
  }

  private static func networkFailure(for error: any Error) -> NetworkFailure {
    if let failure = error as? NetworkFailure {
      return failure
    }
    if error is LiveAcknowledgementValidationError {
      return .protocolMismatch
    }
    return NetworkFailure.classify(error)
  }

  private static func setupFailureReport(
    trigger: SyncTrigger,
    metrics: Set<MetricID>?,
    category: SyncFailureCategory,
    startedAt: Date,
    finishedAt: Date
  ) -> SyncReport {
    let selectedMetrics = metrics ?? []
    let failures =
      selectedMetrics.isEmpty
      ? [SyncFailureSummary(metricID: nil, category: category)]
      : selectedMetrics.map { SyncFailureSummary(metricID: $0, category: category) }
    return SyncReport(
      trigger: trigger,
      attemptedMetrics: selectedMetrics.count,
      synchronizedMetrics: 0,
      skippedMetrics: 0,
      failures: failures,
      startedAt: startedAt,
      finishedAt: finishedAt
    )
  }

  private static func failureCategory(for error: any Error) -> SyncFailureCategory {
    if error is CancellationError {
      return .cancelled
    }
    if let internalError = error as? SyncCoordinatorInternalError {
      switch internalError {
      case .checkpoint: return .checkpoint
      case .deadline: return .deadlineExceeded
      }
    }
    guard let failure = error as? NetworkFailure else {
      return error is LiveAcknowledgementValidationError ? .protocolMismatch : .unknown
    }
    switch failure {
    case .cancelled:
      return .cancelled
    case .timeout:
      return .timeout
    case .dnsFailure:
      return .dnsFailure
    case .offline:
      return .offline
    case .connectionLost:
      return .connectionLost
    case .tlsFailure:
      return .tlsFailure
    case .unauthorized:
      return .unauthorized
    case .forbidden:
      return .forbidden
    case .notFound:
      return .notFound
    case .validation:
      return .validation
    case .rateLimited:
      return .rateLimited
    case .server:
      return .server
    case .malformedResponse:
      return .malformedResponse
    case .protocolMismatch:
      return .protocolMismatch
    case .unexpectedStatus, .transport:
      return .transport
    }
  }
}

private enum SyncCoordinatorInternalError: Error, Sendable {
  case checkpoint
  case deadline
}

/// Opens on whichever finishes first, the bounded work or its boundary, and carries the work's
/// answer to the waiter when the work won.
private actor BoundedWorkGate<Value: Sendable> {
  private var isOpen = false
  private var value: Value?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func open(_ value: Value?) {
    guard !isOpen else { return }
    isOpen = true
    self.value = value
    let pending = waiters
    waiters.removeAll()
    for waiter in pending {
      waiter.resume()
    }
  }

  func wait() async -> Value? {
    if isOpen { return value }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
    return value
  }
}
