import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Archive client")
struct ArchiveClientTests {
  private let baseURL = try! NormalizedBaseURL.parse(
    "https://ha.example.invalid/prefix", allowConfirmedLocalHTTP: false)

  @Test("Capability uses webhook token in JSON and preserves proxy path")
  func capabilityRequest() async throws {
    let body = try responseFixture("archive-capability-v2")
    let transport = StubHTTPTransport(responseData: body)
    let client = client(transport)
    let response = try await client.probe(baseURL: baseURL, userID: "person-1", token: "secret")
    #expect(response.supportedSampleTypes.contains("HKWorkoutType"))
    let request = try #require(await transport.requests().first)
    #expect(
      request.url?.absoluteString == "https://ha.example.invalid/prefix/api/webhook/health_bridge")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    let bodyData = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    #expect(json["token"] as? String == "secret")
    #expect(json["uploader_credential"] as? String == String(repeating: "A", count: 43))
    #expect(json["request_type"] as? String == "archive_capability")
    #expect(json["protocol_version"] as? Int == 2)
  }

  @Test("Batch sends original JSON and validates durable receipt")
  func batchRequest() async throws {
    let transport = StubHTTPTransport(responseData: try fixtureData(named: "archive-ack-v2"))
    let batch = try JSONDecoder().decode(
      ArchiveBatch.self, from: fixtureData(named: "archive-batch-v2"))
    let ack = try await client(transport).send(batch, baseURL: baseURL)
    #expect(ack.archiveCommit == "committed")
    let request = try #require(await transport.requests().first)
    let bodyData = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    #expect(json["token"] as? String == "secret")
    #expect(json["uploader_credential"] as? String == String(repeating: "A", count: 43))
    #expect(json["batch_id"] as? String == "batch-001")
    #expect(json["expected_owner_generation"] == nil)
  }

  @Test("Status validates echoed ID")
  func statusRequest() async throws {
    let transport = StubHTTPTransport(responseData: try responseFixture("archive-status-v2"))
    let response = try await client(transport).status(
      requestID: "request-status-001", baseURL: baseURL)
    #expect(response.metrics.map(\.metric) == ["steps", "sleep_details"])
  }

  @Test("Owner claim carries proof and parses pending claim status")
  func ownerClaim() async throws {
    let body = try responseFixture("archive-owner-v2")
    let transport = StubHTTPTransport(responseData: body)
    let claim = try await client(transport, requestID: "request-owner-001").claimOwner(
      baseURL: baseURL)
    #expect(claim.ownerState == .pending)
    #expect(claim.fingerprint == "66687aadf862")
    #expect(client(transport).uploaderFingerprint == "66687aadf862")
    let request = try #require(await transport.requests().first)
    let requestBody = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let wrapped = try #require(
      JSONSerialization.jsonObject(with: fixtureData(named: "archive-owner-v2")) as? [String: Any])
    var expected = try #require(wrapped["request"] as? [String: Any])
    expected["token"] = "secret"
    #expect(json as NSDictionary == expected as NSDictionary)
  }

  @Test("Owner errors are typed and do not expose response bodies")
  func ownerErrors() async throws {
    for (status, code, expected) in [
      (403, "owner_required", ArchiveClientError.ownerRequired),
      (403, "owner_pending", .ownerPending),
      (409, "owner_pending", .ownerPending),
      (403, "owner_changed", .ownerChanged),
    ] {
      let body = Data("{\"ok\":false,\"error\":\"\(code)\",\"detail\":\"private\"}".utf8)
      let transport = StubHTTPTransport(responseData: body, statusCode: status)
      do {
        _ = try await client(transport).status(requestID: "request-status-001", baseURL: baseURL)
        Issue.record("Expected owner error")
      } catch {
        #expect(error as? ArchiveClientError == expected)
        #expect(!String(describing: error).contains("private"))
      }
    }
  }

  @Test("Final authenticated body enforces the byte ceiling")
  func finalBodySize() async throws {
    var json = try #require(
      JSONSerialization.jsonObject(with: fixtureData(named: "archive-batch-v2")) as? [String: Any])
    let template = try #require((json["samples"] as? [[String: Any]])?.first)
    var samples = (0..<200).map { index -> [String: Any] in
      var sample = template
      sample["uuid"] = String(format: "00000000-0000-0000-0000-%012x", index + 1)
      sample["metadata"] = [
        "a": String(repeating: "x", count: 255),
        "b": String(repeating: "x", count: 255),
        "c": String(repeating: "x", count: 255),
      ]
      return sample
    }
    var index = 0
    while index < samples.count {
      var metadata = samples[index]["metadata"] as! [String: String]
      metadata["d"] = String(repeating: "x", count: 255)
      samples[index]["metadata"] = metadata
      json["samples"] = samples
      if try JSONSerialization.data(withJSONObject: json).count >= ArchiveBatch.maximumBytes - 300 {
        break
      }
      index += 1
    }
    let targetIndex = min(index, samples.count - 1)
    var nearLimit: ArchiveBatch?
    for candidateIndex in targetIndex...min(targetIndex + 1, samples.count - 1) {
      for length in 0...255 {
        var metadata = samples[candidateIndex]["metadata"] as! [String: String]
        metadata["d"] = String(repeating: "x", count: length)
        samples[candidateIndex]["metadata"] = metadata
        json["samples"] = samples
        let data = try JSONSerialization.data(withJSONObject: json)
        guard data.count <= ArchiveBatch.maximumBytes else { break }
        let batch = try ArchiveBatch.decodeValidated(data)
        var body = try #require(
          JSONSerialization.jsonObject(with: JSONEncoder().encode(batch)) as? [String: Any])
        body["token"] = "secret"
        body["uploader_credential"] = String(repeating: "A", count: 43)
        let authenticatedSize = try JSONSerialization.data(withJSONObject: body).count
        if authenticatedSize > ArchiveBatch.maximumBytes {
          nearLimit = batch
          break
        }
      }
      if nearLimit != nil { break }
    }
    let batch = try #require(nearLimit)
    let transport = StubHTTPTransport(responseData: Data())
    await #expect(throws: ArchiveClientError.requestTooLarge) {
      _ = try await client(transport).send(batch, baseURL: baseURL)
    }
    #expect(await transport.requests().isEmpty)
  }

  @Test("Rejects noncanonical uploader proof before sending")
  func invalidUploaderProof() async throws {
    let transport = StubHTTPTransport(responseData: Data())
    let client = HealthBridgeArchiveClient(
      transport: transport, userID: "person-1", token: "secret",
      uploaderCredential: String(repeating: "A", count: 42) + "B")
    #expect(client.uploaderFingerprint == nil)
    await #expect(throws: ArchiveClientError.invalidRequest) {
      _ = try await client.status(requestID: "request-status-001", baseURL: baseURL)
    }
    #expect(await transport.requests().isEmpty)
  }

  @Test("HTTP statuses retain retry classification")
  func retryClassification() async throws {
    let cases: [(Int, [String: String], NetworkFailure)] = [
      (401, [:], .unauthorized), (422, [:], .validation),
      (429, ["Retry-After": "12"], .rateLimited(retryAfter: 12)),
      (503, [:], .server(statusCode: 503)),
    ]
    for (code, headers, expected) in cases {
      let transport = StubHTTPTransport(responseData: Data(), statusCode: code, headers: headers)
      do {
        _ = try await client(transport).status(requestID: "request-status-001", baseURL: baseURL)
        Issue.record("Expected HTTP failure")
      } catch {
        #expect(error as? NetworkFailure == expected)
      }
    }
  }

  @Test("Lost acknowledgement remains retryable with same batch identity")
  func lostAcknowledgement() async throws {
    let transport = FailingArchiveTransport()
    let batch = try JSONDecoder().decode(
      ArchiveBatch.self, from: fixtureData(named: "archive-batch-v2"))
    do {
      _ = try await client(transport).send(batch, baseURL: baseURL)
      Issue.record("Expected lost connection")
    } catch {
      #expect(error as? NetworkFailure == .connectionLost)
    }
    let request = try #require(await transport.request())
    let bodyData = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    #expect(json["batch_id"] as? String == "batch-001")
    #expect(json["request_id"] as? String == "request-batch-001")
  }

  @Test("Rejects oversized, malformed and mismatched success responses")
  func invalidResponse() async throws {
    let bodies = [
      Data(repeating: 120, count: 262_145), Data("not json".utf8),
      Data("{\"ok\":true}".utf8),
    ]
    for body in bodies {
      let transport = StubHTTPTransport(responseData: body)
      await #expect(throws: (any Error).self) {
        _ = try await client(transport).status(requestID: "request-status-001", baseURL: baseURL)
      }
    }
  }

  private func client(
    _ transport: any HTTPTransport, requestID: String = "request-capability-001"
  ) -> HealthBridgeArchiveClient {
    HealthBridgeArchiveClient(
      transport: transport, userID: "person-1", token: "secret",
      uploaderCredential: String(repeating: "A", count: 43),
      requestIDGenerator: { requestID })
  }

  private func responseFixture(_ name: String) throws -> Data {
    let wrapped = try #require(
      JSONSerialization.jsonObject(with: fixtureData(named: name)) as? [String: Any])
    return try JSONSerialization.data(withJSONObject: wrapped["response"]!)
  }
}

private actor FailingArchiveTransport: HTTPTransport {
  private var captured: URLRequest?

  func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
    captured = request
    throw URLError(.networkConnectionLost)
  }

  func request() -> URLRequest? { captured }
}
