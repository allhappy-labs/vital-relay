import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Authenticated Home Assistant client")
struct HomeAssistantClientTests {
  private let baseURL = try! NormalizedBaseURL.parse(
    "https://ha.example.com/prefix",
    allowConfirmedLocalHTTP: false
  )

  @Test("Uses a bearer token only for the authenticated API")
  func bearerAuthentication() async throws {
    let response = Data(#"{"message":"API running."}"#.utf8)
    let transport = StubHTTPTransport(responseData: response)
    let client = HomeAssistantClient(transport: transport)

    let status = try await client.testAuthenticatedAPI(
      baseURL: baseURL,
      accessToken: "fixture-access-token"
    )

    #expect(status.message == "API running.")
    let requests = await transport.requests()
    let request = try #require(requests.count == 1 ? requests[0] : nil)
    #expect(request.httpMethod == "GET")
    #expect(request.url == baseURL.authenticatedAPIURL)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
    #expect(request.httpBody == nil)
    #expect(request.url?.absoluteString.contains("fixture") == false)
  }

  @Test(
    arguments: [
      (401, NetworkFailure.unauthorized),
      (403, .forbidden),
      (404, .notFound),
      (422, .validation),
      (429, .rateLimited(retryAfter: 12)),
      (503, .server(statusCode: 503)),
    ]
  )
  func classifiesFailedResponses(statusCode: Int, expected: NetworkFailure) async throws {
    let headers = statusCode == 429 ? ["Retry-After": "12"] : [:]
    let transport = StubHTTPTransport(
      responseData: Data(),
      statusCode: statusCode,
      headers: headers
    )
    let client = HomeAssistantClient(transport: transport)

    do {
      _ = try await client.testAuthenticatedAPI(
        baseURL: baseURL,
        accessToken: "fixture-access-token"
      )
      Issue.record("Expected request failure")
    } catch {
      #expect(error as? NetworkFailure == expected)
    }
  }

  @Test("Publishes a state with bearer auth, JSON body and timeout")
  func publishState() async throws {
    let transport = StubHTTPTransport(responseData: Data("{}".utf8), statusCode: 201)
    let client = HomeAssistantClient(transport: transport)

    try await client.publishState(
      entityID: "sensor.health_bridge_sync_attempt_oleh",
      state: "2026-09-14T10:00:00Z",
      attributes: ["outcome": .string("exported"), "exported_metrics": .number(3)],
      baseURL: baseURL,
      accessToken: "fixture-access-token",
      timeout: 5
    )

    let request = try #require(await transport.requests().first)
    #expect(request.httpMethod == "POST")
    #expect(
      request.url == (try baseURL.stateURL(entityID: "sensor.health_bridge_sync_attempt_oleh")))
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
    #expect(request.timeoutInterval == 5)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["state"] as? String == "2026-09-14T10:00:00Z")
    let attributes = try #require(json["attributes"] as? [String: Any])
    #expect(attributes["outcome"] as? String == "exported")
  }

  @Test("Non-admin tokens surface as forbidden")
  func publishForbidden() async throws {
    let transport = StubHTTPTransport(responseData: Data(), statusCode: 403)
    let client = HomeAssistantClient(transport: transport)

    await #expect(throws: NetworkFailure.forbidden) {
      try await client.publishState(
        entityID: "sensor.health_bridge_sync_attempt_oleh",
        state: "x",
        attributes: [:],
        baseURL: baseURL,
        accessToken: "fixture-access-token",
        timeout: 5
      )
    }
  }
}
