public struct PaidSyncCoordinator: BidirectionalSyncCoordinating {
  private let base: any BidirectionalSyncCoordinating
  private let access: any PaidFeatureAccessing

  public init(base: any BidirectionalSyncCoordinating, access: any PaidFeatureAccessing) {
    self.base = base
    self.access = access
  }

  public func sync(trigger: SyncTrigger) async -> BidirectionalSyncOutcome {
    guard await isAllowed(trigger) else { return .requiresPurchase }
    return await base.sync(trigger: trigger)
  }

  public func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>
  ) async -> BidirectionalSyncOutcome {
    guard await isAllowed(trigger) else { return .requiresPurchase }
    return await base.sync(trigger: trigger, changedTypes: changedTypes)
  }

  private func isAllowed(_ trigger: SyncTrigger) async -> Bool {
    switch trigger {
    case .manual, .pullToRefresh:
      true
    case .background, .shortcut, .healthKitObserver, .appRefresh:
      await access.accessState() == .unlocked
    }
  }
}
