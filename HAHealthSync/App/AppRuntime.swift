import AppIntents
import Foundation
import HealthSyncCore
import Observation

@MainActor
enum AppRuntime {
  #if DEBUG && OWNER_UNLOCK
    static let lifetimeUnlock = DeveloperLifetimeUnlock()
  #else
    static let lifetimeUnlock = StoreKitLifetimeUnlock()
  #endif

  static func makeAppModel() -> AppModel {
    let launchArguments = ProcessInfo.processInfo.arguments
    if launchArguments.contains("-ui-testing-onboarding") {
      return makeUITestOnboardingModel()
    }
    if launchArguments.contains("-ui-testing-dashboard") {
      return makeUITestDashboardModel()
    }
    if launchArguments.contains("-ui-testing-background") {
      return makeUITestBackgroundModel()
    }
    if launchArguments.contains("-ui-testing-background-disabled") {
      return makeUITestBackgroundModel(
        enabled: false,
        frequency: .batterySaver,
        starvedMetrics: nil
      )
    }
    if launchArguments.contains("-ui-testing-pairings") {
      return makeUITestPairingsModel()
    }
    if launchArguments.contains("-ui-testing-backfill-skips") {
      return makeUITestExperimentalModel(
        medicationAvailable: false,
        reportsSkippedHistory: true
      )
    }
    if launchArguments.contains("-ui-testing-archive") {
      return makeUITestArchiveModel(
        recoveryRequired: launchArguments.contains("-ui-testing-archive-recovery"))
    }
    if launchArguments.contains("-ui-testing-experimental-no-medications") {
      return makeUITestExperimentalModel(medicationAvailable: false)
    }
    if launchArguments.contains("-ui-testing-experimental") {
      return makeUITestExperimentalModel(medicationAvailable: true)
    }
    if launchArguments.contains("-ui-testing-maintenance") {
      return makeUITestMaintenanceModel()
    }

    Task { await lifetimeUnlock.load() }
    do {
      let configurationStore = try ProtectedConfigurationStore()
      let credentialStore = KeychainCredentialStore()
      let archiveCredentialStore = ArchiveUploaderCredentialStore()
      let transport = URLSessionTransport()
      let metricQuery = HealthKitMetricQueryService(store: HKHealthStoreClient())
      let checkpointStore = try ProtectedSyncCheckpointStore()
      let statusStore = try ProtectedSyncStatusStore()
      let pairingStore = try ProtectedPairingStore()
      let pairingCheckpointStore = try ProtectedPairingCheckpointStore()
      let backfillCheckpointStore = try ProtectedBackfillCheckpointStore()
      let archiveCheckpointStore = try ProtectedArchiveCheckpointStore()
      let archiveQuery = HealthKitArchiveQueryService()
      let archiveProgress = ArchiveProgressRelay()
      let archiveCoordinator = ArchiveImportCoordinator(
        access: lifetimeUnlock.access,
        query: archiveQuery, checkpointStore: archiveCheckpointStore,
        connection: {
          guard #available(iOS 27.0, *) else { throw NetworkFailure.protocolMismatch }
          let configuration = try await configurationStore.load()
          let baseURL = try NormalizedBaseURL.parse(
            configuration.baseURL,
            allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP)
          guard let token = try await credentialStore.read(.webhookSecret) else {
            throw CredentialStoreError.blankValue
          }
          let uploaderCredential = try await archiveCredentialStore.loadOrCreate()
          let client = HealthBridgeArchiveClient(
            transport: transport,
            userID: configuration.healthBridgeUserID, token: token,
            uploaderCredential: uploaderCredential)
          let capability = try await client.probe(
            baseURL: baseURL,
            userID: configuration.healthBridgeUserID, token: token)
          guard let uploaderFingerprint = client.uploaderFingerprint else {
            throw ArchiveClientError.invalidRequest
          }
          return ArchiveImportConnection(
            baseURL: baseURL,
            userID: configuration.healthBridgeUserID, token: token, capability: capability,
            sender: client, statusFetcher: client,
            uploaderFingerprint: uploaderFingerprint)
        },
        progress: { report in await archiveProgress.publish(report) })
      let archiveCapabilityProbe: @Sendable () async throws -> ArchiveCapability = {
        guard #available(iOS 27.0, *) else { throw NetworkFailure.protocolMismatch }
        let configuration = try await configurationStore.load()
        let baseURL = try NormalizedBaseURL.parse(
          configuration.baseURL,
          allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP)
        guard let token = try await credentialStore.read(.webhookSecret) else {
          throw CredentialStoreError.blankValue
        }
        let uploaderCredential = try await archiveCredentialStore.loadOrCreate()
        return try await HealthBridgeArchiveClient(
          transport: transport, userID: configuration.healthBridgeUserID, token: token,
          uploaderCredential: uploaderCredential
        ).probe(baseURL: baseURL, userID: configuration.healthBridgeUserID, token: token)
      }
      let archiveOwnerClaim: @Sendable () async throws -> ArchiveOwnerClaimStatus = {
        guard #available(iOS 27.0, *) else { throw NetworkFailure.protocolMismatch }
        let configuration = try await configurationStore.load()
        let baseURL = try NormalizedBaseURL.parse(
          configuration.baseURL,
          allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP)
        guard let token = try await credentialStore.read(.webhookSecret) else {
          throw CredentialStoreError.blankValue
        }
        let uploaderCredential = try await archiveCredentialStore.loadOrCreate()
        let client = HealthBridgeArchiveClient(
          transport: transport, userID: configuration.healthBridgeUserID, token: token,
          uploaderCredential: uploaderCredential)
        return try await client.claimOwner(baseURL: baseURL)
      }
      let archiveUploaderFingerprint: @Sendable () async throws -> String = {
        let uploaderCredential = try await archiveCredentialStore.loadOrCreate()
        guard let fingerprint = HealthBridgeArchiveClient.fingerprint(for: uploaderCredential)
        else {
          throw ArchiveClientError.invalidRequest
        }
        return fingerprint
      }
      let archiveUploaderCredentialDelete: @Sendable () async throws -> Void = {
        try await archiveCredentialStore.delete()
      }
      let medicationCheckpointStore = try ProtectedMedicationCheckpointStore()
      let metricFreshnessStore = try ProtectedMetricFreshnessStore()
      let changeQuery = HealthKitAnchoredQueryService(
        client: HKHealthStoreAnchoredQueryClient()
      )
      let webhookClient = HealthBridgeWebhookClient(transport: transport)
      let authenticatedClient = HomeAssistantClient(transport: transport)
      let healthSampleWriter = HealthKitSampleWriter(client: HKHealthStoreWritingClient())
      let medicationReader = HealthKitMedicationReader(client: HKHealthStoreMedicationClient())
      let medicationCoordinator = MedicationSyncCoordinator(
        configurationStore: configurationStore,
        credentialStore: credentialStore,
        reader: medicationReader,
        sender: webhookClient,
        checkpointStore: medicationCheckpointStore
      )
      let coordinator = SyncCoordinator(
        configurationStore: configurationStore,
        credentialStore: credentialStore,
        metricQuery: metricQuery,
        webhookSender: webhookClient,
        checkpointStore: checkpointStore,
        changeQuery: changeQuery,
        medicationSyncCoordinator: medicationCoordinator
      )
      let inboundCoordinator = InboundSyncCoordinator(
        pairingStore: pairingStore,
        configurationStore: configurationStore,
        credentialStore: credentialStore,
        stateFetcher: authenticatedClient,
        writer: healthSampleWriter,
        checkpointStore: pairingCheckpointStore
      )
      let backfillCoordinator = BackfillCoordinator(
        access: lifetimeUnlock.access,
        configurationStore: configurationStore,
        credentialStore: credentialStore,
        liveCoordinator: coordinator,
        pointQuery: metricQuery,
        sender: HealthBridgeBackfillClient(transport: transport),
        checkpointStore: backfillCheckpointStore
      )
      let bidirectionalCoordinator = BidirectionalSyncCoordinator(
        outbound: coordinator,
        inbound: inboundCoordinator,
        configurationStore: configurationStore,
        statusStore: statusStore,
        paidAccess: lifetimeUnlock.access,
        contextProvider: SystemSyncRunContextProvider(),
        freshnessStore: metricFreshnessStore
      )
      let attemptPublisher = SyncAttemptPublisher(
        configurationStore: configurationStore,
        credentialStore: credentialStore,
        client: authenticatedClient
      )
      let backgroundRuntime = BackgroundSyncRuntime(
        access: lifetimeUnlock.access,
        baseCoordinator: bidirectionalCoordinator,
        makeObserverManager: { observedCoordinator in
          HealthKitObserverManager(
            client: HKHealthKitBackgroundDeliveryClient(),
            coordinator: observedCoordinator,
            statusStore: statusStore
          )
        },
        refreshManager: AppRefreshManager(scheduler: BGTaskSchedulerAdapter()),
        configurationStore: configurationStore,
        credentialStore: credentialStore,
        statusStore: statusStore,
        publisher: attemptPublisher
      )
      lifetimeUnlock.onAccessChanged = { [weak backgroundRuntime] in
        Task { await backgroundRuntime?.reconcile() }
      }
      backgroundRuntime.start()
      let intentHandler = AppIntentSyncHandler(coordinator: backgroundRuntime.coordinator)
      AppDependencyManager.shared.add(dependency: intentHandler)
      let model = AppModel(
        bidirectionalSyncCoordinator: backgroundRuntime.coordinator,
        backfillCoordinator: backfillCoordinator,
        backfillCheckpointStore: backfillCheckpointStore,
        archiveCoordinator: archiveCoordinator,
        archiveCheckpointStore: archiveCheckpointStore,
        archiveQuery: archiveQuery,
        archiveCapabilityProbe: archiveCapabilityProbe,
        archiveOwnerClaim: archiveOwnerClaim,
        archiveUploaderFingerprint: archiveUploaderFingerprint,
        archiveUploaderCredentialDelete: archiveUploaderCredentialDelete,
        configurationStore: configurationStore,
        credentialStore: credentialStore,
        metricQuery: metricQuery,
        authenticatedClient: authenticatedClient,
        homeAssistantStateLister: authenticatedClient,
        webhookClient: webhookClient,
        backgroundRuntime: backgroundRuntime,
        syncAttemptPublisher: attemptPublisher,
        statusStore: statusStore,
        pairingStore: pairingStore,
        pairingCheckpointStore: pairingCheckpointStore,
        syncCheckpointStore: checkpointStore,
        medicationCheckpointStore: medicationCheckpointStore,
        metricFreshnessStore: metricFreshnessStore,
        healthSampleWriter: healthSampleWriter,
        medicationAccess: medicationReader
      )
      archiveProgress.model = model
      return model
    } catch {
      return AppModel(bidirectionalSyncCoordinator: nil, startupError: .configuration)
    }
  }

  private static func makeUITestOnboardingModel() -> AppModel {
    let credentialStore = InMemoryCredentialStore()
    return AppModel(
      bidirectionalSyncCoordinator: UITestSyncCoordinator(),
      configurationStore: InMemoryConfigurationStore(),
      credentialStore: credentialStore,
      metricQuery: UITestMetricQuery(),
      authenticatedClient: UITestAuthenticatedClient(),
      webhookClient: UITestWebhookClient()
    )
  }

  private static func makeUITestDashboardModel() -> AppModel {
    let purchaseFixture: (any LifetimeUnlockPresenting)? =
      ProcessInfo.processInfo.arguments.contains("-ui-testing-purchase-interactions")
      ? UITestLifetimeUnlock() : nil
    let configuration = AppConfiguration(
      baseURL: "https://example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .distance, .flightsClimbed, .bodyMass],
      backgroundSyncEnabled: false
    )
    return AppModel(
      bidirectionalSyncCoordinator: UITestSyncCoordinator(),
      metricQuery: UITestMetricQuery(),
      initialConfiguration: configuration,
      isOnboardingComplete: true,
      lifetimeUnlockFixture: purchaseFixture
    )
  }

  private static func makeUITestBackgroundModel(
    enabled: Bool = true,
    frequency: BackgroundSyncFrequency = .balanced,
    starvedMetrics: Int? = 2
  ) -> AppModel {
    let date = Date(timeIntervalSince1970: 1_788_035_400)
    let configuration = AppConfiguration(
      baseURL: "https://example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .bodyMass, .restingHeartRate],
      backgroundSyncEnabled: enabled,
      backgroundSyncFrequency: frequency
    )
    let status = SyncStatusSnapshot(
      lastAttemptedAt: date,
      lastSuccessfulAt: date,
      lastFailure: SyncStatusFailure(metricID: .steps, category: .offline, at: date),
      registrations: [
        .steps: .registered(at: date),
        .bodyMass: .registered(at: date),
        .restingHeartRate: .failed(category: .healthKit, at: date),
      ],
      recentEvents: [
        SyncStatusEvent(
          report: BidirectionalSyncReport(
            trigger: .background,
            outbound: SyncReport(
              trigger: .background,
              attemptedMetrics: 3,
              synchronizedMetrics: 2,
              skippedMetrics: 0,
              failures: [.init(metricID: .restingHeartRate, category: .healthKit)],
              startedAt: date,
              finishedAt: date
            ),
            inbound: InboundSyncReport(
              trigger: .background,
              attemptedPairings: 1,
              savedPairings: 1,
              skippedPairings: 0,
              failures: [],
              startedAt: date,
              finishedAt: date
            ),
            startedAt: date,
            finishedAt: date
          )
        ),
        SyncStatusEvent(
          report: BidirectionalSyncReport(
            trigger: .manual,
            outbound: SyncReport(
              trigger: .manual,
              attemptedMetrics: 3,
              synchronizedMetrics: 3,
              skippedMetrics: 0,
              failures: [],
              startedAt: date.addingTimeInterval(1),
              finishedAt: date.addingTimeInterval(1),
              collectedMetrics: 3
            ),
            inbound: InboundSyncReport(
              trigger: .manual,
              attemptedPairings: 1,
              savedPairings: 1,
              skippedPairings: 0,
              failures: [],
              startedAt: date.addingTimeInterval(1),
              finishedAt: date.addingTimeInterval(1)
            ),
            startedAt: date.addingTimeInterval(1),
            finishedAt: date.addingTimeInterval(1),
            scopeReason: .trigger,
            requestedMetrics: 3,
            starvedMetrics: starvedMetrics
          )
        ),
      ]
    )
    return AppModel(
      bidirectionalSyncCoordinator: UITestSyncCoordinator(),
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      metricFreshnessStore: InMemoryMetricFreshnessStore(
        snapshot: MetricFreshnessSnapshot(lastFullSweepAt: date)
      ),
      initialConfiguration: configuration,
      isOnboardingComplete: true,
      initialSyncStatus: status
    )
  }

  private static func makeUITestPairingsModel() -> AppModel {
    let configuration = AppConfiguration(
      baseURL: "https://example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .bodyMass, .restingHeartRate],
      backgroundSyncEnabled: false
    )
    return AppModel(
      bidirectionalSyncCoordinator: UITestSyncCoordinator(),
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: UITestCredentialStore(),
      homeAssistantStateLister: UITestHomeAssistantStateLister(),
      pairingStore: InMemoryPairingStore(),
      pairingCheckpointStore: InMemoryPairingCheckpointStore(),
      healthSampleWriter: UITestHealthSampleWriter(),
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )
  }

  private static func makeUITestExperimentalModel(
    medicationAvailable: Bool,
    reportsSkippedHistory: Bool = false
  ) -> AppModel {
    let configuration = AppConfiguration(
      baseURL: "https://example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .bodyMass, .restingHeartRate],
      backgroundSyncEnabled: false
    )
    return AppModel(
      bidirectionalSyncCoordinator: UITestSyncCoordinator(),
      backfillCoordinator: UITestBackfillCoordinator(
        reportsSkippedHistory: reportsSkippedHistory
      ),
      backfillCheckpointStore: InMemoryBackfillCheckpointStore(),
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      medicationAccess: medicationAvailable ? UITestMedicationAccess() : nil,
      medicationSyncAvailable: medicationAvailable,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )
  }

  private static func makeUITestArchiveModel(recoveryRequired: Bool) -> AppModel {
    var configuration = AppConfiguration(
      baseURL: "https://example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .lastAppleWorkout, .cyclingPower],
      backgroundSyncEnabled: false
    )
    configuration.experimentalBackfillEnabled = true
    return AppModel(
      bidirectionalSyncCoordinator: UITestSyncCoordinator(),
      backfillCoordinator: UITestBackfillCoordinator(),
      backfillCheckpointStore: InMemoryBackfillCheckpointStore(),
      archiveCoordinator: UITestArchiveCoordinator(recoveryRequired: recoveryRequired),
      archiveCheckpointStore: InMemoryArchiveCheckpointStore(),
      archiveQuery: UITestArchiveQuery(),
      archiveCapabilityProbe: {
        let json = """
          {"ok":true,"request_type":"archive_capability","protocol_version":2,
          "request_id":"ui-test-request","archive_schema_version":3,
          "ownership_contract_version":1,"owner_state":"active","owner_generation":1,
          "max_batch_bytes":1024,
          "max_samples_per_batch":10,"max_deletions_per_batch":10,
          "supported_sample_types":["HKQuantityTypeIdentifierStepCount","HKWorkoutType",
          "HKQuantityTypeIdentifierCyclingPower"],
          "supported_metrics":["steps","last_apple_workout","cycling_power"],
          "archive_available":true,"statistics_available":true}
          """
        return try JSONDecoder().decode(ArchiveCapability.self, from: Data(json.utf8))
      },
      archiveUploaderFingerprint: { "66687aadf862" },
      supportsFullHistoryOS: { true },
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )
  }

  private static func makeUITestMaintenanceModel() -> AppModel {
    let configuration = AppConfiguration(
      baseURL: "https://example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .bodyMass],
      backgroundSyncEnabled: true,
      backgroundSyncFrequency: .batterySaver
    )
    return AppModel(
      bidirectionalSyncCoordinator: UITestSyncCoordinator(),
      backfillCheckpointStore: InMemoryBackfillCheckpointStore(),
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: UITestCredentialStore(),
      statusStore: InMemorySyncStatusStore(),
      pairingStore: InMemoryPairingStore(),
      pairingCheckpointStore: InMemoryPairingCheckpointStore(),
      syncCheckpointStore: InMemorySyncCheckpointStore(),
      medicationCheckpointStore: InMemoryMedicationCheckpointStore(),
      metricFreshnessStore: InMemoryMetricFreshnessStore(),
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )
  }
}

@MainActor
@Observable
private final class UITestLifetimeUnlock: LifetimeUnlockPresenting {
  var state: PaidAccessState = .locked
  let displayPrice: String? = "CHF 9.00"

  func load() async {}

  func purchase() async -> PurchaseOutcome { .cancelled }

  func restore() async throws { state = .unlocked }
}

@MainActor
private final class ArchiveProgressRelay {
  weak var model: AppModel?

  func publish(_ report: ArchiveImportReport) {
    model?.receiveArchiveProgress(report)
  }
}

private actor UITestArchiveQuery: HealthArchiveQuerying {
  private let date = Date(timeIntervalSince1970: 1_700_000_000)

  func discover(types: Set<HealthObjectTypeID>) -> [HealthObjectTypeID: ReadableHistory] {
    Dictionary(
      uniqueKeysWithValues: types.map {
        ($0, .readable(earliest: date, authorizationBoundary: nil))
      })
  }

  func discover(metrics: [MetricDefinition]) -> ArchiveHistoryDiscovery {
    ArchiveHistoryDiscovery(
      types: discover(types: Set(metrics.map(\.healthObjectType))),
      metrics: Dictionary(
        uniqueKeysWithValues: metrics.map {
          ($0.id, .readable(earliest: date, authorizationBoundary: nil))
        }))
  }

  func page(
    type: HealthObjectTypeID, interval: DateInterval, cursor: ArchiveScanCursor?, limit: Int
  ) throws -> ArchiveSamplePage { throw NetworkFailure.protocolMismatch }

  func changes(type: HealthObjectTypeID, anchor: Data?) throws -> ArchiveChangePage {
    throw NetworkFailure.protocolMismatch
  }
}

private actor UITestArchiveCoordinator: ArchiveImportCoordinating {
  let recoveryRequired: Bool
  init(recoveryRequired: Bool) { self.recoveryRequired = recoveryRequired }

  func importHistory(selection: ArchiveImportSelection) -> ArchiveImportReport {
    var report = ArchiveImportReport()
    report.archiveState = .archived
    report.archivedSamples = 12
    report.projectionStates[.steps] = .failed
    if recoveryRequired {
      report.archiveState = .paused
      report.failures = [
        ArchiveImportIssue.authorizationUnproven, .inventoryTooDense, .inventoryUnstable,
      ].map { .init(type: .stepCount, category: .healthKit, issue: $0) }
    }
    return report
  }

  func pause() {}

  func resume() -> ArchiveImportReport { ArchiveImportReport() }

  func refreshProjection() -> ArchiveImportReport { ArchiveImportReport() }
}

private actor UITestMetricQuery: MetricQuerying {
  func requestReadAuthorization(for metrics: Set<MetricID>) {}

  func currentReading(
    for definition: MetricDefinition,
    now: Date,
    calendar: Calendar
  ) -> MetricReading? {
    let value: Double
    switch definition.id {
    case .steps:
      value = 246
    case .distance:
      value = 1_234
    case .flightsClimbed:
      value = 8
    case .bodyMass:
      value = 84
    default:
      return nil
    }
    return MetricReading(metricID: definition.id, timestamp: now, value: value)
  }
}

private actor UITestAuthenticatedClient: AuthenticatedConnectionTesting {
  func testAuthenticatedAPI(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) -> HomeAssistantAPIStatus {
    HomeAssistantAPIStatus(message: "API running.")
  }
}

private actor UITestWebhookClient: WebhookConnectionTesting {
  func testWebhook(
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) -> WebhookConnectionAcknowledgement {
    WebhookConnectionAcknowledgement(
      ok: true,
      integrationVersion: "1.2.1",
      backfillProtocol: 1,
      backfillAcknowledgement: "committed",
      statisticsPolicy: "history_only"
    )
  }
}

private actor UITestSyncCoordinator: BidirectionalSyncCoordinating {
  func sync(trigger: SyncTrigger) -> BidirectionalSyncOutcome {
    let date = Date(timeIntervalSince1970: 1_788_035_400)
    return .performed(
      BidirectionalSyncReport(
        trigger: trigger,
        outbound: SyncReport(
          trigger: trigger,
          attemptedMetrics: 3,
          synchronizedMetrics: 3,
          skippedMetrics: 0,
          failures: [],
          startedAt: date,
          finishedAt: date
        ),
        inbound: InboundSyncReport(
          trigger: trigger,
          attemptedPairings: 0,
          savedPairings: 0,
          skippedPairings: 0,
          failures: [],
          startedAt: date,
          finishedAt: date
        ),
        startedAt: date,
        finishedAt: date
      )
    )
  }
}

private actor UITestBackfillCoordinator: BackfillCoordinating {
  private let reportsSkippedHistory: Bool

  init(reportsSkippedHistory: Bool = false) {
    self.reportsSkippedHistory = reportsSkippedHistory
  }

  func importHistory(metrics: Set<MetricID>, requestedStart: Date) -> BackfillReport {
    if reportsSkippedHistory {
      return BackfillReport(
        attemptedMetrics: 85,
        committedMetrics: 16,
        skippedMetrics: 69,
        committedPoints: 370,
        capability: .available(protocolVersion: 1),
        failures: []
      )
    }
    return BackfillReport(
      attemptedMetrics: metrics.count,
      committedMetrics: 0,
      skippedMetrics: 0,
      committedPoints: 0,
      capability: .incompatible(reason: .unsupportedRecorder),
      failures: [.init(metricID: nil, category: .compatibility)]
    )
  }
}

private actor UITestMedicationAccess: MedicationAccessProviding {
  func requestAuthorizationAndList() -> [MedicationConcept] {
    [
      MedicationConcept(
        id: MedicationIdentifier.make(from: Data("example-medication".utf8)),
        name: "Example medication"
      )
    ]
  }
}

private actor UITestHealthSampleWriter: HealthSampleWriting {
  func requestWriteAuthorization(for destinations: Set<HealthObjectTypeID>) {}

  func save(_ sample: HealthSampleWrite) {}
}

private actor UITestCredentialStore: CredentialStore {
  func read(_ kind: CredentialKind) -> String? {
    switch kind {
    case .accessToken: "ui-test-access-token"
    case .webhookSecret: "ui-test-webhook-secret"
    }
  }

  func write(_ value: String, for kind: CredentialKind) {}

  func delete(_ kind: CredentialKind) {}

  func deleteAll() {}
}

private actor UITestHomeAssistantStateLister: HomeAssistantStateListing {
  func fetchStates(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) -> [HomeAssistantState] {
    let date = Date(timeIntervalSince1970: 1_788_052_800)
    return [
      HomeAssistantState(
        entityID: "sensor.home_current_uv_index",
        state: "4.2",
        lastChanged: date,
        lastUpdated: date,
        attributes: .init(unitOfMeasurement: nil, friendlyName: "Home Current UV Index")
      )
    ]
  }
}
