import Foundation

public struct RetryPolicy: Sendable, Equatable {
  public static let `default` = RetryPolicy()

  public let maximumAttempts: Int
  public let baseDelay: TimeInterval
  public let multiplier: Double
  public let maximumDelay: TimeInterval
  public let jitterFraction: Double

  public init(
    maximumAttempts: Int = 3,
    baseDelay: TimeInterval = 1,
    multiplier: Double = 2,
    maximumDelay: TimeInterval = 4,
    jitterFraction: Double = 0.2
  ) {
    self.maximumAttempts = max(1, maximumAttempts)
    self.baseDelay = max(0, baseDelay)
    self.multiplier = max(1, multiplier)
    self.maximumDelay = max(0, maximumDelay)
    self.jitterFraction = min(max(0, jitterFraction), 1)
  }

  public func delay(
    after failure: NetworkFailure,
    completedAttempts: Int,
    jitterUnit: Double
  ) -> TimeInterval? {
    guard completedAttempts < maximumAttempts, isRetryable(failure) else {
      return nil
    }
    let rawDelay: TimeInterval
    if case .rateLimited(let retryAfter) = failure, let retryAfter {
      rawDelay = min(max(0, retryAfter), maximumDelay)
    } else {
      rawDelay = unjitteredDelay(completedAttempts: completedAttempts)
    }
    let boundedJitter = min(max(jitterUnit, -1), 1)
    return rawDelay * (1 + jitterFraction * boundedJitter)
  }

  public func unjitteredDelay(completedAttempts: Int) -> TimeInterval {
    let exponent = max(0, completedAttempts - 1)
    return min(baseDelay * pow(multiplier, Double(exponent)), maximumDelay)
  }

  private func isRetryable(_ failure: NetworkFailure) -> Bool {
    switch failure {
    case .timeout, .dnsFailure, .offline, .connectionLost, .rateLimited, .server, .transport:
      true
    case .cancelled, .tlsFailure, .unauthorized, .forbidden, .notFound, .validation,
      .malformedResponse, .protocolMismatch, .unexpectedStatus:
      false
    }
  }
}

public protocol SyncSleeper: Sendable {
  func sleep(for delay: TimeInterval) async throws
}

public struct ContinuousSyncSleeper: SyncSleeper {
  public init() {}

  public func sleep(for delay: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(delay))
  }
}

public protocol JitterSource: Sendable {
  func nextUnit() async -> Double
}

public actor SystemJitterSource: JitterSource {
  public init() {}

  public func nextUnit() -> Double {
    Double.random(in: -1...1)
  }
}
