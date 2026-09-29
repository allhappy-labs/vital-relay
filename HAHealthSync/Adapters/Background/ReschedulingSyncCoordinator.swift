import HealthSyncCore

final class ReschedulingSyncCoordinator: BidirectionalSyncCoordinating {
  private let base: any BidirectionalSyncCoordinating
  private let onOutcome: @Sendable (SyncTrigger, BidirectionalSyncOutcome) async -> Void

  init(
    base: any BidirectionalSyncCoordinating,
    onOutcome: @escaping @Sendable (SyncTrigger, BidirectionalSyncOutcome) async -> Void
  ) {
    self.base = base
    self.onOutcome = onOutcome
  }

  func sync(trigger: SyncTrigger) async -> BidirectionalSyncOutcome {
    let outcome = await base.sync(trigger: trigger)
    await onOutcome(trigger, outcome)
    return outcome
  }

  /// Overridden rather than left to the protocol's default, which drops the changed types: this
  /// decorator wraps every production run, so taking the default would make every observer wake
  /// an unknown change and no run would ever be scoped.
  func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>
  ) async -> BidirectionalSyncOutcome {
    let outcome = await base.sync(trigger: trigger, changedTypes: changedTypes)
    await onOutcome(trigger, outcome)
    return outcome
  }
}
