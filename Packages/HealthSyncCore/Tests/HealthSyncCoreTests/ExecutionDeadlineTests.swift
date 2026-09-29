import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Execution deadline")
struct ExecutionDeadlineTests {
  private let now = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Request timeout is capped by the ceiling and the remaining budget")
  func requestTimeout() throws {
    let deadline = ExecutionDeadline(expiresAt: now.addingTimeInterval(25))
    #expect(deadline.remaining(now: now) == 25)
    #expect(try deadline.requestTimeout(now: now, ceiling: 10) == 10)
    #expect(try deadline.requestTimeout(now: now.addingTimeInterval(21), ceiling: 10) == 4)
  }

  @Test("No request starts inside the minimum window")
  func minimumWindow() {
    let deadline = ExecutionDeadline(expiresAt: now.addingTimeInterval(0.2))
    #expect(throws: ExecutionDeadlineError.exceeded) {
      try deadline.requestTimeout(now: now, ceiling: 10)
    }
  }

  @Test("Unbounded runs keep the default request timeout")
  func unbounded() throws {
    #expect(try ExecutionDeadline.requestTimeout(for: nil, now: now) == 30)
    let deadline = ExecutionDeadline(expiresAt: now.addingTimeInterval(25))
    #expect(try ExecutionDeadline.requestTimeout(for: deadline, now: now) == 10)
  }
}
