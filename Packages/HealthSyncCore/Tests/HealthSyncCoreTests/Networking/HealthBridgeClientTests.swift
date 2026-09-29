import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Health Bridge webhook client")
struct HealthBridgeClientTests {
  private let baseURL = try! NormalizedBaseURL.parse(
    "https://ha.example.com",
    allowConfirmedLocalHTTP: false
  )
  private let requestID = "live.01234567-89ab-cdef-0123-456789abcdef"

  @Test("Encodes the explicit live protocol and validates its acknowledgement")
  func liveRequestAndAcknowledgement() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "live-success"))
    let client = HealthBridgeWebhookClient(transport: transport)
    let timestamp = try #require(ISO8601DateFormatter().date(from: "2026-08-27T20:00:00Z"))

    let acknowledgement = try await client.send(
      reading: MetricReading(metricID: .steps, timestamp: timestamp, value: 8_421),
      baseURL: baseURL,
      webhookSecret: "fixture-webhook-secret",
      userID: "oleh",
      requestID: requestID
    )

    #expect(acknowledgement.receivedEntities == 1)
    #expect(acknowledgement.updatedEntities == 1)
    #expect(acknowledgement.skippedEntities == 0)

    let request = try #require(await transport.requests().only)
    #expect(request.httpMethod == "POST")
    #expect(request.url == baseURL.healthBridgeWebhookURL)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["token"] as? String == "fixture-webhook-secret")
    #expect(json["user_id"] as? String == "oleh")
    #expect(json["request_type"] as? String == "live")
    #expect(json["protocol_version"] as? Int == 1)
    #expect(json["request_id"] as? String == requestID)

    let data = try #require(json["data"] as? [String: Any])
    #expect(Set(data.keys) == ["steps"])
    let points = try #require(data["steps"] as? [[String: Any]])
    let point = try #require(points.only)
    #expect(point["timestamp"] as? String == "2026-08-27T20:00:00Z")
    #expect(point["value"] as? Double == 8_421)
  }

  @Test("HTTP 200 with no applied entity is a protocol failure")
  func noEntityAcknowledgementFails() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "live-no-entities"))
    let client = HealthBridgeWebhookClient(transport: transport)

    await #expect(throws: NetworkFailure.protocolMismatch) {
      try await client.send(
        reading: MetricReading(metricID: .steps, timestamp: .now, value: 1),
        baseURL: baseURL,
        webhookSecret: "fixture-webhook-secret",
        userID: "oleh",
        requestID: requestID
      )
    }
  }

  @Test("Sends a workout without wrapping it as a timestamp datapoint")
  func workoutRequest() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "live-success"))
    let client = HealthBridgeWebhookClient(transport: transport)
    let payload = WorkoutPayload(fields: ["workout_type": .string("Running")])

    _ = try await client.send(
      workout: payload,
      baseURL: baseURL,
      webhookSecret: "fixture-webhook-secret",
      userID: "oleh",
      requestID: requestID
    )

    let request = try #require(await transport.requests().only)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(json["data"] as? [String: Any])
    let workouts = try #require(data["last_apple_workout"] as? [[String: Any]])
    #expect(workouts.only?["workout_type"] as? String == "Running")
    #expect(workouts.only?["timestamp"] == nil)
    #expect(workouts.only?["value"] == nil)
  }

  @Test("HTTP 200 with a mismatched request ID is a protocol failure")
  func requestIDMismatchFails() async throws {
    let fixture = try fixtureData(named: "live-success")
    var json = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
    json["request_id"] = "live.different"
    let transport = StubHTTPTransport(
      responseData: try JSONSerialization.data(withJSONObject: json))
    let client = HealthBridgeWebhookClient(transport: transport)

    await #expect(throws: NetworkFailure.protocolMismatch) {
      try await client.send(
        reading: MetricReading(metricID: .steps, timestamp: .now, value: 1),
        baseURL: baseURL,
        webhookSecret: "fixture-webhook-secret",
        userID: "oleh",
        requestID: requestID
      )
    }
  }

  @Test("Sends a batch in one request with the requested timeout")
  func batchRequest() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "live-success"))
    let client = HealthBridgeWebhookClient(transport: transport)
    let timestamp = try #require(ISO8601DateFormatter().date(from: "2026-08-27T20:00:00Z"))

    _ = try await client.send(
      batch: [
        .reading(MetricReading(metricID: .steps, timestamp: timestamp, value: 8_421)),
        .reading(MetricReading(metricID: .bodyMass, timestamp: timestamp, value: 80)),
      ],
      baseURL: baseURL,
      webhookSecret: "fixture-webhook-secret",
      userID: "oleh",
      requestID: requestID,
      timeout: 7
    )

    let request = try #require(await transport.requests().only)
    #expect(request.timeoutInterval == 7)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(json["data"] as? [String: Any])
    #expect(Set(data.keys) == [MetricID.steps.rawValue, MetricID.bodyMass.rawValue])
    #expect(json["request_id"] as? String == requestID)
  }

  @Test("Medication requests require every dictionary to be acknowledged")
  func medicationAcknowledgement() async throws {
    let firstID = MedicationIdentifier.make(from: Data("first".utf8))
    let secondID = MedicationIdentifier.make(from: Data("second".utf8))
    let payload = try MedicationPayload.aggregate(
      concepts: [
        MedicationConcept(id: firstID, name: "First"),
        MedicationConcept(id: secondID, name: "Second"),
      ],
      doses: []
    )
    let success = try replacing(
      "updated_entities",
      with: 2,
      in: fixtureData(named: "live-success")
    )
    let transport = StubHTTPTransport(responseData: success)
    let client = HealthBridgeWebhookClient(transport: transport)

    _ = try await client.send(
      medications: payload,
      baseURL: baseURL,
      webhookSecret: "fixture-webhook-secret",
      userID: "oleh",
      requestID: requestID
    )

    let request = try #require(await transport.requests().only)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(json["data"] as? [String: Any])
    #expect((data["medications"] as? [[String: Any]])?.count == 2)

    let mismatch = HealthBridgeWebhookClient(
      transport: StubHTTPTransport(responseData: try fixtureData(named: "live-success"))
    )
    await #expect(throws: NetworkFailure.protocolMismatch) {
      try await mismatch.send(
        medications: payload,
        baseURL: baseURL,
        webhookSecret: "fixture-webhook-secret",
        userID: "oleh",
        requestID: requestID
      )
    }
  }

  @Test("Every required live acknowledgement field is enforced")
  func enforcesEveryLiveAcknowledgementField() async throws {
    let fixture = try fixtureData(named: "live-success")
    let invalidAcknowledgements = try [
      replacing("ok", with: false, in: fixture),
      replacing("applied", with: false, in: fixture),
      replacing("request_type", with: "backfill", in: fixture),
      replacing("protocol_version", with: 2, in: fixture),
      replacing("received_entities", with: 2, in: fixture),
      replacing("updated_entities", with: 0, in: fixture),
      replacing("skipped_entities", with: 1, in: fixture),
    ]

    for responseData in invalidAcknowledgements {
      let transport = StubHTTPTransport(responseData: responseData)
      let client = HealthBridgeWebhookClient(transport: transport)
      do {
        _ = try await client.send(
          reading: MetricReading(metricID: .steps, timestamp: .now, value: 1),
          baseURL: baseURL,
          webhookSecret: "fixture-webhook-secret",
          userID: "oleh",
          requestID: requestID
        )
        Issue.record("Expected protocolMismatch")
      } catch {
        #expect(error as? NetworkFailure == .protocolMismatch)
      }
    }
  }

  @Test("Connection test uses its distinct success contract")
  func connectionTestContract() async throws {
    let transport = StubHTTPTransport(
      responseData: try fixtureData(named: "connection-test-success")
    )
    let client = HealthBridgeWebhookClient(transport: transport)

    let result = try await client.testWebhook(
      baseURL: baseURL,
      webhookSecret: "fixture-webhook-secret",
      userID: "oleh",
      requestID: "test.01234567"
    )

    #expect(result.integrationVersion == "1.2.1")
    let request = try #require(await transport.requests().only)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(json["data"] as? [String: Any])
    #expect(data["test_connection"] != nil)
    #expect(json["token"] as? String == "fixture-webhook-secret")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test("Connection test enforces its backfill capability fields")
  func invalidConnectionCapabilityFails() async throws {
    let fixture = try fixtureData(named: "connection-test-success")
    let invalidAcknowledgements = try [
      replacing("ok", with: false, in: fixture),
      replacing("backfill_protocol", with: 2, in: fixture),
      replacing("backfill_ack", with: "queued", in: fixture),
      replacing("statistics_policy", with: "unknown", in: fixture),
    ]

    for responseData in invalidAcknowledgements {
      let transport = StubHTTPTransport(responseData: responseData)
      let client = HealthBridgeWebhookClient(transport: transport)
      do {
        _ = try await client.testWebhook(
          baseURL: baseURL,
          webhookSecret: "fixture-webhook-secret",
          userID: "oleh",
          requestID: "test.01234567"
        )
        Issue.record("Expected protocolMismatch")
      } catch {
        #expect(error as? NetworkFailure == .protocolMismatch)
      }
    }
  }

  @Test("Webhook failures retain their distinct HTTP classifications")
  func webhookHTTPFailureClassification() async throws {
    let cases: [(Int, NetworkFailure)] = [
      (401, .unauthorized),
      (403, .forbidden),
      (404, .notFound),
      (422, .validation),
      (429, .rateLimited(retryAfter: nil)),
      (503, .server(statusCode: 503)),
    ]

    for (statusCode, expected) in cases {
      let transport = StubHTTPTransport(responseData: Data(), statusCode: statusCode)
      let client = HealthBridgeWebhookClient(transport: transport)
      do {
        _ = try await client.send(
          reading: MetricReading(metricID: .steps, timestamp: .now, value: 1),
          baseURL: baseURL,
          webhookSecret: "fixture-webhook-secret",
          userID: "oleh",
          requestID: requestID
        )
        Issue.record("Expected request failure")
      } catch {
        #expect(error as? NetworkFailure == expected)
      }
    }
  }

  private func replacing(
    _ key: String,
    with value: Any,
    in fixture: Data
  ) throws -> Data {
    var json = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
    json[key] = value
    return try JSONSerialization.data(withJSONObject: json)
  }
}

extension Collection {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
