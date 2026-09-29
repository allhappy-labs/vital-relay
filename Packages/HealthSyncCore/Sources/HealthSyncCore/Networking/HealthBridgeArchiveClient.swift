import CryptoKit
import Foundation

public enum ArchiveClientError: Error, Sendable, Equatable {
  case invalidRequest
  case requestTooLarge
  case responseTooLarge
  case inventoryChanged
  case ownerRequired
  case ownerPending
  case ownerChanged
}

public protocol ArchiveCapabilityProbing: Sendable {
  func probe(baseURL: NormalizedBaseURL, userID: String, token: String) async throws
    -> ArchiveCapability
}

public protocol ArchiveBatchSending: Sendable {
  func send(_ batch: ArchiveBatch, baseURL: NormalizedBaseURL) async throws
    -> ArchiveAcknowledgement
}

public protocol ArchiveStatusFetching: Sendable {
  func status(requestID: String, baseURL: NormalizedBaseURL) async throws
    -> ArchiveProjectionStatus
}

public struct HealthBridgeArchiveClient:
  ArchiveCapabilityProbing, ArchiveBatchSending, ArchiveStatusFetching, ArchiveInventoryFetching,
  Sendable
{
  private let transport: any HTTPTransport
  private let userID: String
  private let token: String
  private let uploaderCredential: String
  private let requestIDGenerator: @Sendable () -> String

  public var uploaderFingerprint: String? {
    Self.fingerprint(for: uploaderCredential)
  }

  public static func fingerprint(for credential: String) -> String? {
    guard validCredential(credential), let bytes = credentialBytes(credential) else { return nil }
    return SHA256.hash(data: bytes).prefix(6).map { String(format: "%02x", $0) }.joined()
  }

  public init(
    transport: any HTTPTransport, userID: String, token: String,
    uploaderCredential: String,
    requestIDGenerator: @escaping @Sendable () -> String = {
      "archive.\(UUID().uuidString.lowercased())"
    }
  ) {
    self.transport = transport
    self.userID = userID
    self.token = token
    self.uploaderCredential = uploaderCredential
    self.requestIDGenerator = requestIDGenerator
  }

  public func probe(
    baseURL: NormalizedBaseURL, userID: String, token: String
  ) async throws -> ArchiveCapability {
    let requestID = requestIDGenerator()
    let data = try await perform(
      ControlRequest(requestType: "archive_capability", requestID: requestID, userID: userID),
      token: token, baseURL: baseURL)
    let response: ArchiveCapability = try decode(data)
    do { try response.validate(requestID: requestID) } catch {
      throw NetworkFailure.protocolMismatch
    }
    return response
  }

  public func send(
    _ batch: ArchiveBatch, baseURL: NormalizedBaseURL
  ) async throws -> ArchiveAcknowledgement {
    guard batch.userID == userID else { throw ArchiveClientError.invalidRequest }
    do { try batch.validate() } catch { throw ArchiveClientError.invalidRequest }
    let data = try await perform(batch, token: token, baseURL: baseURL)
    let response: ArchiveAcknowledgement = try decode(data)
    do {
      try response.validate(
        requestID: batch.requestID, batchID: batch.batchID,
        samples: batch.samples.count, deletions: batch.deletions.count)
    } catch { throw NetworkFailure.protocolMismatch }
    return response
  }

  public func claimOwner(baseURL: NormalizedBaseURL) async throws -> ArchiveOwnerClaimStatus {
    let requestID = requestIDGenerator()
    let data = try await perform(
      ControlRequest(requestType: "archive_owner_claim", requestID: requestID, userID: userID),
      token: token, baseURL: baseURL)
    let response: ArchiveOwnerClaimStatus = try decode(data)
    do { try response.validate(requestID: requestID) } catch {
      throw NetworkFailure.protocolMismatch
    }
    return response
  }

  public func status(
    requestID: String, baseURL: NormalizedBaseURL
  ) async throws -> ArchiveProjectionStatus {
    let data = try await perform(
      ControlRequest(requestType: "archive_status", requestID: requestID, userID: userID),
      token: token, baseURL: baseURL)
    let response: ArchiveProjectionStatus = try decode(data)
    do { try response.validate(requestID: requestID) } catch {
      throw NetworkFailure.protocolMismatch
    }
    return response
  }

  public func page(
    query: ArchiveInventoryQuery, baseURL: NormalizedBaseURL
  ) async throws -> ArchiveInventoryPage {
    guard query.userID == userID else { throw ArchiveClientError.invalidRequest }
    do { try query.validate() } catch { throw ArchiveClientError.invalidRequest }
    let data = try await perform(query, token: token, baseURL: baseURL)
    let response: ArchiveInventoryPage = try decode(data)
    do { try response.validate(query: query) } catch { throw NetworkFailure.protocolMismatch }
    return response
  }

  private func perform<Value: Encodable>(
    _ payload: Value, token: String, baseURL: NormalizedBaseURL
  ) async throws -> Data {
    guard ArchiveWire.validText(token), Self.validCredential(uploaderCredential) else {
      throw ArchiveClientError.invalidRequest
    }
    if let control = payload as? ControlRequest,
      !ArchiveWire.validID(control.requestID) || !ArchiveWire.validID(control.userID)
    {
      throw ArchiveClientError.invalidRequest
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payloadData: Data
    do { payloadData = try encoder.encode(payload) } catch {
      throw ArchiveClientError.invalidRequest
    }
    var object = try JSONSerialization.jsonObject(with: payloadData) as! [String: Any]
    object["token"] = token
    object["uploader_credential"] = uploaderCredential
    let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard body.count <= ArchiveBatch.maximumBytes else { throw ArchiveClientError.requestTooLarge }

    var request = URLRequest(url: baseURL.healthBridgeWebhookURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 50
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = body

    let data: Data
    let response: HTTPURLResponse
    do { (data, response) = try await transport.data(for: request) } catch let failure
      as NetworkFailure
    { throw failure } catch { throw NetworkFailure.classify(error) }

    guard data.count <= ArchiveBatch.maximumBytes else { throw ArchiveClientError.responseTooLarge }
    guard (200...299).contains(response.statusCode) else {
      if response.statusCode == 403 || response.statusCode == 409,
        let error = try? JSONDecoder().decode(ArchiveErrorResponse.self, from: data), !error.ok
      {
        switch error.error {
        case "owner_required": throw ArchiveClientError.ownerRequired
        case "owner_pending": throw ArchiveClientError.ownerPending
        case "owner_changed": throw ArchiveClientError.ownerChanged
        default: break
        }
      }
      if response.statusCode == 409,
        let error = try? JSONDecoder().decode(ArchiveErrorResponse.self, from: data),
        !error.ok, error.error == "inventory_changed"
      {
        throw ArchiveClientError.inventoryChanged
      }
      let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
        if let key = entry.key as? String, let value = entry.value as? String {
          result[key] = value
        }
      }
      throw NetworkFailure.classify(statusCode: response.statusCode, headers: headers)
    }
    return data
  }

  private static func validCredential(_ value: String) -> Bool {
    guard value.count == 43,
      value.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
          || $0 == 45 || $0 == 95
      })
    else { return false }
    return credentialBytes(value) != nil
  }

  private static func credentialBytes(_ value: String) -> Data? {
    let padded =
      value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/") + "="
    guard let bytes = Data(base64Encoded: padded), bytes.count == 32 else { return nil }
    let canonical = bytes.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    guard canonical == value else { return nil }
    return bytes
  }

  private func decode<Value: Decodable>(_ data: Data) throws -> Value {
    do { return try JSONDecoder().decode(Value.self, from: data) } catch {
      throw NetworkFailure.malformedResponse
    }
  }
}

private struct ArchiveErrorResponse: Decodable {
  let ok: Bool
  let error: String
}

private struct ControlRequest: Encodable {
  let requestType: String
  let protocolVersion = 2
  let requestID: String
  let userID: String

  enum CodingKeys: String, CodingKey {
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case userID = "user_id"
  }
}
