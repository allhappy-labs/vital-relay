import Foundation

/// Why a run covers the metrics it covers.
public enum SyncScopeReason: String, Codable, Sendable {
  case trigger
  case firstRunAfterLaunch
  case sweepDue
  case dayRollover
  case unknownChange
  case changedTypes
  case staleMetrics
}

/// What a single sync run covers, decided once before the run starts.
public struct SyncScope: Sendable, Equatable {
  /// The metrics the run covers, in the order they should be collected.
  public let orderedMetrics: [MetricID]
  public let metrics: Set<MetricID>
  public let isFullSweep: Bool
  public let includesMedications: Bool
  public let reason: SyncScopeReason

  public init(
    orderedMetrics: [MetricID],
    isFullSweep: Bool,
    includesMedications: Bool,
    reason: SyncScopeReason
  ) {
    self.orderedMetrics = orderedMetrics
    metrics = Set(orderedMetrics)
    self.isFullSweep = isFullSweep
    self.includesMedications = includesMedications
    self.reason = reason
  }
}

/// Decides what each sync run covers. A full sweep covers every selected metric; a scoped run
/// covers the metrics of the types HealthKit reported as changed plus anything that has gone
/// stale. The type is pure: every input, including `now` and the calendar, is passed in.
public struct SyncScopePolicy: Sendable, Equatable {
  public static let defaultFreshnessInterval: TimeInterval = 3_600
  /// How many background cycles pass between full sweeps.
  private static let sweepCycles: Double = 4
  private static let minimumSweepInterval: TimeInterval = 30 * 60
  private static let maximumSweepInterval: TimeInterval = 24 * 60 * 60

  /// How long a metric stays fresh after being checked. Fixed, unlike the sweep and starvation
  /// intervals: it is the data-recency guarantee the app makes to Home Assistant ("within one
  /// hour"), not a cadence, so the background frequency must not move it.
  public let freshnessInterval: TimeInterval
  /// The object type whose changes mean medications need syncing. `MetricRegistry` has no
  /// medication entry, so this stays `nil` until the app can name one; medications then sync on
  /// full sweeps only.
  public let medicationObjectType: HealthObjectTypeID?

  public init(
    freshnessInterval: TimeInterval = SyncScopePolicy.defaultFreshnessInterval,
    medicationObjectType: HealthObjectTypeID? = nil
  ) {
    self.freshnessInterval = freshnessInterval
    self.medicationObjectType = medicationObjectType
  }

  /// How long after a full sweep the next one becomes due: four of the configured background
  /// cycles, never under 30 minutes and never over 24 hours.
  ///
  /// A fixed hour only sweeps sparingly while wakes are far more frequent than that. iOS wakes a
  /// budget-limited phone 3–5 hours apart, so every wake arrived past a fixed hour, every wake
  /// swept, and the scoped run this policy exists to produce never happened once. Counting in
  /// cycles keeps the ratio whatever the cadence is: four cycles leaves three cheap scoped runs
  /// between sweeps. The floor stops Responsive (5 min) sweeping every 20 minutes, which would
  /// cost more than scoping saves; the ceiling stops Daily's four cycles from meaning a sweep
  /// every four days, far longer than any metric should go unswept.
  public func sweepInterval(for frequency: BackgroundSyncFrequency) -> TimeInterval {
    min(
      max(Self.sweepCycles * frequency.minimumInterval, Self.minimumSweepInterval),
      Self.maximumSweepInterval
    )
  }

  /// How long a metric may go unchecked before a run reports it as starved: two freshness
  /// intervals, or two of the configured background cadence when that is longer.
  ///
  /// A fixed two hours is only right while wakes are at most an hour apart. `lastCheckedAt` is
  /// written at the end of the *previous* run, so on Daily (24 h) every metric is more than two
  /// hours stale on every sweep and the audit would permanently name the whole selection; Battery
  /// Saver (1 h) sits exactly on the boundary. Scaling with the cadence keeps the audit a report
  /// of runs that are not happening rather than of a cadence the user chose.
  public func starvationInterval(for frequency: BackgroundSyncFrequency) -> TimeInterval {
    max(2 * freshnessInterval, 2 * frequency.minimumInterval)
  }

  /// The canonical collection order of a selection: `MetricRegistry.selectable` order.
  public static func orderedSelection(_ selected: Set<MetricID>) -> [MetricID] {
    MetricRegistry.selectable.map(\.id).filter(selected.contains)
  }

  public func scope(
    trigger: SyncTrigger,
    selected: Set<MetricID>,
    changedTypes: Set<HealthObjectTypeID>,
    changedTypesKnown: Bool,
    freshness: MetricFreshnessSnapshot,
    frequency: BackgroundSyncFrequency,
    now: Date,
    calendar: Calendar
  ) -> SyncScope {
    let order = Self.orderedSelection(selected)
    if let reason = fullSweepReason(
      trigger: trigger,
      changedTypes: changedTypes,
      changedTypesKnown: changedTypesKnown,
      freshness: freshness,
      frequency: frequency,
      now: now,
      calendar: calendar
    ) {
      return SyncScope(
        orderedMetrics: rotated(order, by: freshness.rotationOffset),
        isFullSweep: true,
        includesMedications: true,
        reason: reason
      )
    }

    let changed = metrics(of: changedTypes, within: selected)
    let stale = staleMetrics(selected: selected, freshness: freshness, now: now)
    let covered = changed.union(stale)
    return SyncScope(
      orderedMetrics: order.filter(covered.contains),
      isFullSweep: false,
      includesMedications: medicationObjectType.map(changedTypes.contains) ?? false,
      reason: stale.isSubset(of: changed) ? .changedTypes : .staleMetrics
    )
  }

  /// Selected metrics that have gone unchecked for longer than `starvationInterval(for:)`.
  ///
  /// Only metrics the registry still offers are audited: a selection persisted by an older app
  /// version can name one a later version removed, and no run will ever check it.
  ///
  /// A metric that has never been checked counts as starved once anything has run at all.
  /// `hasRun` comes from the caller's own record of past attempts, not from the freshness
  /// snapshot, because the states worth reporting are exactly the ones where that snapshot is
  /// empty: a sweep the budget always truncates never completes, a run whose only reached metric
  /// always fails records no check, and a freshness store that cannot be read looks brand new on
  /// every wake. Deciding from freshness alone would report nothing starved in all three.
  /// Freshness the snapshot does carry still counts, so the audit can only over-report.
  public func starvedMetrics(
    selected: Set<MetricID>,
    freshness: MetricFreshnessSnapshot,
    hasRun: Bool,
    frequency: BackgroundSyncFrequency,
    now: Date
  ) -> Set<MetricID> {
    let hasRun = hasRun || freshness.lastFullSweepAt != nil || !freshness.lastCheckedAt.isEmpty
    let threshold = starvationInterval(for: frequency)
    return selected.intersection(Self.selectableMetrics).filter { metric in
      guard let checkedAt = freshness.lastCheckedAt[metric] else { return hasRun }
      return now.timeIntervalSince(checkedAt) >= threshold
    }
  }

  /// The offset the next full sweep starts from: one past the last metric this run looked at,
  /// wrapping at the end of the selection. A run that looked at nothing leaves the offset alone.
  ///
  /// `visited` is every metric the run reached, whether its query succeeded or failed — a run
  /// whose only reached metric fails must still move the start point, or a metric that always
  /// fails pins every later sweep to itself and the tail of the selection is never reached.
  /// Rotating past a failed metric does not exclude it from the next run: it stays stale, so
  /// §4 rule 2 pulls it back in.
  ///
  /// Offsets index into the canonical `orderedSelection(_:)` order, so `selectedOrder` must be
  /// that order — never the rotated order a run collected in. `visited` is in collection order;
  /// only its last element matters.
  public func nextRotationOffset(
    after visited: [MetricID],
    selectedOrder: [MetricID],
    previous: Int
  ) -> Int {
    guard !selectedOrder.isEmpty,
      let last = visited.last,
      let index = selectedOrder.firstIndex(of: last)
    else {
      return previous
    }
    return (index + 1) % selectedOrder.count
  }

  private static let selectableMetrics = Set(MetricRegistry.selectable.map(\.id))

  /// The first rule of the spec's order that applies, or `nil` for a scoped run.
  private func fullSweepReason(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>,
    changedTypesKnown: Bool,
    freshness: MetricFreshnessSnapshot,
    frequency: BackgroundSyncFrequency,
    now: Date,
    calendar: Calendar
  ) -> SyncScopeReason? {
    if trigger.isFullSweepTrigger { return .trigger }
    guard let lastFullSweepAt = freshness.lastFullSweepAt else { return .firstRunAfterLaunch }
    if now.timeIntervalSince(lastFullSweepAt) >= sweepInterval(for: frequency) { return .sweepDue }
    if !calendar.isDate(now, inSameDayAs: lastFullSweepAt) { return .dayRollover }
    if !changedTypesKnown || changedTypes.isEmpty { return .unknownChange }
    return nil
  }

  private func metrics(
    of types: Set<HealthObjectTypeID>,
    within selected: Set<MetricID>
  ) -> Set<MetricID> {
    guard !types.isEmpty else { return [] }
    return selected.filter { metric in
      guard let definition = MetricRegistry[metric] else { return false }
      return types.contains(definition.healthObjectType)
    }
  }

  private func staleMetrics(
    selected: Set<MetricID>,
    freshness: MetricFreshnessSnapshot,
    now: Date
  ) -> Set<MetricID> {
    selected.filter { metric in
      guard let checkedAt = freshness.lastCheckedAt[metric] else { return true }
      return now.timeIntervalSince(checkedAt) >= freshnessInterval
    }
  }

  private func rotated(_ order: [MetricID], by offset: Int) -> [MetricID] {
    guard order.count > 1 else { return order }
    let start = ((offset % order.count) + order.count) % order.count
    guard start != 0 else { return order }
    return Array(order[start...] + order[..<start])
  }
}
