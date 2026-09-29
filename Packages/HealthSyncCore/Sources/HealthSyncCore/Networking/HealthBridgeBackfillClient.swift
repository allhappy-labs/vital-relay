import Foundation

public enum BackfillClientError: Error, Sendable, Equatable {
  case invalidRequest
  case invalidBackfill
  case entityNotReady
  case unsupportedRecorder
  case recorderUnavailable
  case commitFailed
}

public protocol HealthBridgeBackfillSending: Sendable {
  func send(
    _ request: BackfillRequest,
    baseURL: NormalizedBaseURL
  ) async throws -> BackfillAcknowledgement
}

public struct HealthBridgeBackfillClient: HealthBridgeBackfillSending, Sendable {
  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport) {
    self.transport = transport
  }

  public func send(
    _ payload: BackfillRequest,
    baseURL: NormalizedBaseURL
  ) async throws -> BackfillAcknowledgement {
    var request = URLRequest(url: baseURL.healthBridgeWebhookURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 50
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      request.httpBody = try encoder.encode(payload)
    } catch {
      throw BackfillClientError.invalidRequest
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
      if let mapped = Self.backfillError(data: data, statusCode: response.statusCode) {
        throw mapped
      }
      throw NetworkFailure.classify(statusCode: response.statusCode)
    }

    let acknowledgement: BackfillAcknowledgement
    do {
      acknowledgement = try JSONDecoder().decode(BackfillAcknowledgement.self, from: data)
      try acknowledgement.validate(requestID: payload.requestID)
    } catch let error as BackfillAcknowledgementValidationError {
      if error == .unsupportedRecorder { throw BackfillClientError.unsupportedRecorder }
      throw NetworkFailure.protocolMismatch
    } catch let failure as NetworkFailure {
      throw failure
    } catch {
      throw NetworkFailure.malformedResponse
    }
    return acknowledgement
  }

  private static func backfillError(data: Data, statusCode: Int) -> BackfillClientError? {
    guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
      body.ok == false, body.committed == false, body.protocolVersion == 1
    else { return nil }
    return switch (statusCode, body.error) {
    case (422, "invalid_backfill"): .invalidBackfill
    case (503, "entity_not_ready"): .entityNotReady
    case (409, "unsupported_recorder"): .unsupportedRecorder
    case (503, "recorder_unavailable"): .recorderUnavailable
    case (500, "backfill_commit_failed"): .commitFailed
    default: nil
    }
  }

  private struct ErrorBody: Decodable {
    let ok: Bool
    let committed: Bool
    let protocolVersion: Int
    let error: String

    enum CodingKeys: String, CodingKey {
      case ok
      case committed
      case protocolVersion = "protocol_version"
      case error
    }
  }
}
