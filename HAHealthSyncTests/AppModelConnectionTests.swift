import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppModelConnectionTests: XCTestCase {
  private let configuration = AppConfiguration(
    baseURL: "https://ha.example.com",
    allowsConfirmedLocalHTTP: false,
    healthBridgeUserID: "oleh",
    selectedMetrics: [.steps, .bodyMass],
    backgroundSyncEnabled: false
  )

  func testAuthenticatedConnectionReadsOnlyAccessToken() async throws {
    let credentialStore = RecordingCredentialStore()
    try await credentialStore.write("fixture-token", for: .accessToken)
    try await credentialStore.write("fixture-secret", for: .webhookSecret)
    await credentialStore.resetReads()
    let authenticatedClient = FakeAuthenticatedConnectionTester()
    let model = makeModel(
      credentialStore: credentialStore,
      authenticatedClient: authenticatedClient
    )

    await model.testAuthenticatedConnection(configuration: configuration)

    let reads = await credentialStore.reads
    let tokens = await authenticatedClient.tokens
    XCTAssertEqual(reads, [.accessToken])
    XCTAssertEqual(model.authenticatedConnectionState, .succeeded)
    XCTAssertEqual(tokens, ["fixture-token"])
  }

  func testWebhookConnectionReadsOnlyWebhookSecret() async throws {
    let credentialStore = RecordingCredentialStore()
    try await credentialStore.write("fixture-token", for: .accessToken)
    try await credentialStore.write("fixture-secret", for: .webhookSecret)
    await credentialStore.resetReads()
    let webhookClient = FakeWebhookConnectionTester()
    let model = makeModel(
      credentialStore: credentialStore,
      webhookClient: webhookClient
    )

    await model.testWebhookConnection(configuration: configuration)

    let reads = await credentialStore.reads
    let secrets = await webhookClient.secrets
    XCTAssertEqual(reads, [.webhookSecret])
    XCTAssertEqual(model.webhookConnectionState, .succeeded)
    XCTAssertEqual(secrets, ["fixture-secret"])
  }

  func testAuthenticatedConnectionDistinguishesNetworkFailureFromRejectedToken() async throws {
    let credentialStore = RecordingCredentialStore()
    try await credentialStore.write("fixture-token", for: .accessToken)

    let offlineModel = makeModel(
      credentialStore: credentialStore,
      authenticatedClient: FailingAuthenticatedConnectionTester(error: .offline)
    )
    await offlineModel.testAuthenticatedConnection(configuration: configuration)
    XCTAssertEqual(offlineModel.authenticatedConnectionState, .failed(.offline))

    let rejectedTokenModel = makeModel(
      credentialStore: credentialStore,
      authenticatedClient: FailingAuthenticatedConnectionTester(error: .unauthorized)
    )
    await rejectedTokenModel.testAuthenticatedConnection(configuration: configuration)
    XCTAssertEqual(rejectedTokenModel.authenticatedConnectionState, .failed(.unauthorized))
  }

  func testInvalidBaseURLIsConfigurationFailureInsteadOfTokenFailure() async throws {
    let credentialStore = RecordingCredentialStore()
    try await credentialStore.write("fixture-token", for: .accessToken)
    let model = makeModel(credentialStore: credentialStore)
    var invalidConfiguration = configuration
    invalidConfiguration.baseURL = "not a URL"

    await model.testAuthenticatedConnection(configuration: invalidConfiguration)

    XCTAssertEqual(model.authenticatedConnectionState, .failed(.configuration))
  }

  func testSaveConnectionPersistsCredentialsSeparatelyAndClearsNoSecretIntoConfiguration()
    async throws
  {
    let credentialStore = RecordingCredentialStore()
    let configurationStore = InMemoryConfigurationStore()
    let model = makeModel(
      configurationStore: configurationStore,
      credentialStore: credentialStore
    )

    await model.saveConnection(
      configuration: configuration,
      webhookSecret: "fixture-secret",
      accessToken: "fixture-token"
    )

    XCTAssertNil(model.currentError)
    XCTAssertTrue(model.isOnboardingComplete)
    let storedConfiguration = try await configurationStore.load()
    let storedSecret = await credentialStore.value(for: .webhookSecret)
    let storedToken = await credentialStore.value(for: .accessToken)
    XCTAssertEqual(storedConfiguration, configuration)
    XCTAssertEqual(storedSecret, "fixture-secret")
    XCTAssertEqual(storedToken, "fixture-token")
    let encoded = try ConfigurationCodec.encode(configuration)
    let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    XCTAssertFalse(text.contains("fixture-secret"))
    XCTAssertFalse(text.contains("fixture-token"))
  }

  func testCompletingOnboardingRunsInitialSynchronizationThroughSharedCoordinator() async {
    let coordinator = InitialSyncCoordinator()
    let model = AppModel(
      bidirectionalSyncCoordinator: coordinator,
      configurationStore: InMemoryConfigurationStore(),
      credentialStore: RecordingCredentialStore()
    )

    await model.completeOnboarding(
      configuration: configuration,
      webhookSecret: "fixture-secret",
      accessToken: "fixture-token"
    )

    let triggers = await coordinator.triggers
    XCTAssertEqual(triggers, [.manual])
    XCTAssertEqual(model.lastReport?.synchronizedMetrics, 2)
    XCTAssertTrue(model.isOnboardingComplete)
  }

  func testInvalidOnboardingDoesNotAttemptInitialSynchronization() async {
    let coordinator = InitialSyncCoordinator()
    let model = AppModel(
      bidirectionalSyncCoordinator: coordinator,
      configurationStore: InMemoryConfigurationStore(),
      credentialStore: RecordingCredentialStore()
    )
    var invalidConfiguration = configuration
    invalidConfiguration.baseURL = "http://example.com"

    await model.completeOnboarding(
      configuration: invalidConfiguration,
      webhookSecret: "fixture-secret",
      accessToken: "fixture-token"
    )

    let triggers = await coordinator.triggers
    XCTAssertTrue(triggers.isEmpty)
    XCTAssertFalse(model.isOnboardingComplete)
  }

  func testAuthorizationRequestsOnlySelectedMetrics() async {
    let query = FakeAuthorizationMetricQuery()
    let model = makeModel(metricQuery: query)

    await model.requestHealthAuthorization(for: [.steps, .bodyMass])

    let authorizationRequests = await query.authorizationRequests
    XCTAssertEqual(authorizationRequests, [[.steps, .bodyMass]])
    XCTAssertNil(model.currentError)
  }

  func testMetricSelectionRequestsOnlyNewTypesAndPersistsRemoval() async throws {
    let configurationStore = InMemoryConfigurationStore(configuration: configuration)
    let query = FakeAuthorizationMetricQuery()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: configurationStore,
      metricQuery: query,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )

    await model.updateSelectedMetrics([.bodyMass, .restingHeartRate])

    let requests = await query.authorizationRequests
    XCTAssertEqual(requests, [[.restingHeartRate]])
    XCTAssertEqual(model.currentConfiguration.selectedMetrics, [.bodyMass, .restingHeartRate])
    let stored = try await configurationStore.load()
    XCTAssertEqual(stored.selectedMetrics, [.bodyMass, .restingHeartRate])
  }

  func testLoadLeavesBackgroundOwnershipToTheRuntimeWithoutPrompting() async throws {
    var enabledConfiguration = configuration
    enabledConfiguration.backgroundSyncEnabled = true
    let configurationStore = InMemoryConfigurationStore(configuration: enabledConfiguration)
    let credentialStore = RecordingCredentialStore()
    try await credentialStore.write("fixture-secret", for: .webhookSecret)
    try await credentialStore.write("fixture-token", for: .accessToken)
    let runtime = RecordingBackgroundRuntime()
    let query = FakeAuthorizationMetricQuery()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: configurationStore,
      credentialStore: credentialStore,
      metricQuery: query,
      backgroundRuntime: runtime
    )

    await model.load()

    XCTAssertTrue(model.isOnboardingComplete)
    XCTAssertEqual(runtime.reconcileCount, 0)
    let authorizationRequests = await query.authorizationRequests
    XCTAssertTrue(authorizationRequests.isEmpty)
  }

  func testBackgroundTogglePersistsAndReconcilesRuntime() async throws {
    let configurationStore = InMemoryConfigurationStore(configuration: configuration)
    let runtime = RecordingBackgroundRuntime()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: configurationStore,
      backgroundRuntime: runtime,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )

    await model.setBackgroundSyncEnabled(true)

    XCTAssertTrue(model.backgroundSyncEnabled)
    let storedConfiguration = try await configurationStore.load()
    XCTAssertTrue(storedConfiguration.backgroundSyncEnabled)
    XCTAssertEqual(runtime.reconcileCount, 1)
  }

  func testBackgroundFrequencyPersistsThenReconcilesRuntime() async throws {
    var enabledConfiguration = configuration
    enabledConfiguration.backgroundSyncEnabled = true
    let configurationStore = InMemoryConfigurationStore(configuration: enabledConfiguration)
    let lastAttempt = Date(timeIntervalSince1970: 1_788_035_000)
    let statusStore = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(lastAttemptedAt: lastAttempt)
    )
    let runtime = RecordingBackgroundRuntime()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: configurationStore,
      backgroundRuntime: runtime,
      statusStore: statusStore,
      initialConfiguration: enabledConfiguration,
      isOnboardingComplete: true
    )

    await model.setBackgroundSyncFrequency(.daily)

    XCTAssertEqual(model.currentConfiguration.backgroundSyncFrequency, .daily)
    let storedConfiguration = try await configurationStore.load()
    XCTAssertEqual(storedConfiguration.backgroundSyncFrequency, .daily)
    XCTAssertEqual(runtime.reconcileCount, 1)
  }

  func testBackgroundFrequencySaveFailureKeepsBalancedAndDoesNotReconcile() async {
    let runtime = RecordingBackgroundRuntime()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: FailingConfigurationStore(),
      backgroundRuntime: runtime,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )

    await model.setBackgroundSyncFrequency(.daily)

    XCTAssertEqual(model.currentConfiguration.backgroundSyncFrequency, .balanced)
    XCTAssertEqual(runtime.reconcileCount, 0)
    XCTAssertEqual(model.currentError, .configuration)
  }

  private func makeModel(
    configurationStore: any ConfigurationStore = InMemoryConfigurationStore(),
    credentialStore: any CredentialStore = RecordingCredentialStore(),
    metricQuery: any MetricQuerying = FakeAuthorizationMetricQuery(),
    authenticatedClient: any AuthenticatedConnectionTesting = FakeAuthenticatedConnectionTester(),
    webhookClient: any WebhookConnectionTesting = FakeWebhookConnectionTester()
  ) -> AppModel {
    AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: configurationStore,
      credentialStore: credentialStore,
      metricQuery: metricQuery,
      authenticatedClient: authenticatedClient,
      webhookClient: webhookClient
    )
  }
}

private actor InitialSyncCoordinator: BidirectionalSyncCoordinating {
  private(set) var triggers: [SyncTrigger] = []

  func sync(trigger: SyncTrigger) -> BidirectionalSyncOutcome {
    triggers.append(trigger)
    let now = Date(timeIntervalSince1970: 1_788_035_400)
    return .performed(
      BidirectionalSyncReport(
        trigger: trigger,
        outbound: SyncReport(
          trigger: trigger,
          attemptedMetrics: 2,
          synchronizedMetrics: 2,
          skippedMetrics: 0,
          failures: [],
          startedAt: now,
          finishedAt: now
        ),
        inbound: nil,
        startedAt: now,
        finishedAt: now
      )
    )
  }
}

@MainActor
private final class RecordingBackgroundRuntime: BackgroundSyncRuntimeControlling {
  private(set) var reconcileCount = 0
  private(set) var suspendCount = 0

  func reconcile() async { reconcileCount += 1 }
  func suspend() async { suspendCount += 1 }
}

private actor FailingConfigurationStore: ConfigurationStore {
  func load() throws -> AppConfiguration { throw Failure.expected }
  func save(_ configuration: AppConfiguration) throws { throw Failure.expected }
  func delete() throws { throw Failure.expected }

  private enum Failure: Error { case expected }
}

private actor RecordingCredentialStore: CredentialStore {
  private var values: [CredentialKind: String] = [:]
  private(set) var reads: [CredentialKind] = []

  func value(for kind: CredentialKind) -> String? {
    values[kind]
  }

  func resetReads() {
    reads = []
  }

  func read(_ kind: CredentialKind) -> String? {
    reads.append(kind)
    return values[kind]
  }

  func write(_ value: String, for kind: CredentialKind) throws {
    guard !value.isEmpty else { throw CredentialStoreError.blankValue }
    values[kind] = value
  }

  func delete(_ kind: CredentialKind) {
    values[kind] = nil
  }

  func deleteAll() {
    values = [:]
  }
}

private actor FakeAuthenticatedConnectionTester: AuthenticatedConnectionTesting {
  private(set) var tokens: [String] = []

  func testAuthenticatedAPI(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) -> HomeAssistantAPIStatus {
    tokens.append(accessToken)
    return HomeAssistantAPIStatus(message: "API running.")
  }
}

private actor FailingAuthenticatedConnectionTester: AuthenticatedConnectionTesting {
  let error: NetworkFailure

  init(error: NetworkFailure) {
    self.error = error
  }

  func testAuthenticatedAPI(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) throws -> HomeAssistantAPIStatus {
    throw error
  }
}

private actor FakeWebhookConnectionTester: WebhookConnectionTesting {
  private(set) var secrets: [String] = []

  func testWebhook(
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) -> WebhookConnectionAcknowledgement {
    secrets.append(webhookSecret)
    return WebhookConnectionAcknowledgement(
      ok: true,
      integrationVersion: "1.2.1",
      backfillProtocol: 1,
      backfillAcknowledgement: "committed",
      statisticsPolicy: "history_only"
    )
  }
}

private actor FakeAuthorizationMetricQuery: MetricQuerying {
  private(set) var authorizationRequests: [Set<MetricID>] = []

  func requestReadAuthorization(for metrics: Set<MetricID>) {
    authorizationRequests.append(metrics)
  }

  func currentReading(
    for definition: MetricDefinition,
    now: Date,
    calendar: Calendar
  ) -> MetricReading? {
    nil
  }
}
