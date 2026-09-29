import Foundation
import HealthSyncCore

@testable import HAHealthSync

final class FakeAppRefreshScheduler: AppRefreshScheduling, @unchecked Sendable {
  struct Submission: Equatable {
    let identifier: String
    let date: Date
  }

  private let lock = NSLock()
  private var storedSubmissions: [Submission] = []
  private var storedCancellations: [String] = []
  private var handler: (@Sendable (any AppRefreshTaskHandle) -> Void)?

  var submissions: [Submission] { lock.withLock { storedSubmissions } }
  var cancellations: [String] { lock.withLock { storedCancellations } }

  func register(
    identifier: String,
    launchHandler: @escaping @Sendable (any AppRefreshTaskHandle) -> Void
  ) -> Bool {
    lock.withLock { handler = launchHandler }
    return true
  }

  func submit(identifier: String, earliestBeginDate: Date) {
    lock.withLock {
      storedSubmissions.append(Submission(identifier: identifier, date: earliestBeginDate))
    }
  }

  func cancel(identifier: String) {
    lock.withLock { storedCancellations.append(identifier) }
  }

  func launch(_ task: FakeAppRefreshTask) {
    lock.withLock { handler }?(task)
  }
}

final class FakeAppRefreshTask: AppRefreshTaskHandle, @unchecked Sendable {
  private let lock = NSLock()
  private var expirationHandler: (@Sendable () -> Void)?
  private var storedCompletions: [Bool] = []

  var completions: [Bool] { lock.withLock { storedCompletions } }

  func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
    lock.withLock { expirationHandler = handler }
  }

  func setTaskCompleted(success: Bool) {
    lock.withLock { storedCompletions.append(success) }
  }

  func expire() {
    lock.withLock { expirationHandler }?()
  }
}

@MainActor
func waitUntil(
  timeout: Duration = .seconds(2),
  _ condition: @escaping () async -> Bool
) async -> Bool {
  let clock = ContinuousClock()
  let end = clock.now.advanced(by: timeout)
  while clock.now < end {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return await condition()
}
