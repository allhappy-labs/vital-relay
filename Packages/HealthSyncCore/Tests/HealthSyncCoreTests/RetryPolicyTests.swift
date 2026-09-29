import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Bounded retry policy")
struct RetryPolicyTests {
  private let policy = RetryPolicy(
    maximumAttempts: 3,
    baseDelay: 1,
    multiplier: 2,
    maximumDelay: 4,
    jitterFraction: 0.2
  )

  @Test("Uses exponential delays, cap, and bounded jitter")
  func exponentialDelays() {
    #expect(policy.delay(after: .timeout, completedAttempts: 1, jitterUnit: 0) == 1)
    #expect(policy.delay(after: .timeout, completedAttempts: 2, jitterUnit: 0) == 2)
    #expect(policy.delay(after: .timeout, completedAttempts: 3, jitterUnit: 0) == nil)
    #expect(policy.unjitteredDelay(completedAttempts: 4) == 4)
    #expect(policy.delay(after: .offline, completedAttempts: 1, jitterUnit: -1) == 0.8)
    #expect(policy.delay(after: .offline, completedAttempts: 1, jitterUnit: 1) == 1.2)
    #expect(policy.delay(after: .offline, completedAttempts: 1, jitterUnit: -10) == 0.8)
    #expect(policy.delay(after: .offline, completedAttempts: 1, jitterUnit: 10) == 1.2)
  }

  @Test("Bounds Retry-After and retries only transient failures")
  func classifications() {
    #expect(
      policy.delay(
        after: .rateLimited(retryAfter: 30),
        completedAttempts: 1,
        jitterUnit: 0
      ) == 4
    )
    let transient: [NetworkFailure] = [
      .timeout, .dnsFailure, .offline, .connectionLost, .rateLimited(retryAfter: nil),
      .server(statusCode: 503), .transport,
    ]
    for failure in transient {
      #expect(policy.delay(after: failure, completedAttempts: 1, jitterUnit: 0) != nil)
    }
    let terminal: [NetworkFailure] = [
      .cancelled, .tlsFailure, .unauthorized, .forbidden, .notFound, .validation,
      .malformedResponse, .protocolMismatch, .unexpectedStatus(statusCode: 418),
    ]
    for failure in terminal {
      #expect(policy.delay(after: failure, completedAttempts: 1, jitterUnit: 0) == nil)
    }
  }

  @Test("Deadline rejects sleeps that cannot finish in time")
  func deadline() throws {
    let now = Date(timeIntervalSince1970: 100)
    let deadline = ExecutionDeadline(expiresAt: now.addingTimeInterval(2))
    #expect(try deadline.validate(wait: 2, now: now) == 2)
    #expect(throws: ExecutionDeadlineError.exceeded) {
      try deadline.validate(wait: 2.1, now: now)
    }
    #expect(throws: ExecutionDeadlineError.exceeded) {
      try deadline.validate(wait: 0, now: now.addingTimeInterval(3))
    }
  }
}
