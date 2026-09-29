import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Home Assistant state client")
struct HomeAssistantStateClientTests {
  private let baseURL = try! NormalizedBaseURL.parse(
    "https://ha.example.com/prefix",
    allowConfirmedLocalHTTP: false
  )

  @Test("Fetches one encoded state with bearer authentication")
  func fetchesState() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "ha-state-valid"))
    let client = HomeAssistantClient(transport: transport)

    let state = try await client.fetchState(
      entityID: "sensor.body_mass",
      baseURL: baseURL,
      accessToken: "fixture-access-token"
    )

    #expect(state.entityID == "sensor.body_mass")
    #expect(state.attributes.unitOfMeasurement == "lb")
    #expect(state.lastChanged < state.lastUpdated)
    let requests = await transport.requests()
    let request = try #require(requests.first)
    let expectedURL = try baseURL.stateURL(entityID: "sensor.body_mass")
    #expect(request.url == expectedURL)
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
    #expect(request.httpBody == nil)
  }

  @Test("Decodes unavailable as wire state for validation by the parser")
  func decodesUnavailableWireState() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "ha-state-unavailable"))
    let client = HomeAssistantClient(transport: transport)

    let state = try await client.fetchState(
      entityID: "sensor.body_mass",
      baseURL: baseURL,
      accessToken: "fixture-access-token"
    )

    #expect(state.state == "unavailable")
  }

  @Test("Lists Home Assistant states for entity discovery")
  func listsStates() async throws {
    let response = Data(
      #"[{"entity_id":"sensor.current_uv_index","state":"4.2","attributes":{"friendly_name":"Current UV Index"},"last_changed":"2026-08-28T12:00:00Z","last_updated":"2026-08-28T12:00:01Z"}]"#
        .utf8
    )
    let transport = StubHTTPTransport(responseData: response)
    let client = HomeAssistantClient(transport: transport)

    let states = try await client.fetchStates(
      baseURL: baseURL,
      accessToken: "fixture-access-token"
    )

    #expect(states.map(\.entityID) == ["sensor.current_uv_index"])
    #expect(states.first?.attributes.friendlyName == "Current UV Index")
    let request = try #require(await transport.requests().first)
    #expect(request.url == baseURL.statesURL)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
  }

  @Test(
    "Classifies authenticated state failures",
    arguments: [
      (401, NetworkFailure.unauthorized),
      (403, .forbidden),
      (404, .notFound),
      (422, .validation),
      (429, .rateLimited(retryAfter: nil)),
      (500, .server(statusCode: 500)),
    ]
  )
  func classifiesFailures(status: Int, expected: NetworkFailure) async throws {
    let transport = StubHTTPTransport(responseData: Data(), statusCode: status)
    let client = HomeAssistantClient(transport: transport)

    await #expect(throws: expected) {
      try await client.fetchState(
        entityID: "sensor.body_mass",
        baseURL: baseURL,
        accessToken: "fixture-access-token"
      )
    }
  }

  @Test("Rejects malformed timestamps and blank bearer credentials")
  func rejectsMalformedResponseAndCredential() async throws {
    let malformed = Data(
      #"{"entity_id":"sensor.x","state":"1","attributes":{"unit_of_measurement":"kg"},"last_changed":"bad","last_updated":"bad"}"#
        .utf8
    )
    let transport = StubHTTPTransport(responseData: malformed)
    let client = HomeAssistantClient(transport: transport)

    await #expect(throws: NetworkFailure.malformedResponse) {
      try await client.fetchState(
        entityID: "sensor.x",
        baseURL: baseURL,
        accessToken: "fixture-access-token"
      )
    }
    await #expect(throws: CredentialStoreError.blankValue) {
      try await client.fetchState(entityID: "sensor.x", baseURL: baseURL, accessToken: " ")
    }
    await #expect(throws: CredentialStoreError.blankValue) {
      try await client.fetchStates(baseURL: baseURL, accessToken: " ")
    }
  }

  @Test("State fetch honours the requested timeout")
  func fetchTimeout() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "ha-state-valid"))
    let client = HomeAssistantClient(transport: transport)
    let baseURL = try NormalizedBaseURL.parse(
      "https://ha.example.com", allowConfirmedLocalHTTP: false)

    _ = try await client.fetchState(
      entityID: "sensor.body_mass",
      baseURL: baseURL,
      accessToken: "fixture-access-token",
      timeout: 7
    )

    let request = try #require(await transport.requests().first)
    #expect(request.timeoutInterval == 7)
  }
}
