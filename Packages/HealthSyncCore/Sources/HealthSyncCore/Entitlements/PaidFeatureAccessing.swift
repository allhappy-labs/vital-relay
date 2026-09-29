public enum PaidAccessState: Sendable, Equatable {
  case checking
  case locked
  case unlocked
  case unavailable
}

public protocol PaidFeatureAccessing: Sendable {
  func accessState() async -> PaidAccessState
}
