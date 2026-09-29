import Foundation
import HealthSyncCore
import os

@MainActor
protocol BackgroundSyncRuntimeControlling: AnyObject {
  func reconcile() async
  func suspend() async
}

@MainActor
private final class RuntimeOutcomeForwarder {
  weak var runtime: BackgroundSyncRuntime?

  func forward(_ trigger: SyncTrigger, _ outcome: BidirectionalSyncOutcome) async {
    await runtime?.handleOutcome(trigger: trigger, outcome: outcome)
  }
}

@MainActor
final class BackgroundSyncRuntime: BackgroundSyncRuntimeControlling, AppRefreshLaunchDelegate {
  let coordinator: any BidirectionalSyncCoordinating
  private let observerManager: any BackgroundSyncManaging
  private let refreshManager: any AppRefreshControlling
  private let configurationStore: any ConfigurationStore
  private let access: any PaidFeatureAccessing
  private let credentialStore: any CredentialStore
  private let statusStore: any SyncStatusStore
  private let publisher: (any SyncAttemptPublishing)?
  private let now: @Sendable () -> Date
  private let logger: Logger
  private var latestTask: Task<Void, Never>?
  private var isStarted = false
  private var policy = BackgroundSchedulePolicy(frequency: .balanced)
  private var lastHandledStartedAt: Date?
  private(set) var isEligible = false

  init(
    access: any PaidFeatureAccessing,
    baseCoordinator: any BidirectionalSyncCoordinating,
    makeObserverManager: (any BidirectionalSyncCoordinating) -> any BackgroundSyncManaging,
    refreshManager: any AppRefreshControlling,
    configurationStore: any ConfigurationStore,
    credentialStore: any CredentialStore,
    statusStore: any SyncStatusStore,
    publisher: (any SyncAttemptPublishing)? = nil,
    now: @escaping @Sendable () -> Date = { Date() },
    logger: Logger = BackgroundLog.logger
  ) {
    let forwarder = RuntimeOutcomeForwarder()
    let decorated = ReschedulingSyncCoordinator(base: baseCoordinator) { trigger, outcome in
      await forwarder.forward(trigger, outcome)
    }
    let gated = PaidSyncCoordinator(base: decorated, access: access)
    coordinator = gated
    observerManager = makeObserverManager(gated)
    self.access = access
    self.refreshManager = refreshManager
    self.configurationStore = configurationStore
    self.credentialStore = credentialStore
    self.statusStore = statusStore
    self.publisher = publisher
    self.now = now
    self.logger = logger
    forwarder.runtime = self
  }

  func start() {
    guard !isStarted else { return }
    isStarted = true
    refreshManager.launchDelegate = self
    refreshManager.register()
    logger.info("Background runtime started")
    latestTask = Task { await self.reconcileFromStores(isBootstrap: true) }
  }

  func reconcile() async {
    await enqueue { await $0.reconcileFromStores(isBootstrap: false) }
  }

  func suspend() async {
    await enqueue { runtime in
      runtime.isEligible = false
      await runtime.observerManager.stopAll()
      runtime.refreshManager.reconcile(
        enabled: false,
        earliestBeginDate: nil,
        retryInterval: runtime.policy.retryInterval
      )
    }
  }

  func waitUntilReady() async {
    while let task = latestTask {
      await task.value
      if task == latestTask { return }
    }
  }

  func isBackgroundWorkEligible() async -> Bool {
    await loadEligibility()?.isEligible ?? false
  }

  func performRefreshSync() async -> BidirectionalSyncOutcome {
    await coordinator.sync(trigger: .appRefresh)
  }

  func handleOutcome(trigger: SyncTrigger, outcome: BidirectionalSyncOutcome) async {
    // Every caller that shared one run reports the same outcome; handle that run once.
    if case .performed(let report) = outcome {
      guard report.startedAt != lastHandledStartedAt else { return }
      lastHandledStartedAt = report.startedAt
    }
    if case .throttled = outcome {
      logger.info("Throttled \(trigger.rawValue, privacy: .public) wake")
    }
    if case .performed(let report) = outcome, let scope = BackgroundLog.scopeMessage(for: report) {
      logger.info("\(scope, privacy: .public)")
    }
    // Cancelled runs resubmit at the retry interval so the refresh chain survives a shared
    // run cancelled by another caller. `suspend()` clears eligibility before it cancels work.
    if isEligible {
      refreshManager.reconcile(
        enabled: true,
        earliestBeginDate: policy.nextRefreshDate(after: outcome, now: now()),
        retryInterval: policy.retryInterval
      )
    }
    guard case .performed(let report) = outcome, let publisher else { return }
    let recorded = try? await statusStore.snapshot().recentEvents.last
    let event: SyncStatusEvent
    if let recorded, recorded.startedAt == report.startedAt {
      event = recorded
    } else {
      event = SyncStatusEvent(report: report)
    }
    let deadline = report.trigger.budget.map {
      ExecutionDeadline(expiresAt: report.startedAt.addingTimeInterval($0))
    }
    await publish(event, deadline: deadline, with: publisher)
  }

  private func publish(
    _ event: SyncStatusEvent,
    deadline: ExecutionDeadline?,
    with publisher: any SyncAttemptPublishing
  ) async {
    if let failure = await publisher.publish(event, deadline: deadline) {
      logger.error("Sync attempt publish failed: \(failure.rawValue, privacy: .public)")
    }
  }

  private func enqueue(_ work: @escaping @MainActor (BackgroundSyncRuntime) async -> Void) async {
    let previous = latestTask
    let task = Task {
      await previous?.value
      await work(self)
    }
    latestTask = task
    await task.value
  }

  private struct Eligibility {
    let isEligible: Bool
    let frequency: BackgroundSyncFrequency
    let metrics: Set<MetricID>
  }

  /// Returns `nil` when a store read fails, so callers can keep existing background work
  /// instead of tearing it down on a transient error.
  private func loadEligibility() async -> Eligibility? {
    guard await access.accessState() == .unlocked else {
      return Eligibility(isEligible: false, frequency: policy.frequency, metrics: [])
    }
    let configuration: AppConfiguration
    do {
      configuration = try await configurationStore.load()
    } catch {
      logReadError(error)
      return nil
    }
    let ineligible = Eligibility(
      isEligible: false,
      frequency: configuration.backgroundSyncFrequency,
      metrics: configuration.selectedMetrics
    )
    // An unconfigured or disabled app is simply not eligible; that is not a read error.
    guard configuration.backgroundSyncEnabled,
      !configuration.baseURL.isEmpty,
      !configuration.selectedMetrics.isEmpty,
      (try? configuration.validate()) != nil
    else {
      return ineligible
    }
    let secret: String?
    let token: String?
    do {
      secret = try await credentialStore.read(.webhookSecret)
      token = try await credentialStore.read(.accessToken)
    } catch {
      logReadError(error)
      return nil
    }
    let hasCredentials = [secret, token].allSatisfy {
      !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    guard hasCredentials else { return ineligible }
    return Eligibility(
      isEligible: true,
      frequency: configuration.backgroundSyncFrequency,
      metrics: configuration.selectedMetrics
    )
  }

  private func logReadError(_ error: any Error) {
    logger.error(
      "Background eligibility unavailable: \(String(describing: type(of: error)), privacy: .public)"
    )
  }

  private func reconcileFromStores(isBootstrap: Bool) async {
    var interrupted: SyncStatusEvent?
    if isBootstrap, let event = try? await statusStore.recordInterruptedAttemptIfNeeded() {
      logger.notice("Recorded interrupted \(event.trigger.rawValue, privacy: .public) attempt")
      interrupted = event
    }
    // Publishing is fire-and-forget after observers and refresh are reconciled, so a slow
    // Home Assistant never delays bootstrap or a waiting refresh launch.
    defer {
      if let interrupted, let publisher {
        Task { await self.publish(interrupted, deadline: nil, with: publisher) }
      }
    }

    guard let eligibility = await loadEligibility() else {
      logger.notice("Background work left unchanged after a store read error")
      return
    }
    isEligible = eligibility.isEligible
    policy = BackgroundSchedulePolicy(frequency: eligibility.frequency)
    await observerManager.reconcile(enabled: eligibility.isEligible, metrics: eligibility.metrics)

    guard eligibility.isEligible else {
      refreshManager.reconcile(
        enabled: false, earliestBeginDate: nil, retryInterval: policy.retryInterval)
      logger.info("Background work not eligible")
      return
    }
    let snapshot = try? await statusStore.snapshot()
    refreshManager.reconcile(
      enabled: true,
      earliestBeginDate: policy.initialRefreshDate(
        lastAttemptedAt: snapshot?.lastAttemptedAt,
        lastFailure: snapshot?.lastFailure,
        now: now()
      ),
      retryInterval: policy.retryInterval
    )
  }
}
