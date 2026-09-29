import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Paid sync execution gate")
struct PaidSyncCoordinatorTests {
  private let triggers: [SyncTrigger] = [
    .manual, .pullToRefresh, .background, .shortcut, .healthKitObserver, .appRefresh,
  ]

  @Test("Every trigger uses the purchase rule at execution for both coordinator overloads")
  func triggerMatrix() async {
    let states: [PaidAccessState] = [.checking, .locked, .unavailable, .unlocked]
    let changedTypes: Set<HealthObjectTypeID> = [.stepCount]
    for state in states {
      for trigger in triggers {
        let base = PaidSyncBase()
        let coordinator = PaidSyncCoordinator(base: base, access: MutablePaidAccess(state))
        let allowed = trigger == .manual || trigger == .pullToRefresh || state == .unlocked

        let plain = await coordinator.sync(trigger: trigger)
        let scoped = await coordinator.sync(trigger: trigger, changedTypes: changedTypes)

        #expect(plain == (allowed ? .throttled(nextEligibleAt: .distantFuture) : .requiresPurchase))
        #expect(
          scoped == (allowed ? .throttled(nextEligibleAt: .distantFuture) : .requiresPurchase))
        let calls = await base.calls
        #expect(calls.count == (allowed ? 2 : 0))
        if allowed {
          #expect(calls[0].trigger == trigger)
          #expect(calls[0].changedTypes == nil)
          #expect(calls[1].trigger == trigger)
          #expect(calls[1].changedTypes == changedTypes)
        }
      }
    }
  }

  @Test("A refund between queued calls blocks the second paid execution")
  func refundBetweenCalls() async {
    let base = PaidSyncBase()
    let access = MutablePaidAccess(.unlocked)
    let coordinator = PaidSyncCoordinator(base: base, access: access)

    #expect(
      await coordinator.sync(trigger: .background) == .throttled(nextEligibleAt: .distantFuture))
    await access.set(.locked)
    #expect(await coordinator.sync(trigger: .background) == .requiresPurchase)
    #expect(await base.calls.count == 1)
  }
}

private actor MutablePaidAccess: PaidFeatureAccessing {
  private var state: PaidAccessState
  init(_ state: PaidAccessState) { self.state = state }
  func accessState() -> PaidAccessState { state }
  func set(_ state: PaidAccessState) { self.state = state }
}

private actor PaidSyncBase: BidirectionalSyncCoordinating {
  struct Call: Sendable {
    let trigger: SyncTrigger
    let changedTypes: Set<HealthObjectTypeID>?
  }

  private(set) var calls: [Call] = []

  func sync(trigger: SyncTrigger) -> BidirectionalSyncOutcome {
    calls.append(.init(trigger: trigger, changedTypes: nil))
    return .throttled(nextEligibleAt: .distantFuture)
  }

  func sync(trigger: SyncTrigger, changedTypes: Set<HealthObjectTypeID>) -> BidirectionalSyncOutcome
  {
    calls.append(.init(trigger: trigger, changedTypes: changedTypes))
    return .throttled(nextEligibleAt: .distantFuture)
  }
}
