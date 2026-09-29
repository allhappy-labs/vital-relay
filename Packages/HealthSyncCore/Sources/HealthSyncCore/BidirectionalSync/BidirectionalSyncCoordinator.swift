import Foundation

public actor BidirectionalSyncCoordinator: BidirectionalSyncCoordinating {
  private struct ActiveSync: Sendable {
    let id: UUID
    /// What the run covers, so a caller only takes its report when the run answers its request.
    let coverage: SyncRunCoverage
    let task: Task<BidirectionalSyncOutcome, Never>
  }

  private let outbound: any SyncCoordinating
  private let paidAccess: (any PaidFeatureAccessing)?
  private let inbound: any InboundSyncCoordinating
  private let configurationStore: any ConfigurationStore
  private let statusStore: any SyncStatusStore
  private let contextProvider: (any SyncRunContextProviding)?
  private let scopePolicy: SyncScopePolicy
  private let freshnessStore: (any MetricFreshnessStore)?
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private var activeSync: ActiveSync?
  private var interruptedAttemptCheck: Task<Void, Never>?

  public init(
    outbound: any SyncCoordinating,
    inbound: any InboundSyncCoordinating,
    configurationStore: any ConfigurationStore,
    statusStore: any SyncStatusStore,
    paidAccess: (any PaidFeatureAccessing)? = nil,
    contextProvider: (any SyncRunContextProviding)? = nil,
    scopePolicy: SyncScopePolicy = SyncScopePolicy(),
    freshnessStore: (any MetricFreshnessStore)? = nil,
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.outbound = outbound
    self.paidAccess = paidAccess
    self.inbound = inbound
    self.configurationStore = configurationStore
    self.statusStore = statusStore
    self.contextProvider = contextProvider
    self.scopePolicy = scopePolicy
    self.freshnessStore = freshnessStore
    self.calendar = calendar
    self.now = now
  }

  public func sync(trigger: SyncTrigger) async -> BidirectionalSyncOutcome {
    await sync(trigger: trigger, changedTypes: [], changedTypesKnown: false)
  }

  public func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>
  ) async -> BidirectionalSyncOutcome {
    await sync(trigger: trigger, changedTypes: changedTypes, changedTypesKnown: true)
  }

  private func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>,
    changedTypesKnown: Bool
  ) async -> BidirectionalSyncOutcome {
    var resolution = await resolvedRun(
      trigger: trigger,
      changedTypes: changedTypes,
      changedTypesKnown: changedTypesKnown,
      now: now()
    )
    var coverage = resolution.coverage
    // A caller that joins an existing run must not cancel it for the caller that started it.
    if let activeSync, activeSync.coverage.covers(coverage) {
      return await activeSync.task.value
    }

    if interruptedAttemptCheck == nil {
      let store = statusStore
      interruptedAttemptCheck = Task {
        _ = try? await store.recordInterruptedAttemptIfNeeded()
      }
    }
    await interruptedAttemptCheck?.value

    let requestDate = now()
    if let nextEligibleAt = await nextEligibleDate(trigger: trigger, requestDate: requestDate) {
      try? await statusStore.recordThrottledWake()
      return .throttled(nextEligibleAt: nextEligibleAt)
    }

    // Wait out any run this caller cannot take the report of, then run for its own scope.
    while true {
      while let active = activeSync {
        if active.coverage.covers(coverage) {
          return await active.task.value
        }
        _ = await active.task.value
        if activeSync?.id == active.id {
          activeSync = nil
        }
        // The run just waited out may have checked and sent the very metrics this caller was about
        // to ask for. Resolving once, before the wait, would re-query and re-send every daily
        // metric that run refreshed — their window touches predate it — and would audit starvation
        // against freshness that is now out of date. The fresh coverage is also what the next turn
        // of this loop judges joining by, so P1's scope-aware join semantics still decide it.
        resolution = await resolvedRun(
          trigger: trigger,
          changedTypes: changedTypes,
          changedTypesKnown: changedTypesKnown,
          now: now()
        )
        coverage = resolution.coverage
      }
      // Authorize before publishing a joinable task, so free callers cannot inherit a paid
      // rejection. The await permits another run to start: re-enter the coverage/wait loop
      // in that case, and authorize again after any new wait.
      if trigger != .manual && trigger != .pullToRefresh,
        let paidAccess, await paidAccess.accessState() != .unlocked
      {
        return .requiresPurchase
      }
      if activeSync == nil { break }
    }

    // The run starts on a fresh clock: waiting out a run this caller could not join is not part
    // of its own duration, and back-dating the attempt would loosen the next wake's throttle.
    let startedAt = now()
    if Task.isCancelled {
      // Registering a run that is already cancelled would hand its report to anyone joining it.
      return .performed(
        setupFailureReport(trigger: trigger, category: .cancelled, startedAt: startedAt)
      )
    }
    // The deadline stays anchored to the wake, because the budget iOS granted is spent by the
    // wait as much as by the run.
    let deadline = trigger.budget.map {
      ExecutionDeadline(expiresAt: requestDate.addingTimeInterval($0))
    }
    if let deadline, deadline.remaining(now: startedAt) <= 0 {
      // Nothing is attempted, so nothing is recorded as attempted; the wake is counted like any
      // other that did no work. The run it waited out recorded an attempt of its own, so the
      // next opportunity is the schedule's, not this instant — asking for one now would buy a
      // wake that is throttled on arrival.
      try? await statusStore.recordThrottledWake()
      let nextEligibleAt = await nextEligibleDate(trigger: trigger, requestDate: startedAt)
      return .throttled(nextEligibleAt: nextEligibleAt ?? startedAt)
    }

    let id = UUID()
    let task = Task {
      await self.perform(
        trigger: trigger,
        startedAt: startedAt,
        deadline: deadline,
        resolution: resolution
      )
    }
    activeSync = ActiveSync(id: id, coverage: coverage, task: task)
    let outcome = await waitForSync(task)
    if activeSync?.id == id {
      activeSync = nil
    }
    return outcome
  }

  /// What a run started now would cover, and the freshness it was decided from. The scope is
  /// resolved before the run starts, so the run and the callers that may join it are compared
  /// against the same set: a full sweep must not take the report of a scoped run.
  private func resolvedRun(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>,
    changedTypesKnown: Bool,
    now: Date
  ) async -> ResolvedRun {
    // A freshness store that cannot be read is treated as no freshness data at all, which the
    // policy turns into a full sweep; the run itself goes ahead either way.
    let freshness = (try? await freshnessStore?.snapshot()) ?? nil
    // The selection and the cadence come from the same read: the sweep interval is derived from
    // the configured frequency, so scoping a run against a selection the configuration no longer
    // carries would also date it against a cadence it no longer has.
    let configuration = try? await configurationStore.load()
    let scope = configuration.map {
      scopePolicy.scope(
        trigger: trigger,
        selected: $0.selectedMetrics,
        changedTypes: changedTypes,
        changedTypesKnown: changedTypesKnown,
        freshness: freshness ?? MetricFreshnessSnapshot(),
        frequency: $0.backgroundSyncFrequency,
        now: now,
        calendar: calendar
      )
    }
    return ResolvedRun(
      scope: scope,
      selectedMetrics: configuration?.selectedMetrics,
      freshness: freshness ?? MetricFreshnessSnapshot(),
      changedTypes: changedTypes,
      changedTypesKnown: changedTypesKnown
    )
  }

  /// The scope a run covers, with the inputs the run needs once it finishes: what the freshness
  /// was before it started, and the change signal it was scoped from.
  private struct ResolvedRun: Sendable {
    /// `nil` when the selection could not be read, which leaves the run unresolved: it neither
    /// joins another run nor is joined.
    let scope: SyncScope?
    let selectedMetrics: Set<MetricID>?
    let freshness: MetricFreshnessSnapshot
    let changedTypes: Set<HealthObjectTypeID>
    let changedTypesKnown: Bool

    var coverage: SyncRunCoverage {
      SyncRunCoverage(
        metrics: scope?.metrics,
        includesMedications: scope?.includesMedications ?? true
      )
    }

    /// When each metric was last touched by a run. A check counts as much as a send: a refresh
    /// that found no value still means the metric was inside today's window, and gating on sends
    /// alone would query it again on every wake for the rest of the day.
    ///
    /// The day gate and the staleness rule share this input because a check now means a
    /// resolved outcome (§5): a refresh that found no value records one, so the gate still holds
    /// for the rest of the day, while a value that never reached Health Bridge records neither a
    /// check nor a send — and that metric has to be queried again anyway.
    var lastWindowTouchAt: [MetricID: Date] {
      freshness.lastCheckedAt.merging(freshness.lastSentAt) { checked, sent in
        max(checked, sent)
      }
    }
  }

  private func waitForSync(
    _ task: Task<BidirectionalSyncOutcome, Never>
  ) async -> BidirectionalSyncOutcome {
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func nextEligibleDate(trigger: SyncTrigger, requestDate: Date) async -> Date? {
    guard trigger.isAutomatic else { return nil }
    let frequency: BackgroundSyncFrequency
    do {
      let configuration = try await configurationStore.load()
      try configuration.validate()
      frequency = configuration.backgroundSyncFrequency
    } catch {
      frequency = .balanced
    }
    guard let snapshot = try? await statusStore.snapshot() else { return nil }
    return BackgroundSchedulePolicy(frequency: frequency).shouldThrottle(
      trigger: trigger,
      lastAttemptedAt: snapshot.lastAttemptedAt,
      lastFailure: snapshot.lastFailure,
      now: requestDate
    )
  }

  /// `deadline` is the wake's, not the run's: it expires a budget after the wake that asked for
  /// this run, however long the run waited to start. `resolution` is the scope this run was
  /// registered as covering, decided before it started so joiners are judged against it.
  private func perform(
    trigger: SyncTrigger,
    startedAt: Date,
    deadline: ExecutionDeadline?,
    resolution: ResolvedRun
  ) async -> BidirectionalSyncOutcome {
    // Whether anything ran before this, read before this run records its own attempt. The
    // starvation audit asks the status store rather than the freshness store, so a freshness
    // store that never writes — or cannot be read — cannot make the audit report nothing.
    let hasRunBefore = (try? await statusStore.snapshot())?.lastAttemptedAt != nil
    do {
      try await statusStore.recordAttempt(trigger: trigger, at: startedAt)
    } catch {
      return .performed(
        setupFailureReport(
          trigger: trigger,
          category: Task.isCancelled ? .cancelled : .checkpoint,
          startedAt: startedAt
        )
      )
    }

    let configuration: AppConfiguration
    do {
      configuration = try await configurationStore.load()
      try configuration.validate()
    } catch {
      return await finishSetupFailure(
        trigger: trigger,
        category: Task.isCancelled ? .cancelled : .configuration,
        startedAt: startedAt
      )
    }

    let context = await contextProvider?.currentContext()
    let selected = resolution.selectedMetrics ?? configuration.selectedMetrics
    // The selection is normally read before the run starts; a run that could not read it then
    // resolves its scope here, from the configuration it just loaded.
    let scope =
      resolution.scope
      ?? scopePolicy.scope(
        trigger: trigger,
        selected: selected,
        changedTypes: resolution.changedTypes,
        changedTypesKnown: resolution.changedTypesKnown,
        freshness: resolution.freshness,
        frequency: configuration.backgroundSyncFrequency,
        now: startedAt,
        calendar: calendar
      )

    async let outboundReport = outbound.sync(
      trigger: trigger,
      metrics: scope.metrics,
      deadline: deadline,
      includesMedications: scope.includesMedications,
      lastWindowTouchAt: resolution.lastWindowTouchAt,
      orderedMetrics: scope.orderedMetrics
    )
    async let inboundReport = inbound.sync(trigger: trigger, deadline: deadline)
    let (outboundReportValue, inboundReportValue) = await (outboundReport, inboundReport)

    let finishedAt = now()
    let freshnessWriteFailed = await recordFreshness(
      scope: scope,
      selected: selected,
      previous: resolution.freshness,
      outbound: outboundReportValue,
      finishedAt: finishedAt
    )

    let report = BidirectionalSyncReport(
      trigger: trigger,
      outbound: outboundReportValue,
      inbound: inboundReportValue,
      setupFailureCategory: setupCategory(freshnessWriteFailed: freshnessWriteFailed),
      startedAt: startedAt,
      finishedAt: finishedAt,
      context: context,
      scopeReason: scope.reason,
      requestedMetrics: scope.metrics.count,
      changedTypes: resolution.changedTypesKnown ? resolution.changedTypes.count : nil,
      starvedMetrics: scope.isFullSweep
        ? scopePolicy.starvedMetrics(
          selected: selected,
          freshness: resolution.freshness,
          hasRun: hasRunBefore,
          frequency: configuration.backgroundSyncFrequency,
          now: startedAt
        ).count
        : nil
    )
    return await finish(report)
  }

  /// Whether a locked device stopped the run before it could look at anything. Such a run
  /// defers no metrics, yet it swept nothing: recording it as a completed sweep would hide every
  /// metric it never checked behind a fresh `lastFullSweepAt`.
  private static func wasLocked(_ report: SyncReport) -> Bool {
    report.failures.contains { $0.category == .deviceLocked }
  }

  private func setupCategory(freshnessWriteFailed: Bool) -> SyncFailureCategory? {
    if Task.isCancelled { return .cancelled }
    return freshnessWriteFailed ? .checkpoint : nil
  }

  /// Writes what the run touched in one store call, and returns whether the write failed.
  ///
  /// Only metrics the run *resolved* are recorded as checked — sent successfully, or genuinely
  /// nothing to send and the anchor that produced committed. Being looked at is not enough: a
  /// metric collected with a value the deadline then abandoned is in `collectedMetricIDs` and
  /// not in `resolvedMetricIDs`, and stamping a check for it would call data that is still only
  /// on the phone fresh for the whole freshness interval, while the changed-type ledger that
  /// would have covered it was drained by this very run. A metric whose query failed is left out
  /// by the same rule, so the next run retries it and the starvation audit can surface one that
  /// never succeeds.
  private func recordFreshness(
    scope: SyncScope,
    selected: Set<MetricID>,
    previous: MetricFreshnessSnapshot,
    outbound report: SyncReport?,
    finishedAt: Date
  ) async -> Bool {
    guard let freshnessStore, let report else { return false }
    let update = MetricFreshnessUpdate(
      checked: report.resolvedMetricIDs,
      sent: report.synchronizedMetricIDs,
      at: finishedAt,
      selected: selected,
      rotationOffset: nextRotationOffset(
        scope: scope,
        selected: selected,
        previous: previous,
        report: report
      ),
      completedSweepAt: completedSweep(scope: scope, report: report) ? finishedAt : nil
    )
    // A run that learned nothing writes nothing, rather than spending a locked-device wake on an
    // encrypted read-modify-write that leaves the document identical.
    guard update.changes(previous) else { return false }
    do {
      try await freshnessStore.record(update)
      return false
    } catch {
      return true
    }
  }

  /// Where the next full sweep starts, or `nil` to leave the offset alone. A full sweep rotates
  /// as soon as it looked at anything, truncated or not: a sweep the budget always cuts short at
  /// the same point would otherwise restart from the same metric forever and never reach the tail
  /// of the selection. Scoped runs do not rotate.
  private func nextRotationOffset(
    scope: SyncScope,
    selected: Set<MetricID>,
    previous: MetricFreshnessSnapshot,
    report: SyncReport
  ) -> Int? {
    let visited = Self.visitedMetrics(report)
    guard scope.isFullSweep, !visited.isEmpty else { return nil }
    // Offsets index into the canonical selection order, never the rotated order this run
    // collected in.
    return scopePolicy.nextRotationOffset(
      after: scope.orderedMetrics.filter(visited.contains),
      selectedOrder: SyncScopePolicy.orderedSelection(selected),
      previous: previous.rotationOffset
    )
  }

  /// Every metric the run reached: the ones it collected, plus the ones whose query failed. Only
  /// the metrics the budget left untouched are missing, and those are what the next sweep starts
  /// on. A run that reached one metric and failed it has still made progress through the
  /// selection, even though it recorded no check.
  private static func visitedMetrics(_ report: SyncReport) -> Set<MetricID> {
    report.collectedMetricIDs.union(report.failures.compactMap(\.metricID))
  }

  /// Whether this run actually covered the whole selection. `collectedMetrics` is never compared
  /// with what was requested, because a metric may be unsupported or fail without the sweep being
  /// truncated; `deferredMetrics` is the truncation signal. A locked device, a cancelled run and
  /// a run that failed before collection — a blank webhook secret, say — all stop the run before
  /// it can look at what is left while deferring nothing, so a sweep must also have collected at
  /// least one metric: otherwise a run that collected nothing would stamp `lastFullSweepAt` and
  /// suppress the next sweep for the whole sweep interval.
  private func completedSweep(scope: SyncScope, report: SyncReport) -> Bool {
    scope.isFullSweep && report.collectedMetrics > 0 && report.deferredMetrics == 0
      && !Self.wasLocked(report) && !Task.isCancelled
  }

  private func finishSetupFailure(
    trigger: SyncTrigger,
    category: SyncFailureCategory,
    startedAt: Date
  ) async -> BidirectionalSyncOutcome {
    await finish(
      setupFailureReport(
        trigger: trigger,
        category: category,
        startedAt: startedAt
      )
    )
  }

  private func finish(_ report: BidirectionalSyncReport) async -> BidirectionalSyncOutcome {
    do {
      try await statusStore.record(report: report)
      return .performed(report)
    } catch {
      return .performed(
        BidirectionalSyncReport(
          trigger: report.trigger,
          outbound: report.outbound,
          inbound: report.inbound,
          setupFailureCategory: Task.isCancelled ? .cancelled : .checkpoint,
          startedAt: report.startedAt,
          finishedAt: now(),
          context: report.context,
          scopeReason: report.scopeReason,
          requestedMetrics: report.requestedMetrics,
          changedTypes: report.changedTypes,
          starvedMetrics: report.starvedMetrics
        )
      )
    }
  }

  private func setupFailureReport(
    trigger: SyncTrigger,
    category: SyncFailureCategory,
    startedAt: Date
  ) -> BidirectionalSyncReport {
    BidirectionalSyncReport(
      trigger: trigger,
      outbound: nil,
      inbound: nil,
      setupFailureCategory: category,
      startedAt: startedAt,
      finishedAt: now()
    )
  }
}
