import Foundation
import HealthSyncCore
import Observation

enum ConnectionTestState: Equatable, Sendable {
  case notTested
  case testing
  case succeeded
  case failed(SyncFailureCategory)
}

/// What a manual sync settled, kept only long enough to confirm the tap on the button.
enum ManualSyncFeedback: Hashable, Sendable {
  case synced(Int)
  case upToDate

  var title: String {
    switch self {
    case .synced(let count): count == 1 ? "Synced 1 value" : "Synced \(count) values"
    case .upToDate: "Already up to date"
    }
  }

  /// The confirmation itself is the same either way — the run succeeded. Only the detail differs,
  /// because "nothing changed" is an outcome worth naming rather than a reason to stay silent.
  var detail: String {
    switch self {
    case .synced(let count): count == 1 ? "1 value sent" : "\(count) values sent"
    case .upToDate: "Nothing new to send"
    }
  }
}

enum UVPresetEnableResult: Equatable, Sendable {
  case enabled
  case disabled
  case selectionRequired([UVEntityCandidate])
  case noCandidates
  case failed(SyncFailureCategory)
}

enum PublishSyncAttemptsResult: Equatable, Sendable {
  case enabled
  case disabled
  case requiresAdministrator
  case failed(SyncFailureCategory)
}

private struct ArchiveAvailabilityIdentity: Equatable {
  let baseURL: String
  let allowsConfirmedLocalHTTP: Bool
  let userID: String
  let selectedMetrics: Set<MetricID>
  let integrationVersion: String?

  init(configuration: AppConfiguration, integrationVersion: String?) {
    baseURL = configuration.baseURL
    allowsConfirmedLocalHTTP = configuration.allowsConfirmedLocalHTTP
    userID = configuration.healthBridgeUserID
    selectedMetrics = configuration.selectedMetrics
    self.integrationVersion = integrationVersion
  }
}

@MainActor
@Observable
final class AppModel {
  private let lifetimeUnlockFixture: (any LifetimeUnlockPresenting)?
  var lifetimeUnlock: any LifetimeUnlockPresenting {
    lifetimeUnlockFixture ?? AppRuntime.lifetimeUnlock
  }

  var lifetimeAccessState: PaidAccessState {
    if let lifetimeUnlockFixture { return lifetimeUnlockFixture.state }
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("-ui-testing-purchase-unavailable") { return .unavailable }
    if arguments.contains("-ui-testing-purchase-locked") { return .locked }
    if arguments.contains(where: { $0.hasPrefix("-ui-testing-") }) { return .unlocked }
    return lifetimeUnlock.state
  }

  private let bidirectionalSyncCoordinator: (any BidirectionalSyncCoordinating)?
  private let backfillCoordinator: (any BackfillCoordinating)?
  private let backfillCheckpointStore: (any BackfillCheckpointStore)?
  let archiveCoordinator: (any ArchiveImportCoordinating)?
  private let archiveCheckpointStore: (any ArchiveCheckpointStore)?
  private let archiveQuery: (any HealthArchiveQuerying)?
  private let archiveCapabilityProbe: (@Sendable () async throws -> ArchiveCapability)?
  private let archiveOwnerClaim: (@Sendable () async throws -> ArchiveOwnerClaimStatus)?
  private let archiveUploaderFingerprint: (@Sendable () async throws -> String)?
  private let archiveUploaderCredentialDelete: (@Sendable () async throws -> Void)?
  private let supportsFullHistoryOS: @Sendable () -> Bool
  private let configurationStore: (any ConfigurationStore)?
  private let credentialStore: (any CredentialStore)?
  private let metricQuery: (any MetricQuerying)?
  private let authenticatedClient: (any AuthenticatedConnectionTesting)?
  private let homeAssistantStateLister: (any HomeAssistantStateListing)?
  private let webhookClient: (any WebhookConnectionTesting)?
  private let backgroundRuntime: (any BackgroundSyncRuntimeControlling)?
  private let syncAttemptPublisher: (any SyncAttemptPublishing)?
  private let statusStore: (any SyncStatusStore)?
  private let pairingStore: (any PairingStore)?
  private let pairingCheckpointStore: (any PairingCheckpointStore)?
  private let syncCheckpointStore: (any SyncCheckpointStore)?
  private let medicationCheckpointStore: (any MedicationCheckpointStore)?
  private let metricFreshnessStore: (any MetricFreshnessStore)?
  private let healthSampleWriter: (any HealthSampleWriting)?
  private let medicationAccess: (any MedicationAccessProviding)?
  private let requestIDGenerator: RequestIDGenerator
  private let now: @Sendable () -> Date
  private var backfillTask: Task<BackfillReport, Never>?
  private var archiveImportGeneration = 0
  private var archiveAvailabilityGeneration = 0
  private var storedBackfillCapability = BackfillCapability.unprobed
  private var authenticatedConnectionTestGeneration = 0
  private var webhookConnectionTestGeneration = 0

  private(set) var isSyncing = false
  private(set) var manualSyncFeedback: ManualSyncFeedback?
  private(set) var lastReport: SyncReport?
  private(set) var lastInboundReport: InboundSyncReport?
  private(set) var currentError: SyncFailureCategory?
  private(set) var currentConfiguration = AppConfiguration.default
  private(set) var isOnboardingComplete = false
  private(set) var authenticatedConnectionState = ConnectionTestState.notTested
  private(set) var webhookConnectionState = ConnectionTestState.notTested
  private(set) var lastAttemptedSync: Date?
  private(set) var lastSuccessfulSync: Date?
  private(set) var syncStatus: SyncStatusSnapshot
  private(set) var dashboardPreview = DashboardPreviewState()
  private(set) var pairings: [Pairing] = []
  private(set) var isUpdatingUVExposureImport = false
  private(set) var uvExposureCandidates: [UVEntityCandidate] = []
  private(set) var pairingValidationError: PairingValidationError?
  private(set) var isBackfillRunning = false
  private(set) var lastBackfillReport: BackfillReport?
  private(set) var archiveCapability: ArchiveCapability?
  private(set) var archiveClaimStatus: ArchiveOwnerClaimStatus?
  private(set) var archiveClaimFailure: ArchiveImportIssue?
  private(set) var archiveUploaderFingerprintValue: String?
  private(set) var archiveDiscovery: ArchiveHistoryDiscovery?
  private(set) var archiveSavedSelection: ArchiveImportSelection?
  private(set) var lastArchiveReport: ArchiveImportReport?
  private(set) var isArchiveImportRunning = false
  private(set) var isPerformingDestructiveAction = false
  private(set) var maintenanceFailureCount = 0
  private(set) var healthBridgeIntegrationVersion: String?
  /// When the app last covered every selected metric in one run. Read from the freshness store,
  /// which only records a sweep that finished, so a truncated one keeps the previous date.
  private(set) var lastFullSweepAt: Date?
  let medicationSyncAvailable: Bool

  init(
    bidirectionalSyncCoordinator: (any BidirectionalSyncCoordinating)?,
    backfillCoordinator: (any BackfillCoordinating)? = nil,
    backfillCheckpointStore: (any BackfillCheckpointStore)? = nil,
    archiveCoordinator: (any ArchiveImportCoordinating)? = nil,
    archiveCheckpointStore: (any ArchiveCheckpointStore)? = nil,
    archiveQuery: (any HealthArchiveQuerying)? = nil,
    archiveCapabilityProbe: (@Sendable () async throws -> ArchiveCapability)? = nil,
    archiveOwnerClaim: (@Sendable () async throws -> ArchiveOwnerClaimStatus)? = nil,
    archiveUploaderFingerprint: (@Sendable () async throws -> String)? = nil,
    archiveUploaderCredentialDelete: (@Sendable () async throws -> Void)? = nil,
    supportsFullHistoryOS: @escaping @Sendable () -> Bool = {
      if #available(iOS 27.0, *) { return true }
      return false
    },
    configurationStore: (any ConfigurationStore)? = nil,
    credentialStore: (any CredentialStore)? = nil,
    metricQuery: (any MetricQuerying)? = nil,
    authenticatedClient: (any AuthenticatedConnectionTesting)? = nil,
    homeAssistantStateLister: (any HomeAssistantStateListing)? = nil,
    webhookClient: (any WebhookConnectionTesting)? = nil,
    backgroundRuntime: (any BackgroundSyncRuntimeControlling)? = nil,
    syncAttemptPublisher: (any SyncAttemptPublishing)? = nil,
    statusStore: (any SyncStatusStore)? = nil,
    pairingStore: (any PairingStore)? = nil,
    pairingCheckpointStore: (any PairingCheckpointStore)? = nil,
    syncCheckpointStore: (any SyncCheckpointStore)? = nil,
    medicationCheckpointStore: (any MedicationCheckpointStore)? = nil,
    metricFreshnessStore: (any MetricFreshnessStore)? = nil,
    healthSampleWriter: (any HealthSampleWriting)? = nil,
    medicationAccess: (any MedicationAccessProviding)? = nil,
    medicationSyncAvailable: Bool? = nil,
    requestIDGenerator: RequestIDGenerator = RequestIDGenerator(),
    initialConfiguration: AppConfiguration = .default,
    isOnboardingComplete: Bool = false,
    startupError: SyncFailureCategory? = nil,
    initialSyncStatus: SyncStatusSnapshot = SyncStatusSnapshot(),
    lifetimeUnlockFixture: (any LifetimeUnlockPresenting)? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.bidirectionalSyncCoordinator = bidirectionalSyncCoordinator
    self.lifetimeUnlockFixture = lifetimeUnlockFixture
    self.backfillCoordinator = backfillCoordinator
    self.backfillCheckpointStore = backfillCheckpointStore
    self.archiveCoordinator = archiveCoordinator
    self.archiveCheckpointStore = archiveCheckpointStore
    self.archiveQuery = archiveQuery
    self.archiveCapabilityProbe = archiveCapabilityProbe
    self.archiveOwnerClaim = archiveOwnerClaim
    self.archiveUploaderFingerprint = archiveUploaderFingerprint
    self.archiveUploaderCredentialDelete = archiveUploaderCredentialDelete
    self.supportsFullHistoryOS = supportsFullHistoryOS
    self.configurationStore = configurationStore
    self.credentialStore = credentialStore
    self.metricQuery = metricQuery
    self.authenticatedClient = authenticatedClient
    self.homeAssistantStateLister = homeAssistantStateLister
    self.webhookClient = webhookClient
    self.backgroundRuntime = backgroundRuntime
    self.syncAttemptPublisher = syncAttemptPublisher
    self.statusStore = statusStore
    self.pairingStore = pairingStore
    self.pairingCheckpointStore = pairingCheckpointStore
    self.syncCheckpointStore = syncCheckpointStore
    self.medicationCheckpointStore = medicationCheckpointStore
    self.metricFreshnessStore = metricFreshnessStore
    self.healthSampleWriter = healthSampleWriter
    self.medicationAccess = medicationAccess
    if let medicationSyncAvailable {
      self.medicationSyncAvailable = medicationSyncAvailable
    } else if #available(iOS 26.0, *) {
      self.medicationSyncAvailable = medicationAccess != nil
    } else {
      self.medicationSyncAvailable = false
    }
    self.requestIDGenerator = requestIDGenerator
    self.now = now
    currentConfiguration = initialConfiguration
    self.isOnboardingComplete = isOnboardingComplete
    currentError = startupError
    syncStatus = initialSyncStatus
  }

  var selectedMetricCount: Int {
    currentConfiguration.selectedMetrics.count
  }

  var uvExposureImportEnabled: Bool {
    pairings.contains { $0.destination == .uvExposure && $0.isEnabled }
  }

  func load() async {
    await reloadPairings()
    await refreshBackfillCapability()
    guard let configurationStore, let credentialStore else {
      return
    }
    do {
      let configuration = try await configurationStore.load()
      currentConfiguration = configuration
      guard !configuration.baseURL.isEmpty, !configuration.selectedMetrics.isEmpty else {
        isOnboardingComplete = false
        return
      }
      try configuration.validate()
      let secret = try await credentialStore.read(.webhookSecret)
      let token = try await credentialStore.read(.accessToken)
      isOnboardingComplete = secret?.isEmpty == false && token?.isEmpty == false
      await refreshSyncStatus()
    } catch {
      currentError = .configuration
      isOnboardingComplete = false
    }
  }

  var backgroundSyncEnabled: Bool {
    currentConfiguration.backgroundSyncEnabled
  }

  var backgroundSyncFrequency: BackgroundSyncFrequency {
    currentConfiguration.backgroundSyncFrequency
  }

  var publishSyncAttempts: Bool {
    currentConfiguration.publishSyncAttempts
  }

  var earliestNextAutomaticSync: Date? {
    guard backgroundSyncEnabled, let lastAttemptedAt = syncStatus.lastAttemptedAt else {
      return nil
    }
    // Matches the automatic-trigger gate. Without a date, a locked-device failure bypasses it.
    let eligibleAt = BackgroundSchedulePolicy(frequency: backgroundSyncFrequency)
      .automaticEligibleAt(lastAttemptedAt: lastAttemptedAt, lastFailure: syncStatus.lastFailure)
    return max(now(), eligibleAt ?? now())
  }

  var lastAutomaticEvent: SyncStatusEvent? {
    syncStatus.recentEvents.last { $0.trigger.isAutomatic }
  }

  var experimentalBackfillEnabled: Bool {
    currentConfiguration.experimentalBackfillEnabled
  }

  var historicalImportCapability: BackfillCapability {
    experimentalBackfillEnabled ? storedBackfillCapability : .disabledByUser
  }

  var isFullHistoryAvailable: Bool {
    supportsFullHistoryOS() && archiveCapability?.supportsOwnershipContract == true
  }

  var canArchiveHistory: Bool {
    isFullHistoryAvailable && archiveCapability?.ownerState == .active
      && archiveClaimFailure == nil
  }

  var archiveEligibleDefinitions: [MetricDefinition] {
    guard isFullHistoryAvailable, let archiveCapability else { return [] }
    return HistoricalMetricSelectionPolicy.archiveEligibleDefinitions(
      selectedMetrics: currentConfiguration.selectedMetrics.intersection(
        MetricSelectionPolicy.availableMetricIDs(
          osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)),
      capability: archiveCapability)
  }

  var archiveAvailabilityDescription: String {
    if isFullHistoryAvailable { return "Full-history archive protocol available" }
    if !supportsFullHistoryOS() {
      return "Full history requires iOS 27. The 14-day import remains available."
    }
    return
      "Full history requires the Health Bridge archive integration. The 14-day import remains available."
  }

  func refreshArchiveAvailability() async {
    archiveAvailabilityGeneration &+= 1
    let generation = archiveAvailabilityGeneration
    let identity = archiveAvailabilityIdentity
    archiveCapability = nil
    archiveDiscovery = nil
    archiveSavedSelection = nil
    archiveClaimStatus = nil
    archiveClaimFailure = nil
    guard !isPerformingDestructiveAction, supportsFullHistoryOS(),
      archiveCoordinator != nil, let archiveQuery, let archiveCapabilityProbe
    else { return }
    do {
      let capability = try await archiveCapabilityProbe()
      guard archiveAvailabilityIsCurrent(generation, identity: identity) else { return }
      try capability.validate(requestID: capability.requestID)
      guard capability.archiveAvailable, capability.supportsOwnershipContract else { return }
      if let archiveUploaderFingerprint {
        archiveUploaderFingerprintValue = try await archiveUploaderFingerprint()
      }
      var checkpoint: ArchiveImportCheckpoint?
      if let archiveCheckpointStore {
        checkpoint = try await archiveCheckpointStore.load()
        guard archiveAvailabilityIsCurrent(generation, identity: identity) else { return }
      }
      let definitions = HistoricalMetricSelectionPolicy.archiveEligibleDefinitions(
        selectedMetrics: identity.selectedMetrics.intersection(
          MetricSelectionPolicy.availableMetricIDs(
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)),
        capability: capability)
      var discovery: ArchiveHistoryDiscovery?
      var discoveryError: SyncFailureCategory?
      if !definitions.isEmpty {
        do {
          discovery = try await archiveQuery.discover(metrics: definitions)
        } catch {
          discoveryError = Self.failureCategory(for: error, fallback: .healthKit)
        }
      }
      guard archiveAvailabilityIsCurrent(generation, identity: identity) else { return }
      archiveCapability = capability
      archiveDiscovery = discovery
      archiveSavedSelection = checkpoint?.selection
      if let checkpoint, checkpoint.hasPreviousWork,
        checkpoint.uploaderFingerprint != archiveUploaderFingerprintValue
          || checkpoint.ownerGeneration != capability.ownerGeneration
      {
        archiveClaimFailure = .checkpointOwnerMismatch
      }
      if let checkpoint, checkpoint.selection != nil, lastArchiveReport == nil,
        !isArchiveImportRunning
      {
        var restored = ArchiveImportReport()
        restored.archiveState = .paused
        restored.archivedSamples = checkpoint.archivedSamples
        restored.archivedDeletions = checkpoint.archivedDeletions
        restored.metricEarliestDates = checkpoint.metricEarliestDates
        restored.typeProgress = ArchiveProgress.restored(checkpoint: checkpoint, now: Date())
        restored.failures = checkpoint.types.compactMap { type, state in
          state.reconciliationRequired
            ? ArchiveImportFailure(type: type, category: .healthKit, issue: .reconciliationRequired)
            : nil
        }
        lastArchiveReport = restored
      }
      if let discoveryError { currentError = discoveryError }
    } catch {
      guard archiveAvailabilityIsCurrent(generation, identity: identity) else { return }
      archiveCapability = nil
      archiveDiscovery = nil
      archiveSavedSelection = nil
      archiveUploaderFingerprintValue = nil
    }
  }

  func requestArchiveOwnerClaim() async {
    guard isFullHistoryAvailable, let archiveOwnerClaim else { return }
    let generation = archiveAvailabilityGeneration
    let identity = archiveAvailabilityIdentity
    do {
      let status = try await archiveOwnerClaim()
      guard archiveAvailabilityIsCurrent(generation, identity: identity) else { return }
      archiveClaimStatus = status
      archiveClaimFailure = nil
      await refreshArchiveAvailability()
      if archiveAvailabilityIdentity == identity { archiveClaimStatus = status }
    } catch let error as ArchiveClientError {
      guard archiveAvailabilityIsCurrent(generation, identity: identity) else { return }
      switch error {
      case .ownerPending: archiveClaimFailure = .ownerPending
      case .ownerChanged: archiveClaimFailure = .ownerChanged
      default: archiveClaimFailure = .ownerRequired
      }
    } catch {
      guard archiveAvailabilityIsCurrent(generation, identity: identity) else { return }
      currentError = Self.failureCategory(for: error, fallback: .transport)
    }
  }

  func resetArchiveImportForThisPhone() async {
    guard let archiveCheckpointStore, !isArchiveImportRunning else { return }
    archiveImportGeneration &+= 1
    do {
      try await archiveCheckpointStore.reset()
      lastArchiveReport = nil
      archiveSavedSelection = nil
      archiveClaimFailure = nil
      await refreshArchiveAvailability()
    } catch {
      currentError = .checkpoint
    }
  }

  private var archiveAvailabilityIdentity: ArchiveAvailabilityIdentity {
    ArchiveAvailabilityIdentity(
      configuration: currentConfiguration, integrationVersion: healthBridgeIntegrationVersion)
  }

  private func archiveAvailabilityIsCurrent(
    _ generation: Int, identity: ArchiveAvailabilityIdentity
  ) -> Bool {
    archiveAvailabilityGeneration == generation
      && archiveAvailabilityIdentity == identity
      && !isPerformingDestructiveAction
  }

  func importReadableHistory(metrics: Set<MetricID>, requestedStart: Date?) async {
    let eligible = Set(archiveEligibleDefinitions.map(\.id))
    guard experimentalBackfillEnabled, canArchiveHistory, let archiveCoordinator,
      let archiveDiscovery,
      !metrics.isEmpty, metrics.isSubset(of: eligible), !isArchiveImportRunning,
      metrics.contains(where: {
        if case .readable = archiveDiscovery.metrics[$0] { return true }
        return false
      })
    else {
      currentError = .configuration
      return
    }
    isArchiveImportRunning = true
    let generation = archiveImportGeneration
    let task = Task {
      await archiveCoordinator.importHistory(
        selection: ArchiveImportSelection(metrics: metrics, requestedStart: requestedStart))
    }
    let report = await task.value
    guard generation == archiveImportGeneration else { return }
    isArchiveImportRunning = false
    lastArchiveReport = report
    archiveSavedSelection = ArchiveImportSelection(metrics: metrics, requestedStart: requestedStart)
    recordArchiveOwnershipFailure(from: report)
    currentError = report.failures.first(where: { $0.issue != .noReadableSamples })?.category
  }

  func pauseArchiveImport() async {
    await archiveCoordinator?.pause()
  }

  func resumeArchiveImport() async {
    guard experimentalBackfillEnabled, canArchiveHistory, let archiveCoordinator,
      !isArchiveImportRunning
    else { return }
    isArchiveImportRunning = true
    let generation = archiveImportGeneration
    let report = await archiveCoordinator.resume()
    guard generation == archiveImportGeneration else { return }
    isArchiveImportRunning = false
    lastArchiveReport = report
    recordArchiveOwnershipFailure(from: report)
  }

  func refreshArchiveProjection() async {
    guard isFullHistoryAvailable, let archiveCoordinator else { return }
    let generation = archiveImportGeneration
    let availabilityGeneration = archiveAvailabilityGeneration
    let identity = archiveAvailabilityIdentity
    let update = await archiveCoordinator.refreshProjection()
    guard generation == archiveImportGeneration,
      archiveAvailabilityIsCurrent(availabilityGeneration, identity: identity)
    else { return }
    guard var report = lastArchiveReport else {
      lastArchiveReport = update
      return
    }
    report.projectionStates.merge(update.projectionStates) { _, latest in latest }
    for failure in update.failures where !report.failures.contains(failure) {
      report.failures.append(failure)
    }
    if update.archiveState == .paused,
      update.failures.contains(where: { Self.isArchiveOwnershipIssue($0.issue) })
    {
      report.archiveState = .paused
    }
    recordArchiveOwnershipFailure(from: update)
    lastArchiveReport = report
  }

  private func recordArchiveOwnershipFailure(from report: ArchiveImportReport) {
    if let issue = report.failures.map(\.issue).first(where: Self.isArchiveOwnershipIssue) {
      archiveClaimFailure = issue
    }
  }

  private static func isArchiveOwnershipIssue(_ issue: ArchiveImportIssue?) -> Bool {
    issue == .ownerRequired || issue == .ownerPending || issue == .ownerChanged
  }

  func receiveArchiveProgress(_ report: ArchiveImportReport) {
    // The coordinator also publishes projection refreshes through this callback. Their
    // returned report is merged by refreshArchiveProjection; only imports own progress.
    guard isArchiveImportRunning else { return }
    lastArchiveReport = report
  }

  var medicationSyncEnabled: Bool {
    currentConfiguration.medicationSyncEnabled
  }

  func requestHealthAuthorization(for metrics: Set<MetricID>) async {
    guard let metricQuery, !metrics.isEmpty else {
      currentError = .configuration
      return
    }
    do {
      try await metricQuery.requestReadAuthorization(for: metrics)
      currentError = nil
    } catch {
      currentError = Self.failureCategory(for: error, fallback: .healthKit)
    }
  }

  func refreshDashboardPreview(
    now: Date = Date(),
    calendar: Calendar = .current
  ) async {
    guard let metricQuery else {
      dashboardPreview = DashboardPreviewState(refreshedAt: now)
      return
    }

    dashboardPreview.isLoading = true
    defer { dashboardPreview.isLoading = false }

    var readings: [MetricID: MetricReading] = [:]
    var failures: [MetricID: SyncFailureCategory] = [:]
    let definitions = MetricRegistry.selectable
      .filter { currentConfiguration.selectedMetrics.contains($0.id) }
      .sorted { $0.id.rawValue < $1.id.rawValue }

    for definition in definitions {
      do {
        readings[definition.id] = try await metricQuery.currentReading(
          for: definition,
          now: now,
          calendar: calendar
        )
      } catch is CancellationError {
        return
      } catch {
        failures[definition.id] = Self.failureCategory(for: error, fallback: .healthKit)
      }
    }

    dashboardPreview = DashboardPreviewState(
      readings: readings,
      failureCategories: failures,
      isLoading: false,
      refreshedAt: now
    )
  }

  @discardableResult
  func requestHealthWriteAuthorization(for destinations: Set<HealthObjectTypeID>) async -> Bool {
    guard let healthSampleWriter, !destinations.isEmpty else {
      currentError = .configuration
      return false
    }
    do {
      try await healthSampleWriter.requestWriteAuthorization(for: destinations)
      currentError = nil
      return true
    } catch {
      currentError = Self.failureCategory(for: error, fallback: .healthKit)
      return false
    }
  }

  func reloadPairings() async {
    guard let pairingStore else { return }
    do {
      pairings = try await pairingStore.all()
      pairingValidationError = nil
    } catch {
      currentError = .configuration
    }
  }

  @discardableResult
  func savePairing(_ pairing: Pairing) async -> Bool {
    guard let pairingStore else {
      currentError = .configuration
      return false
    }
    do {
      try PairingValidator.validate(pairing, existing: pairings)
      try await pairingStore.save(pairing)
      pairings = try await pairingStore.all()
      pairingValidationError = nil
      currentError = nil
      return true
    } catch let error as PairingValidationError {
      pairingValidationError = error
      currentError = .validation
      return false
    } catch {
      currentError = .configuration
      return false
    }
  }

  func deletePairing(id: UUID) async {
    guard let pairingStore else {
      currentError = .configuration
      return
    }
    do {
      try await pairingStore.delete(id: id)
      try await pairingCheckpointStore?.reset(pairingID: id)
      pairings = try await pairingStore.all()
      pairingValidationError = nil
      currentError = nil
    } catch {
      currentError = .checkpoint
    }
  }

  func setUVExposureImportEnabled(
    _ enabled: Bool,
    selectedEntityID: String? = nil
  ) async -> UVPresetEnableResult {
    guard !isUpdatingUVExposureImport, let pairingStore else {
      currentError = .configuration
      return .failed(.configuration)
    }

    isUpdatingUVExposureImport = true
    defer { isUpdatingUVExposureImport = false }

    if !enabled {
      do {
        for var pairing in pairings
        where pairing.destination == .uvExposure && pairing.isEnabled {
          pairing.isEnabled = false
          try await pairingStore.save(pairing)
        }
        pairings = try await pairingStore.all()
        uvExposureCandidates = []
        pairingValidationError = nil
        currentError = nil
        return .disabled
      } catch {
        currentError = .configuration
        return .failed(.configuration)
      }
    }

    if uvExposureImportEnabled {
      return .enabled
    }

    let entityID: String
    if let selectedEntityID {
      guard uvExposureCandidates.contains(where: { $0.entityID == selectedEntityID }) else {
        currentError = .validation
        return .failed(.validation)
      }
      entityID = selectedEntityID
    } else if let existingPairing = pairings.first(where: {
      $0.destination == .uvExposure && !$0.isEnabled
    }) {
      entityID = existingPairing.entityID
    } else {
      guard let homeAssistantStateLister, let credentialStore else {
        currentError = .configuration
        return .failed(.configuration)
      }
      do {
        let baseURL = try normalizedBaseURL(for: currentConfiguration)
        guard let accessToken = try await credentialStore.read(.accessToken),
          !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          currentError = .credential
          return .failed(.credential)
        }
        let states = try await homeAssistantStateLister.fetchStates(
          baseURL: baseURL,
          accessToken: accessToken
        )
        let candidates = UVEntityDiscovery.candidates(
          from: states,
          excludingHealthBridgeUserID: currentConfiguration.healthBridgeUserID
        )
        uvExposureCandidates = candidates
        guard !candidates.isEmpty else {
          currentError = nil
          return .noCandidates
        }
        guard candidates.count == 1, let candidate = candidates.first else {
          currentError = nil
          return .selectionRequired(candidates)
        }
        entityID = candidate.entityID
      } catch {
        let failure = Self.failureCategory(for: error, fallback: .configuration)
        currentError = failure
        return .failed(failure)
      }
    }

    guard await requestHealthWriteAuthorization(for: [.uvExposure]) else {
      return .failed(currentError ?? .healthKit)
    }

    let pairing = Pairing(
      id: pairings.first(where: { $0.destination == .uvExposure })?.id ?? UUID(),
      entityID: entityID,
      destination: .uvExposure,
      sourceUnit: .unitless,
      destinationUnit: .unitless,
      transformation: .identity,
      isEnabled: true
    )
    guard await savePairing(pairing) else {
      return .failed(currentError ?? .configuration)
    }
    uvExposureCandidates = []
    return .enabled
  }

  func updateSelectedMetrics(_ metrics: Set<MetricID>) async {
    guard !metrics.isEmpty, let configurationStore else {
      currentError = .configuration
      return
    }

    let newlySelected = metrics.subtracting(currentConfiguration.selectedMetrics)
    var updatedConfiguration = currentConfiguration
    updatedConfiguration.selectedMetrics = metrics
    do {
      try await configurationStore.save(updatedConfiguration)
      currentConfiguration = updatedConfiguration
      currentError = nil
    } catch {
      currentError = .configuration
      return
    }

    if !newlySelected.isEmpty {
      await requestHealthAuthorization(for: newlySelected)
    }
    await refreshArchiveAvailability()
    await backgroundRuntime?.reconcile()
    await refreshSyncStatus()
  }

  func setBackgroundSyncEnabled(_ enabled: Bool) async {
    guard let configurationStore else {
      currentError = .configuration
      return
    }
    var updatedConfiguration = currentConfiguration
    updatedConfiguration.backgroundSyncEnabled = enabled
    do {
      try await configurationStore.save(updatedConfiguration)
      currentConfiguration = updatedConfiguration
      currentError = nil
      await backgroundRuntime?.reconcile()
      await refreshSyncStatus()
    } catch {
      currentError = .configuration
    }
  }

  func setBackgroundSyncFrequency(_ frequency: BackgroundSyncFrequency) async {
    guard let configurationStore else {
      currentError = .configuration
      return
    }
    var updatedConfiguration = currentConfiguration
    updatedConfiguration.backgroundSyncFrequency = frequency
    do {
      try await configurationStore.save(updatedConfiguration)
      currentConfiguration = updatedConfiguration
      currentError = nil
      await backgroundRuntime?.reconcile()
      await refreshSyncStatus()
    } catch {
      currentError = .configuration
    }
  }

  func setPublishSyncAttempts(_ enabled: Bool) async -> PublishSyncAttemptsResult {
    guard let configurationStore else {
      currentError = .configuration
      return .failed(.configuration)
    }
    if enabled {
      guard let syncAttemptPublisher else { return .failed(.configuration) }
      do {
        try await syncAttemptPublisher.publishTest()
      } catch {
        let category = Self.failureCategory(for: error, fallback: .transport)
        return category == .unauthorized || category == .forbidden
          ? .requiresAdministrator : .failed(category)
      }
    }
    var updatedConfiguration = currentConfiguration
    updatedConfiguration.publishSyncAttempts = enabled
    do {
      try await configurationStore.save(updatedConfiguration)
      currentConfiguration = updatedConfiguration
      currentError = nil
      return enabled ? .enabled : .disabled
    } catch {
      currentError = .configuration
      return .failed(.configuration)
    }
  }

  func setExperimentalBackfillEnabled(_ enabled: Bool) async {
    guard let configurationStore, !enabled || backfillCoordinator != nil else {
      currentError = .configuration
      return
    }
    var updatedConfiguration = currentConfiguration
    updatedConfiguration.experimentalBackfillEnabled = enabled
    do {
      try await configurationStore.save(updatedConfiguration)
      currentConfiguration = updatedConfiguration
      currentError = nil
      if !enabled {
        cancelHistoricalImport()
        archiveImportGeneration &+= 1
        await pauseArchiveImport()
        isArchiveImportRunning = false
      } else {
        await refreshArchiveAvailability()
      }
    } catch {
      currentError = .configuration
    }
  }

  func importHistory(metrics: Set<MetricID>, requestedStart: Date) async {
    let eligible = Set(MetricRegistry.backfillEligible.map(\.id))
    guard experimentalBackfillEnabled, let backfillCoordinator,
      !metrics.isEmpty, metrics.isSubset(of: eligible), !isBackfillRunning
    else {
      currentError = .configuration
      return
    }

    isBackfillRunning = true
    let task = Task {
      await backfillCoordinator.importHistory(
        metrics: metrics,
        requestedStart: requestedStart
      )
    }
    backfillTask = task
    let report = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    backfillTask = nil
    isBackfillRunning = false
    lastBackfillReport = report
    if !report.requiresPurchase { storedBackfillCapability = report.capability }
    currentError = report.failures.first?.category
  }

  func cancelHistoricalImport() {
    backfillTask?.cancel()
  }

  func requestMedicationAuthorization() async -> [MedicationConcept] {
    guard medicationSyncAvailable, let medicationAccess else {
      currentError = .compatibility
      return []
    }
    do {
      let concepts = try await medicationAccess.requestAuthorizationAndList()
      currentError = nil
      return concepts.filter { !$0.isArchived }.sorted {
        ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id)
          == .orderedAscending
      }
    } catch {
      currentError = Self.failureCategory(for: error, fallback: .healthKit)
      return []
    }
  }

  func setMedicationSyncEnabled(_ enabled: Bool) async {
    guard let configurationStore, !enabled || medicationSyncAvailable else {
      currentError = .compatibility
      return
    }
    var updatedConfiguration = currentConfiguration
    updatedConfiguration.medicationSyncEnabled = enabled
    do {
      try await configurationStore.save(updatedConfiguration)
      currentConfiguration = updatedConfiguration
      currentError = nil
    } catch {
      currentError = .configuration
    }
  }

  func refreshBackfillCapability() async {
    guard let backfillCheckpointStore else { return }
    do {
      storedBackfillCapability = try await backfillCheckpointStore.load().capability
    } catch {
      currentError = .checkpoint
    }
  }

  func diagnosticsText(
    appVersion: String,
    buildVersion: String,
    osVersion: String,
    generatedAt: Date = Date()
  ) async throws -> String {
    var secrets: [String] = []
    if let credentialStore {
      for kind in CredentialKind.allCases {
        if let value = try? await credentialStore.read(kind), !value.isEmpty {
          secrets.append(value)
        }
      }
    }

    var failureCategories = lastReport?.failures.map { $0.category.rawValue } ?? []
    failureCategories.append(
      contentsOf: lastInboundReport?.failures.map { $0.category.rawValue } ?? []
    )
    failureCategories.append(
      contentsOf: lastBackfillReport?.failures.map { $0.category.rawValue } ?? []
    )
    if let lastFailure = syncStatus.lastFailure {
      failureCategories.append(lastFailure.category.rawValue)
    }
    let registeredCount = syncStatus.registrations.values.filter {
      if case .registered = $0 { return true }
      return false
    }.count
    let report = DiagnosticReport(
      generatedAt: generatedAt,
      appVersion: appVersion,
      buildVersion: buildVersion,
      osVersion: osVersion,
      integrationVersion: healthBridgeIntegrationVersion,
      liveProtocolVersion: LiveRequest.protocolVersion,
      backfillProtocolVersion: BackfillRequest.protocolVersion,
      authenticatedAPIConnected: authenticatedConnectionState == .succeeded,
      webhookConnected: webhookConnectionState == .succeeded,
      backgroundSyncEnabled: backgroundSyncEnabled,
      backgroundSyncFrequency: currentConfiguration.backgroundSyncFrequency,
      historicalImportEnabled: experimentalBackfillEnabled,
      medicationSyncEnabled: medicationSyncEnabled,
      selectedMetricCount: selectedMetricCount,
      pairingCount: pairings.count,
      registeredBackgroundMetricCount: registeredCount,
      lastAttemptedAt: syncStatus.lastAttemptedAt,
      lastSuccessfulAt: syncStatus.lastSuccessfulAt,
      failureCategories: Array(Set(failureCategories)),
      interruptedEventCount: syncStatus.recentEvents.filter { $0.outcome == .interrupted }.count,
      throttledWakeCount: syncStatus.recentEvents.reduce(syncStatus.pendingThrottledWakes) {
        $0 + $1.throttledWakesBefore
      }
    )
    return try report.render(redacting: secrets)
  }

  func resetSynchronizationState() async {
    guard !isPerformingDestructiveAction else { return }
    isPerformingDestructiveAction = true
    defer { isPerformingDestructiveAction = false }
    cancelHistoricalImport()
    archiveImportGeneration &+= 1
    archiveAvailabilityGeneration &+= 1
    await archiveCoordinator?.pause()
    isArchiveImportRunning = false
    await backgroundRuntime?.suspend()

    var failures = 0
    failures += await attempt { try await self.syncCheckpointStore?.resetAll() }
    failures += await attempt { try await self.pairingCheckpointStore?.resetAll() }
    failures += await attempt { try await self.backfillCheckpointStore?.reset() }
    failures += await attempt { try await self.archiveCheckpointStore?.reset() }
    failures += await attempt { try await self.medicationCheckpointStore?.reset() }
    failures += await attempt { try await self.statusStore?.reset() }
    failures += await attempt { try await self.metricFreshnessStore?.reset() }

    lastReport = nil
    lastInboundReport = nil
    lastBackfillReport = nil
    lastArchiveReport = nil
    archiveCapability = nil
    archiveDiscovery = nil
    archiveSavedSelection = nil
    lastAttemptedSync = nil
    lastSuccessfulSync = nil
    syncStatus = SyncStatusSnapshot()
    storedBackfillCapability = .unprobed
    lastFullSweepAt = nil
    maintenanceFailureCount = failures
    currentError = failures == 0 ? nil : .checkpoint

    await backgroundRuntime?.reconcile()
    await refreshSyncStatus()
  }

  func deleteAllLocalApplicationData() async {
    guard !isPerformingDestructiveAction else { return }
    isPerformingDestructiveAction = true
    defer { isPerformingDestructiveAction = false }
    cancelHistoricalImport()
    archiveImportGeneration &+= 1
    archiveAvailabilityGeneration &+= 1
    await archiveCoordinator?.pause()
    isArchiveImportRunning = false
    await backgroundRuntime?.suspend()

    var failures = 0
    failures += await attempt { try await self.syncCheckpointStore?.resetAll() }
    failures += await attempt { try await self.pairingCheckpointStore?.resetAll() }
    failures += await attempt { try await self.backfillCheckpointStore?.reset() }
    failures += await attempt { try await self.archiveCheckpointStore?.reset() }
    failures += await attempt { try await self.medicationCheckpointStore?.reset() }
    failures += await attempt { try await self.statusStore?.reset() }
    failures += await attempt { try await self.metricFreshnessStore?.reset() }
    failures += await attempt { try await self.pairingStore?.deleteAll() }
    failures += await attempt { try await self.credentialStore?.deleteAll() }
    failures += await attempt { try await self.archiveUploaderCredentialDelete?() }
    failures += await attempt { try await self.configurationStore?.delete() }

    currentConfiguration = .default
    if failures == 0 {
      isOnboardingComplete = false
    }
    authenticatedConnectionState = .notTested
    webhookConnectionState = .notTested
    healthBridgeIntegrationVersion = nil
    pairings = []
    pairingValidationError = nil
    lastReport = nil
    lastInboundReport = nil
    lastBackfillReport = nil
    lastArchiveReport = nil
    archiveCapability = nil
    archiveDiscovery = nil
    archiveSavedSelection = nil
    lastAttemptedSync = nil
    lastSuccessfulSync = nil
    syncStatus = SyncStatusSnapshot()
    storedBackfillCapability = .unprobed
    lastFullSweepAt = nil
    maintenanceFailureCount = failures
    currentError = failures == 0 ? nil : .checkpoint
  }

  private func attempt(_ operation: () async throws -> Void) async -> Int {
    do {
      try await operation()
      return 0
    } catch {
      return 1
    }
  }

  func refreshSyncStatus() async {
    // A freshness read that fails leaves the last known sweep date on screen: a transient
    // read error is not evidence that the app never swept.
    if let metricFreshnessStore, let freshness = try? await metricFreshnessStore.snapshot() {
      lastFullSweepAt = freshness.lastFullSweepAt
    }
    guard let statusStore else { return }
    do {
      syncStatus = try await statusStore.snapshot()
      lastAttemptedSync = syncStatus.lastAttemptedAt
      lastSuccessfulSync = syncStatus.lastSuccessfulAt
    } catch {
      currentError = .checkpoint
    }
  }

  func saveConnection(
    configuration: AppConfiguration,
    webhookSecret: String,
    accessToken: String
  ) async {
    guard let configurationStore, let credentialStore else {
      currentError = .configuration
      return
    }

    do {
      _ = try normalizedBaseURL(for: configuration)
      try configuration.validate()
      guard !configuration.selectedMetrics.isEmpty else {
        throw AppModelError.invalidConfiguration
      }
      try await credentialStore.write(
        webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines),
        for: .webhookSecret
      )
      try await credentialStore.write(
        accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
        for: .accessToken
      )
      try await configurationStore.save(configuration)
      currentConfiguration = configuration
      isOnboardingComplete = true
      currentError = nil
      await refreshArchiveAvailability()
      await backgroundRuntime?.reconcile()
    } catch {
      isOnboardingComplete = false
      currentError = Self.failureCategory(for: error, fallback: .configuration)
    }
  }

  func completeOnboarding(
    configuration: AppConfiguration,
    webhookSecret: String,
    accessToken: String
  ) async {
    await saveConnection(
      configuration: configuration,
      webhookSecret: webhookSecret,
      accessToken: accessToken
    )
    guard isOnboardingComplete else { return }
    await syncNow()
  }

  func updateConnection(
    configuration: AppConfiguration,
    webhookSecret: String,
    accessToken: String
  ) async {
    guard let configurationStore, let credentialStore else {
      currentError = .configuration
      return
    }

    do {
      _ = try normalizedBaseURL(for: configuration)
      try configuration.validate()
      guard !configuration.selectedMetrics.isEmpty else {
        throw AppModelError.invalidConfiguration
      }
      let trimmedWebhookSecret = webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedWebhookSecret.isEmpty {
        try await credentialStore.write(trimmedWebhookSecret, for: .webhookSecret)
      }
      if !trimmedAccessToken.isEmpty {
        try await credentialStore.write(trimmedAccessToken, for: .accessToken)
      }
      guard try await credentialStore.read(.webhookSecret) != nil,
        try await credentialStore.read(.accessToken) != nil
      else {
        throw CredentialStoreError.blankValue
      }
      try await configurationStore.save(configuration)
      currentConfiguration = configuration
      currentError = nil
      await refreshArchiveAvailability()
      await backgroundRuntime?.reconcile()
    } catch {
      currentError = Self.failureCategory(for: error, fallback: .configuration)
    }
  }

  func resetConnectionTestStates() {
    invalidateAuthenticatedConnectionTest()
    invalidateWebhookConnectionTest()
  }

  func invalidateAuthenticatedConnectionTest() {
    authenticatedConnectionTestGeneration &+= 1
    authenticatedConnectionState = .notTested
  }

  func invalidateWebhookConnectionTest() {
    webhookConnectionTestGeneration &+= 1
    webhookConnectionState = .notTested
  }

  func testAuthenticatedConnection(configuration: AppConfiguration) async {
    guard let credentialStore, let authenticatedClient else {
      authenticatedConnectionState = .failed(.configuration)
      return
    }
    authenticatedConnectionTestGeneration &+= 1
    let generation = authenticatedConnectionTestGeneration
    authenticatedConnectionState = .testing
    do {
      let baseURL = try normalizedBaseURL(for: configuration)
      guard let token = try await credentialStore.read(.accessToken) else {
        throw CredentialStoreError.blankValue
      }
      _ = try await authenticatedClient.testAuthenticatedAPI(
        baseURL: baseURL,
        accessToken: token
      )
      guard generation == authenticatedConnectionTestGeneration else { return }
      authenticatedConnectionState = .succeeded
    } catch {
      guard generation == authenticatedConnectionTestGeneration else { return }
      authenticatedConnectionState = .failed(
        Self.failureCategory(for: error, fallback: .configuration)
      )
    }
  }

  func storeAccessTokenAndTest(
    configuration: AppConfiguration,
    accessToken: String
  ) async {
    guard let credentialStore else {
      authenticatedConnectionState = .failed(.configuration)
      return
    }
    do {
      try await credentialStore.write(
        accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
        for: .accessToken
      )
      await testAuthenticatedConnection(configuration: configuration)
    } catch {
      authenticatedConnectionState = .failed(.credential)
    }
  }

  func testWebhookConnection(configuration: AppConfiguration) async {
    guard let credentialStore, let webhookClient else {
      webhookConnectionState = .failed(.configuration)
      return
    }
    webhookConnectionTestGeneration &+= 1
    let generation = webhookConnectionTestGeneration
    webhookConnectionState = .testing
    do {
      let baseURL = try normalizedBaseURL(for: configuration)
      guard let secret = try await credentialStore.read(.webhookSecret) else {
        throw CredentialStoreError.blankValue
      }
      let acknowledgement = try await webhookClient.testWebhook(
        baseURL: baseURL,
        webhookSecret: secret,
        userID: configuration.healthBridgeUserID,
        requestID: requestIDGenerator.connectionTest()
      )
      guard generation == webhookConnectionTestGeneration else { return }
      let versionChanged = healthBridgeIntegrationVersion != acknowledgement.integrationVersion
      healthBridgeIntegrationVersion = acknowledgement.integrationVersion
      webhookConnectionState = .succeeded
      if versionChanged { await refreshArchiveAvailability() }
    } catch {
      guard generation == webhookConnectionTestGeneration else { return }
      webhookConnectionState = .failed(
        Self.failureCategory(for: error, fallback: .configuration)
      )
    }
  }

  func storeWebhookSecretAndTest(
    configuration: AppConfiguration,
    webhookSecret: String
  ) async {
    guard let credentialStore else {
      webhookConnectionState = .failed(.configuration)
      return
    }
    do {
      try await credentialStore.write(
        webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines),
        for: .webhookSecret
      )
      await testWebhookConnection(configuration: configuration)
    } catch {
      webhookConnectionState = .failed(.credential)
    }
  }

  func syncNow() async {
    guard !isSyncing, let bidirectionalSyncCoordinator else { return }

    isSyncing = true
    manualSyncFeedback = nil
    defer { isSyncing = false }

    let outcome = await bidirectionalSyncCoordinator.sync(trigger: .manual)
    guard case .performed(let report) = outcome else { return }
    lastAttemptedSync = report.startedAt
    lastReport = report.outbound
    lastInboundReport = report.inbound
    currentError = report.firstFailureCategory
    let changesSent =
      (report.outbound?.synchronizedMetrics ?? 0) + (report.inbound?.savedPairings ?? 0)
    if report.succeeded, changesSent > 0 {
      lastSuccessfulSync = report.finishedAt
    }
    // A run that found nothing to send still succeeded. Saying so is the difference between a
    // button that looks broken — it returns at once and leaves "Last sync" untouched, because
    // that records the last time something was actually sent — and one that answers the question
    // the tap asked.
    if report.succeeded {
      manualSyncFeedback = changesSent > 0 ? .synced(changesSent) : .upToDate
    }
    await refreshSyncStatus()
  }

  /// Drops the transient confirmation shown on the sync button, once it has been read.
  func clearManualSyncFeedback() {
    manualSyncFeedback = nil
  }

  private func normalizedBaseURL(for configuration: AppConfiguration) throws
    -> NormalizedBaseURL
  {
    try NormalizedBaseURL.parse(
      configuration.baseURL,
      allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP
    )
  }

  private static func failureCategory(
    for error: any Error,
    fallback: SyncFailureCategory
  ) -> SyncFailureCategory {
    guard let failure = error as? NetworkFailure else {
      return error is CredentialStoreError ? .credential : fallback
    }
    return switch failure {
    case .cancelled: .cancelled
    case .timeout: .timeout
    case .dnsFailure: .dnsFailure
    case .offline: .offline
    case .connectionLost: .connectionLost
    case .tlsFailure: .tlsFailure
    case .unauthorized: .unauthorized
    case .forbidden: .forbidden
    case .notFound: .notFound
    case .validation: .validation
    case .rateLimited: .rateLimited
    case .server: .server
    case .malformedResponse: .malformedResponse
    case .protocolMismatch: .protocolMismatch
    case .unexpectedStatus, .transport: .transport
    }
  }
}

private enum AppModelError: Error {
  case invalidConfiguration
}
