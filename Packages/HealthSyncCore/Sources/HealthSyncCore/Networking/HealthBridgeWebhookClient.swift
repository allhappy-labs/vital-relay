import Foundation

public enum HealthBridgeClientError: Error, Equatable, Sendable {
  case invalidRequest
}

public protocol WebhookConnectionTesting: Sendable {
  func testWebhook(
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> WebhookConnectionAcknowledgement
}

public struct HealthBridgeWebhookClient: Sendable {
  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport) {
    self.transport = transport
  }

  public func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement {
    try await send(
      reading: reading,
      baseURL: baseURL,
      webhookSecret: webhookSecret,
      userID: userID,
      requestID: requestID,
      timeout: ExecutionDeadline.defaultRequestTimeout
    )
  }

  public func send(
    reading: MetricReading,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    let request = LiveRequest(
      token: webhookSecret,
      userID: userID,
      requestID: requestID,
      data: [
        reading.metricID.rawValue: [
          HealthBridgeDataPoint(
            timestamp: reading.timestamp,
            value: .number(reading.value)
          )
        ]
      ]
    )
    let data = try await perform(request, baseURL: baseURL, timeout: timeout)
    let acknowledgement: LiveAcknowledgement = try decode(data)
    do {
      try acknowledgement.validate(requestID: requestID)
    } catch {
      throw NetworkFailure.protocolMismatch
    }
    return acknowledgement
  }

  public func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement {
    try await send(
      workout: workout,
      baseURL: baseURL,
      webhookSecret: webhookSecret,
      userID: userID,
      requestID: requestID,
      timeout: ExecutionDeadline.defaultRequestTimeout
    )
  }

  public func send(
    workout: WorkoutPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    let request = LiveRequest(
      token: webhookSecret,
      userID: userID,
      requestID: requestID,
      specialMetric: .lastAppleWorkout,
      value: workout.liveValue
    )
    let data = try await perform(request, baseURL: baseURL, timeout: timeout)
    let acknowledgement: LiveAcknowledgement = try decode(data)
    do {
      try acknowledgement.validate(requestID: requestID)
    } catch {
      throw NetworkFailure.protocolMismatch
    }
    return acknowledgement
  }

  public func send(
    batch: [LiveBatchEntry],
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    let request = LiveRequest(
      token: webhookSecret,
      userID: userID,
      requestID: requestID,
      entries: batch
    )
    let data = try await perform(request, baseURL: baseURL, timeout: timeout)
    return try decode(data)
  }

  public func testWebhook(
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> WebhookConnectionAcknowledgement {
    let request = LiveRequest(
      token: webhookSecret,
      userID: userID,
      requestID: requestID,
      data: [
        "test_connection": [
          HealthBridgeDataPoint(value: .boolean(true))
        ]
      ]
    )
    let data = try await perform(
      request, baseURL: baseURL, timeout: ExecutionDeadline.defaultRequestTimeout)
    let acknowledgement: WebhookConnectionAcknowledgement = try decode(data)
    do {
      try acknowledgement.validate()
    } catch {
      throw NetworkFailure.protocolMismatch
    }
    return acknowledgement
  }

  public func send(
    medications: MedicationPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement {
    try await send(
      medications: medications,
      baseURL: baseURL,
      webhookSecret: webhookSecret,
      userID: userID,
      requestID: requestID,
      timeout: ExecutionDeadline.defaultRequestTimeout
    )
  }

  public func send(
    medications: MedicationPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    let request = LiveRequest(
      token: webhookSecret,
      userID: userID,
      requestID: requestID,
      medications: medications
    )
    let data = try await perform(request, baseURL: baseURL, timeout: timeout)
    let acknowledgement: LiveAcknowledgement = try decode(data)
    do {
      try acknowledgement.validateMedications(
        requestID: requestID,
        medicationCount: medications.records.count
      )
    } catch {
      throw NetworkFailure.protocolMismatch
    }
    return acknowledgement
  }

  private func perform(
    _ payload: LiveRequest,
    baseURL: NormalizedBaseURL,
    timeout: TimeInterval
  ) async throws -> Data {
    guard !payload.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      RequestIDGenerator.isValid(payload.requestID),
      !payload.data.isEmpty
    else {
      throw HealthBridgeClientError.invalidRequest
    }

    var request = URLRequest(url: baseURL.healthBridgeWebhookURL)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(ISO8601DateFormatter().string(from: date))
    }
    do {
      request.httpBody = try encoder.encode(payload)
    } catch {
      throw HealthBridgeClientError.invalidRequest
    }

    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.data(for: request)
    } catch let failure as NetworkFailure {
      throw failure
    } catch {
      throw NetworkFailure.classify(error)
    }

    guard (200...299).contains(response.statusCode) else {
      throw NetworkFailure.classify(
        statusCode: response.statusCode,
        headers: Self.stringHeaders(response)
      )
    }
    return data
  }

  private func decode<Value: Decodable>(_ data: Data) throws -> Value {
    do {
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      throw NetworkFailure.malformedResponse
    }
  }

  private static func stringHeaders(_ response: HTTPURLResponse) -> [String: String] {
    response.allHeaderFields.reduce(into: [:]) { result, entry in
      guard let key = entry.key as? String, let value = entry.value as? String else {
        return
      }
      result[key] = value
    }
  }
}

extension HealthBridgeWebhookClient: WebhookConnectionTesting {}
extension HealthBridgeWebhookClient: MedicationHealthBridgeSending {}
