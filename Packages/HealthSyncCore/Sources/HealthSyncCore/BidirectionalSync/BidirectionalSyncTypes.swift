import Foundation

public struct BidirectionalSyncReport: Sendable, Equatable {
  public let trigger: SyncTrigger
  public let outbound: SyncReport?
  public let inbound: InboundSyncReport?
  public let setupFailureCategory: SyncFailureCategory?
  public let startedAt: Date
  public let finishedAt: Date
  public let context: SyncRunContext?
  /// Why the run covered what it covered, `nil` when no scope was resolved for it.
  public let scopeReason: SyncScopeReason?
  /// How many metrics the resolved scope asked the outbound run to cover.
  public let requestedMetrics: Int?
  /// How many changed types the run was scoped from. `nil` means the caller named no set at
  /// all, which the policy treats as an unknown change; `0` means it named an empty one.
  public let changedTypes: Int?
  /// How many selected metrics had gone unchecked for longer than the starvation interval when
  /// this full sweep started. `nil` on a scoped run, which is not meant to cover everything.
  public let starvedMetrics: Int?

  public init(
    trigger: SyncTrigger,
    outbound: SyncReport?,
    inbound: InboundSyncReport?,
    setupFailureCategory: SyncFailureCategory? = nil,
    startedAt: Date,
    finishedAt: Date,
    context: SyncRunContext? = nil,
    scopeReason: SyncScopeReason? = nil,
    requestedMetrics: Int? = nil,
    changedTypes: Int? = nil,
    starvedMetrics: Int? = nil
  ) {
    self.trigger = trigger
    self.outbound = outbound
    self.inbound = inbound
    self.setupFailureCategory = setupFailureCategory
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.context = context
    self.scopeReason = scopeReason
    self.requestedMetrics = requestedMetrics
    self.changedTypes = changedTypes
    self.starvedMetrics = starvedMetrics
  }

  public var firstFailureCategory: SyncFailureCategory? {
    setupFailureCategory
      ?? outbound?.failures.first?.category
      ?? inbound?.failures.first?.category
  }

  public var failureCategories: [SyncFailureCategory] {
    [setupFailureCategory].compactMap { $0 }
      + (outbound?.failures.map(\.category) ?? [])
      + (inbound?.failures.map(\.category) ?? [])
  }

  public var succeeded: Bool {
    firstFailureCategory == nil
  }
}

public enum BidirectionalSyncOutcome: Sendable, Equatable {
  case performed(BidirectionalSyncReport)
  case throttled(nextEligibleAt: Date)
  case requiresPurchase
}

public protocol BidirectionalSyncCoordinating: Sendable {
  func sync(trigger: SyncTrigger) async -> BidirectionalSyncOutcome
  /// Runs for the HealthKit object types the observer reported as changed. Passing the types is
  /// what lets the run be scoped: a caller that names none is treated as an unknown change and
  /// gets a full sweep.
  func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>
  ) async -> BidirectionalSyncOutcome
}

extension BidirectionalSyncCoordinating {
  public func sync(
    trigger: SyncTrigger,
    changedTypes: Set<HealthObjectTypeID>
  ) async -> BidirectionalSyncOutcome {
    await sync(trigger: trigger)
  }
}
