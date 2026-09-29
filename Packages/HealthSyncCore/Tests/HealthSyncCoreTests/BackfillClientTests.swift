import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Health Bridge backfill client")
struct BackfillClientTests {
  private let baseURL = try! NormalizedBaseURL.parse(
    "https://ha.example.invalid",
    allowConfirmedLocalHTTP: false
  )

  @Test("Uses only the webhook JSON secret and validates committed acknowledgement")
  func committedRequest() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "backfill-success"))
    let acknowledgement = try await HealthBridgeBackfillClient(transport: transport).send(
      try request(),
      baseURL: baseURL
    )

    #expect(acknowledgement.committed)
    let recorded = try #require(await transport.requests().first)
    #expect(recorded.url == baseURL.healthBridgeWebhookURL)
    #expect(recorded.httpMethod == "POST")
    #expect(recorded.value(forHTTPHeaderField: "Authorization") == nil)
    let body = try #require(recorded.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["token"] as? String == "fixture-secret")
    #expect(json["request_type"] as? String == "backfill")
  }

  @Test("Maps stable backfill errors precisely")
  func stableErrors() async throws {
    let cases: [(Int, String, BackfillClientError)] = [
      (422, "invalid_backfill", .invalidBackfill),
      (503, "entity_not_ready", .entityNotReady),
      (409, "unsupported_recorder", .unsupportedRecorder),
      (503, "recorder_unavailable", .recorderUnavailable),
      (500, "backfill_commit_failed", .commitFailed),
    ]
    for (status, code, expected) in cases {
      let body: [String: Any] = [
        "ok": false,
        "committed": false,
        "protocol_version": 1,
        "error": code,
        "message": "fixture message",
      ]
      let transport = StubHTTPTransport(
        responseData: try JSONSerialization.data(withJSONObject: body),
        statusCode: status
      )
      do {
        _ = try await HealthBridgeBackfillClient(transport: transport).send(
          try request(),
          baseURL: baseURL
        )
        Issue.record("Expected backfill failure")
      } catch {
        #expect(error as? BackfillClientError == expected)
      }
    }
  }

  @Test("Rejects malformed mismatched and incompatible success responses")
  func invalidAcknowledgements() async throws {
    let success = try fixtureData(named: "backfill-success")
    let cases: [(String, Any)] = [
      ("request_id", "backfill.different"),
      ("committed", false),
      ("database", "postgresql"),
      ("recorder_schema", 54),
      ("statistics_policy", "statistics"),
      ("inserted", 1),
    ]
    for (key, value) in cases {
      var json = try #require(JSONSerialization.jsonObject(with: success) as? [String: Any])
      json[key] = value
      let transport = StubHTTPTransport(
        responseData: try JSONSerialization.data(withJSONObject: json)
      )
      do {
        _ = try await HealthBridgeBackfillClient(transport: transport).send(
          try request(),
          baseURL: baseURL
        )
        Issue.record("Expected acknowledgement failure for \(key)")
      } catch {
        if key == "database" || key == "recorder_schema" {
          #expect(error as? BackfillClientError == .unsupportedRecorder)
        } else {
          #expect(error as? NetworkFailure == .protocolMismatch)
        }
      }
    }
  }

  private func request() throws -> BackfillRequest {
    let now = Date(timeIntervalSince1970: 1_788_052_900)
    return try BackfillRequest(
      token: "fixture-secret",
      userID: "fixture-user",
      requestID: "backfill.01234567",
      series: [
        BackfillSeries(
          metricID: .steps,
          points: [
            .init(timestamp: now.addingTimeInterval(-100), value: 7_000),
            .init(timestamp: now, value: 8_421),
          ]
        )
      ],
      now: now
    )
  }
}
