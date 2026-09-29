import HealthSyncCore

struct ImportCheckpointAccess: PaidFeatureAccessing {
  let state: @Sendable () async -> PaidAccessState
  func accessState() async -> PaidAccessState { await state() }
}

actor ImportPaidAccessFixture: PaidFeatureAccessing {
  var state: PaidAccessState
  init(_ state: PaidAccessState = .unlocked) { self.state = state }
  func accessState() -> PaidAccessState { state }
  func revoke() { state = .locked }
}
