import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppModelPairingTests: XCTestCase {
  private let configuration = AppConfiguration(
    baseURL: "https://ha.example.invalid",
    allowsConfirmedLocalHTTP: false,
    healthBridgeUserID: "fixture-user",
    selectedMetrics: [.steps, .bodyMass],
    backgroundSyncEnabled: false
  )

  func testLoadAndSavePairingDoNotChangeOutboundMetricSelection() async throws {
    let pairingStore = InMemoryPairingStore()
    let configurationStore = InMemoryConfigurationStore(configuration: configuration)
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    try await credentials.write("fixture-token", for: .accessToken)
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: configurationStore,
      credentialStore: credentials,
      pairingStore: pairingStore
    )
    let pairing = makePairing()

    await model.load()
    let saved = await model.savePairing(pairing)
    let storedMetrics = try await configurationStore.load().selectedMetrics

    XCTAssertTrue(saved)
    XCTAssertEqual(model.pairings, [pairing])
    XCTAssertEqual(model.currentConfiguration.selectedMetrics, [.steps, .bodyMass])
    XCTAssertEqual(storedMetrics, [.steps, .bodyMass])
  }

  func testRequestsWriteAuthorizationOnlyForExplicitDestinations() async {
    let writer = RecordingPairingHealthWriter()
    let model = AppModel(bidirectionalSyncCoordinator: nil, healthSampleWriter: writer)

    await model.requestHealthWriteAuthorization(for: [.bodyMass, .dietaryWater])

    let requests = await writer.authorizationRequests()
    XCTAssertEqual(requests, [[.bodyMass, .dietaryWater]])
    XCTAssertNil(model.currentError)
  }

  func testDuplicateValidationIsExposedWithoutReplacingStoredPairings() async throws {
    let original = makePairing()
    let store = try InMemoryPairingStore(pairings: [original])
    let model = AppModel(bidirectionalSyncCoordinator: nil, pairingStore: store)
    await model.reloadPairings()
    let duplicate = Pairing(
      entityID: original.entityID,
      destination: original.destination,
      sourceUnit: original.sourceUnit,
      destinationUnit: original.destinationUnit,
      transformation: .identity,
      isEnabled: true
    )

    let saved = await model.savePairing(duplicate)
    let pairings = try await store.all()

    XCTAssertFalse(saved)
    XCTAssertEqual(model.pairingValidationError, .duplicateEnabledPairing)
    XCTAssertEqual(pairings, [original])
  }

  func testDeleteRemovesPairingAndItsCheckpoint() async throws {
    let pairing = makePairing()
    let store = try InMemoryPairingStore(pairings: [pairing])
    let identity = SyncIdentity.make(
      pairingID: pairing.id,
      entityID: pairing.entityID,
      homeAssistantUpdatedAt: Date(timeIntervalSince1970: 1_788_052_801),
      normalizedValue: 70,
      destination: pairing.destination
    )
    let checkpointStore = InMemoryPairingCheckpointStore()
    try await checkpointStore.commit(
      PairingCheckpoint(
        pairingID: pairing.id,
        entityID: pairing.entityID,
        homeAssistantUpdatedAt: Date(timeIntervalSince1970: 1_788_052_801),
        normalizedValue: 70,
        destination: pairing.destination,
        syncIdentifier: identity.identifier,
        syncVersion: identity.version
      )
    )
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      pairingStore: store,
      pairingCheckpointStore: checkpointStore
    )
    await model.reloadPairings()

    await model.deletePairing(id: pairing.id)
    let checkpoint = try await checkpointStore.checkpoint(for: pairing.id)

    XCTAssertTrue(model.pairings.isEmpty)
    XCTAssertNil(checkpoint)
  }

  func testUVPresetAutoSelectsOnlyCandidateAndAuthorizesBeforeSaving() async throws {
    let events = PresetEventRecorder()
    let store = InMemoryPairingStore()
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-token", for: .accessToken)
    let lister = StubHomeAssistantStateLister(
      states: [makeUVState(entityID: "sensor.home_current_uv_index")],
      events: events
    )
    let writer = RecordingPairingHealthWriter(events: events)
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      homeAssistantStateLister: lister,
      pairingStore: store,
      healthSampleWriter: writer,
      initialConfiguration: configuration
    )

    let result = await model.setUVExposureImportEnabled(true)

    XCTAssertEqual(result, .enabled)
    XCTAssertTrue(model.uvExposureImportEnabled)
    let pairing = try XCTUnwrap(model.pairings.first)
    XCTAssertEqual(pairing.entityID, "sensor.home_current_uv_index")
    XCTAssertEqual(pairing.destination, .uvExposure)
    XCTAssertEqual(pairing.sourceUnit, .unitless)
    XCTAssertEqual(pairing.destinationUnit, .unitless)
    XCTAssertEqual(pairing.transformation, .identity)
    let recordedEvents = await events.values()
    XCTAssertEqual(recordedEvents, ["discover", "authorize"])
  }

  func testUVPresetRequiresSelectionWhenSeveralBestCandidatesExist() async throws {
    let store = InMemoryPairingStore()
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-token", for: .accessToken)
    let writer = RecordingPairingHealthWriter()
    let lister = StubHomeAssistantStateLister(states: [
      makeUVState(entityID: "sensor.garden_current_uv_index", name: "Garden UV Index"),
      makeUVState(entityID: "sensor.patio_current_uv_index", name: "Patio UV Index"),
    ])
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      homeAssistantStateLister: lister,
      pairingStore: store,
      healthSampleWriter: writer,
      initialConfiguration: configuration
    )

    let discoveryResult = await model.setUVExposureImportEnabled(true)

    guard case .selectionRequired(let candidates) = discoveryResult else {
      return XCTFail("Expected a UV sensor selection")
    }
    XCTAssertEqual(
      candidates.map(\.entityID),
      [
        "sensor.garden_current_uv_index", "sensor.patio_current_uv_index",
      ])
    XCTAssertTrue(model.pairings.isEmpty)
    let requestsBeforeSelection = await writer.authorizationRequests()
    XCTAssertTrue(requestsBeforeSelection.isEmpty)

    let selectionResult = await model.setUVExposureImportEnabled(
      true,
      selectedEntityID: "sensor.patio_current_uv_index"
    )

    XCTAssertEqual(selectionResult, .enabled)
    XCTAssertEqual(model.pairings.first?.entityID, "sensor.patio_current_uv_index")
    let requestsAfterSelection = await writer.authorizationRequests()
    XCTAssertEqual(requestsAfterSelection, [[.uvExposure]])
  }

  func testUVPresetDoesNotSaveWhenAuthorizationFails() async throws {
    let store = InMemoryPairingStore()
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-token", for: .accessToken)
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      homeAssistantStateLister: StubHomeAssistantStateLister(
        states: [makeUVState(entityID: "sensor.home_current_uv_index")]
      ),
      pairingStore: store,
      healthSampleWriter: RecordingPairingHealthWriter(authorizationError: TestWriterError.denied),
      initialConfiguration: configuration
    )

    let result = await model.setUVExposureImportEnabled(true)

    XCTAssertEqual(result, .failed(.healthKit))
    XCTAssertEqual(model.currentError, .healthKit)
    let storedPairings = try await store.all()
    XCTAssertTrue(storedPairings.isEmpty)
  }

  func testUVPresetDisablePreservesPairingAndReenableUsesExistingSource() async throws {
    let original = Pairing(
      entityID: "sensor.home_current_uv_index",
      destination: .uvExposure,
      sourceUnit: .unitless,
      destinationUnit: .unitless,
      transformation: .identity,
      isEnabled: true
    )
    let store = try InMemoryPairingStore(pairings: [original])
    let writer = RecordingPairingHealthWriter()
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      pairingStore: store,
      healthSampleWriter: writer
    )
    await model.reloadPairings()

    let disableResult = await model.setUVExposureImportEnabled(false)

    XCTAssertEqual(disableResult, .disabled)
    XCTAssertFalse(model.uvExposureImportEnabled)
    XCTAssertEqual(model.pairings.first?.id, original.id)
    XCTAssertEqual(model.pairings.first?.isEnabled, false)

    let enableResult = await model.setUVExposureImportEnabled(true)

    XCTAssertEqual(enableResult, .enabled)
    XCTAssertTrue(model.uvExposureImportEnabled)
    XCTAssertEqual(model.pairings.first?.entityID, original.entityID)
  }

  func testUVPresetReportsNoCompatibleSensor() async throws {
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-token", for: .accessToken)
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      homeAssistantStateLister: StubHomeAssistantStateLister(states: []),
      pairingStore: InMemoryPairingStore(),
      healthSampleWriter: RecordingPairingHealthWriter(),
      initialConfiguration: configuration
    )

    let result = await model.setUVExposureImportEnabled(true)

    XCTAssertEqual(result, .noCandidates)
    XCTAssertFalse(model.uvExposureImportEnabled)
  }

  private func makePairing() -> Pairing {
    Pairing(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
      entityID: "sensor.body_mass",
      destination: .bodyMass,
      sourceUnit: .kilograms,
      destinationUnit: .kilograms,
      transformation: .identity,
      isEnabled: true
    )
  }

  private func makeUVState(
    entityID: String,
    name: String = "Current UV Index"
  ) -> HomeAssistantState {
    let date = Date(timeIntervalSince1970: 1_788_052_800)
    return HomeAssistantState(
      entityID: entityID,
      state: "4.2",
      lastChanged: date,
      lastUpdated: date,
      attributes: .init(unitOfMeasurement: nil, friendlyName: name)
    )
  }
}

private actor RecordingPairingHealthWriter: HealthSampleWriting {
  private var requests: [Set<HealthObjectTypeID>] = []
  private let events: PresetEventRecorder?
  private let authorizationError: (any Error)?

  init(
    events: PresetEventRecorder? = nil,
    authorizationError: (any Error)? = nil
  ) {
    self.events = events
    self.authorizationError = authorizationError
  }

  func requestWriteAuthorization(for destinations: Set<HealthObjectTypeID>) async throws {
    await events?.append("authorize")
    requests.append(destinations)
    if let authorizationError { throw authorizationError }
  }

  func save(_ sample: HealthSampleWrite) {}

  func authorizationRequests() -> [Set<HealthObjectTypeID>] {
    requests
  }
}

private actor StubHomeAssistantStateLister: HomeAssistantStateListing {
  let states: [HomeAssistantState]
  let events: PresetEventRecorder?

  init(states: [HomeAssistantState], events: PresetEventRecorder? = nil) {
    self.states = states
    self.events = events
  }

  func fetchStates(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) async throws -> [HomeAssistantState] {
    await events?.append("discover")
    return states
  }
}

private actor PresetEventRecorder {
  private var recordedValues: [String] = []

  func append(_ value: String) {
    recordedValues.append(value)
  }

  func values() -> [String] {
    recordedValues
  }
}

private enum TestWriterError: Error {
  case denied
}
