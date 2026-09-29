import BackgroundTasks
import Foundation
import HealthSyncCore
import os

@MainActor
protocol AppRefreshLaunchDelegate: AnyObject {
  func waitUntilReady() async
  func isBackgroundWorkEligible() async -> Bool
  func performRefreshSync() async -> BidirectionalSyncOutcome
}

@MainActor
protocol AppRefreshControlling: AnyObject {
  var launchDelegate: (any AppRefreshLaunchDelegate)? { get set }
  @discardableResult func register() -> Bool
  func reconcile(enabled: Bool, earliestBeginDate: Date?, retryInterval: TimeInterval)
}

protocol AppRefreshTaskHandle: AnyObject, Sendable {
  func setExpirationHandler(_ handler: @escaping @Sendable () -> Void)
  func setTaskCompleted(success: Bool)
}

protocol AppRefreshScheduling: Sendable {
  func register(
    identifier: String,
    launchHandler: @escaping @Sendable (any AppRefreshTaskHandle) -> Void
  ) -> Bool
  func submit(identifier: String, earliestBeginDate: Date) throws
  func cancel(identifier: String)
}

final class RefreshTaskRun: @unchecked Sendable {
  private let lock = NSLock()
  private let handle: any AppRefreshTaskHandle
  private var isCompleted = false
  private var isExpired = false
  private var work: Task<Void, Never>?

  init(handle: any AppRefreshTaskHandle) {
    self.handle = handle
  }

  func attach(_ task: Task<Void, Never>) {
    let expired = lock.withLock {
      if !isExpired { work = task }
      return isExpired
    }
    if expired { task.cancel() }
  }

  func expire() {
    let task = lock.withLock {
      isExpired = true
      return work
    }
    task?.cancel()
    complete(success: false)
  }

  func complete(success: Bool) {
    let shouldComplete = lock.withLock {
      guard !isCompleted else { return false }
      isCompleted = true
      return true
    }
    if shouldComplete {
      handle.setTaskCompleted(success: success)
    }
  }
}

final class LockedTimeInterval: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: TimeInterval

  init(_ value: TimeInterval) {
    storedValue = value
  }

  var value: TimeInterval {
    get { lock.withLock { storedValue } }
    set { lock.withLock { storedValue = newValue } }
  }
}

@MainActor
final class AppRefreshManager: AppRefreshControlling {
  nonisolated static let identifier = "com.marynavdovenko.HAHealthSync.refresh"

  weak var launchDelegate: (any AppRefreshLaunchDelegate)?
  private let scheduler: any AppRefreshScheduling
  private let now: @Sendable () -> Date
  private let logger: Logger
  private let expirationRetryInterval = LockedTimeInterval(
    BackgroundSchedulePolicy.maximumRetryInterval
  )
  private var activeTask: Task<Void, Never>?
  private(set) var isRegistered = false

  init(
    scheduler: any AppRefreshScheduling,
    now: @escaping @Sendable () -> Date = { Date() },
    logger: Logger = BackgroundLog.logger
  ) {
    self.scheduler = scheduler
    self.now = now
    self.logger = logger
  }

  @discardableResult
  func register() -> Bool {
    guard !isRegistered else { return true }
    let scheduler = scheduler
    let now = now
    let logger = logger
    let retryInterval = expirationRetryInterval
    isRegistered = scheduler.register(identifier: Self.identifier) { [weak self] handle in
      let run = RefreshTaskRun(handle: handle)
      handle.setExpirationHandler {
        logger.notice("Refresh task expired")
        do {
          try scheduler.submit(
            identifier: Self.identifier,
            earliestBeginDate: now().addingTimeInterval(retryInterval.value)
          )
        } catch {
          logger.error(
            "Refresh resubmit after expiry failed: \(String(describing: error), privacy: .public)")
        }
        run.expire()
      }
      Task { @MainActor [weak self] in
        guard let self else {
          run.complete(success: false)
          return
        }
        self.handle(run)
      }
    }
    if !isRegistered {
      logger.error("Refresh task registration failed")
    }
    return isRegistered
  }

  func reconcile(enabled: Bool, earliestBeginDate: Date?, retryInterval: TimeInterval) {
    expirationRetryInterval.value = retryInterval
    guard enabled, isRegistered else {
      scheduler.cancel(identifier: Self.identifier)
      activeTask?.cancel()
      activeTask = nil
      return
    }
    let date = earliestBeginDate ?? now().addingTimeInterval(retryInterval)
    do {
      try scheduler.submit(identifier: Self.identifier, earliestBeginDate: date)
      logger.info("Refresh submitted")
    } catch {
      logger.error("Refresh submit failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func handle(_ run: RefreshTaskRun) {
    logger.info("Refresh task launched")
    activeTask?.cancel()
    let work = Task { @MainActor [weak self] in
      guard let delegate = self?.launchDelegate else {
        run.complete(success: false)
        return
      }
      await delegate.waitUntilReady()
      guard !Task.isCancelled else {
        run.complete(success: false)
        return
      }
      guard await delegate.isBackgroundWorkEligible() else {
        self?.logger.info("Refresh task skipped: background work not eligible")
        run.complete(success: true)
        return
      }
      guard !Task.isCancelled else {
        run.complete(success: false)
        return
      }
      let outcome = await delegate.performRefreshSync()
      switch outcome {
      case .performed(let report):
        run.complete(success: report.succeeded)
      case .throttled:
        run.complete(success: true)
      case .requiresPurchase:
        run.complete(success: true)
      }
    }
    activeTask = work
    run.attach(work)
  }
}

final class BGAppRefreshTaskHandle: AppRefreshTaskHandle, @unchecked Sendable {
  private let task: BGAppRefreshTask

  init(task: BGAppRefreshTask) {
    self.task = task
  }

  func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
    task.expirationHandler = handler
  }

  func setTaskCompleted(success: Bool) {
    task.setTaskCompleted(success: success)
  }
}

struct BGTaskSchedulerAdapter: AppRefreshScheduling, @unchecked Sendable {
  private let scheduler: BGTaskScheduler

  init(scheduler: BGTaskScheduler = .shared) {
    self.scheduler = scheduler
  }

  func register(
    identifier: String,
    launchHandler: @escaping @Sendable (any AppRefreshTaskHandle) -> Void
  ) -> Bool {
    scheduler.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      launchHandler(BGAppRefreshTaskHandle(task: refreshTask))
    }
  }

  func submit(identifier: String, earliestBeginDate: Date) throws {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = earliestBeginDate
    try scheduler.submit(request)
  }

  func cancel(identifier: String) {
    scheduler.cancel(taskRequestWithIdentifier: identifier)
  }
}
