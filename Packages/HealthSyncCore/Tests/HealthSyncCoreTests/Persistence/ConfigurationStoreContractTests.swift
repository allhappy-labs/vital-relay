import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Configuration store contract")
struct ConfigurationStoreContractTests {
  private let configuration = AppConfiguration(
    baseURL: "https://ha.example.com",
    allowsConfirmedLocalHTTP: false,
    healthBridgeUserID: "oleh_1",
    selectedMetrics: [.steps, .bodyMass],
    backgroundSyncEnabled: true
  )

  @Test("Missing configuration returns local defaults")
  func missingConfigurationReturnsDefaults() async throws {
    let store = InMemoryConfigurationStore()

    #expect(try await store.load() == .default)
  }

  @Test("Configuration round-trips in a versioned envelope")
  func versionedRoundTrip() throws {
    let data = try ConfigurationCodec.encode(configuration)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["version"] as? Int == 1)
    #expect(json["configuration"] != nil)
    #expect(json["webhookSecret"] == nil)
    #expect(json["accessToken"] == nil)
    #expect(try ConfigurationCodec.decode(data) == configuration)
  }

  @Test("Existing configuration documents default new experimental settings off")
  func existingDocumentDefaultsExperimentalSettingsOff() throws {
    let data = Data(
      #"{"version":1,"configuration":{"baseURL":"https://ha.example.com","allowsConfirmedLocalHTTP":false,"healthBridgeUserID":"oleh_1","selectedMetrics":["steps"],"backgroundSyncEnabled":true}}"#
        .utf8
    )

    let decoded = try ConfigurationCodec.decode(data)

    #expect(decoded.experimentalBackfillEnabled == false)
    #expect(decoded.medicationSyncEnabled == false)
    #expect(decoded.backgroundSyncFrequency == .balanced)
  }

  @Test("Every background frequency round-trips")
  func backgroundFrequencyRoundTrip() throws {
    for frequency in BackgroundSyncFrequency.allCases {
      var candidate = configuration
      candidate.backgroundSyncFrequency = frequency

      let data = try ConfigurationCodec.encode(candidate)

      #expect(try ConfigurationCodec.decode(data) == candidate)
    }
  }

  @Test("Unsupported and corrupted data fail closed")
  func invalidDataFailsClosed() throws {
    let unsupportedVersion = Data(
      #"{"version":2,"configuration":{}}"#.utf8
    )

    #expect(throws: ConfigurationStoreError.unsupportedVersion) {
      try ConfigurationCodec.decode(unsupportedVersion)
    }
    #expect(throws: ConfigurationStoreError.corruptedData) {
      try ConfigurationCodec.decode(Data("not-json".utf8))
    }
  }

  @Test(
    arguments: [
      "oleh",
      "Oleh_2026",
      "user-name",
      "a",
      String(repeating: "a", count: 64),
    ]
  )
  func acceptsValidUserIDs(userID: String) throws {
    var candidate = configuration
    candidate.healthBridgeUserID = userID

    try candidate.validate()
  }

  @Test(
    arguments: [
      "",
      "_oleh",
      "-oleh",
      "oleh space",
      "oleh@example.com",
      String(repeating: "a", count: 65),
    ]
  )
  func rejectsInvalidUserIDs(userID: String) {
    var candidate = configuration
    candidate.healthBridgeUserID = userID

    #expect(throws: ConfigurationStoreError.invalidUserID) {
      try candidate.validate()
    }
  }

  @Test("In-memory writes replace the complete configuration")
  func writesReplaceAtomically() async throws {
    let store = InMemoryConfigurationStore()
    try await store.save(configuration)

    var replacement = configuration
    replacement.baseURL = "https://second.example.com"
    replacement.selectedMetrics = [.restingHeartRate]
    try await store.save(replacement)

    #expect(try await store.load() == replacement)
  }
}
