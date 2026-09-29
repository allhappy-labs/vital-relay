import Foundation

public enum ExecutionDeadlineError: Error, Equatable, Sendable {
  case exceeded
}

public struct ExecutionDeadline: Sendable, Equatable {
  public let expiresAt: Date

  public init(expiresAt: Date) {
    self.expiresAt = expiresAt
  }

  public func validate(wait: TimeInterval, now: Date) throws -> TimeInterval {
    guard wait >= 0, now <= expiresAt, now.addingTimeInterval(wait) <= expiresAt else {
      throw ExecutionDeadlineError.exceeded
    }
    return wait
  }

  public static let minimumRequestWindow: TimeInterval = 0.25
  public static let backgroundRequestTimeoutCeiling: TimeInterval = 10
  public static let defaultRequestTimeout: TimeInterval = 30

  public func remaining(now: Date) -> TimeInterval {
    expiresAt.timeIntervalSince(now)
  }

  public func requestTimeout(now: Date, ceiling: TimeInterval) throws -> TimeInterval {
    let remaining = remaining(now: now)
    guard remaining >= Self.minimumRequestWindow else {
      throw ExecutionDeadlineError.exceeded
    }
    return min(ceiling, remaining)
  }

  public static func requestTimeout(
    for deadline: ExecutionDeadline?,
    now: Date
  ) throws -> TimeInterval {
    guard let deadline else { return defaultRequestTimeout }
    return try deadline.requestTimeout(now: now, ceiling: backgroundRequestTimeoutCeiling)
  }
}
