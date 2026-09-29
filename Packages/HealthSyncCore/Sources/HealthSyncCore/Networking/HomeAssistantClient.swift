import Foundation

public struct HomeAssistantAPIStatus: Decodable, Sendable, Equatable {
  public let message: String

  public init(message: String) {
    self.message = message
  }
}

public protocol AuthenticatedConnectionTesting: Sendable {
  func testAuthenticatedAPI(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) async throws -> HomeAssistantAPIStatus
}

public protocol HomeAssistantStateFetching: Sendable {
  func fetchState(
    entityID: String,
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) async throws -> HomeAssistantState
  func fetchState(
    entityID: String,
    baseURL: NormalizedBaseURL,
    accessToken: String,
    timeout: TimeInterval
  ) async throws -> HomeAssistantState
}

extension HomeAssistantStateFetching {
  public func fetchState(
    entityID: String,
    baseURL: NormalizedBaseURL,
    accessToken: String,
    timeout: TimeInterval
  ) async throws -> HomeAssistantState {
    try await fetchState(entityID: entityID, baseURL: baseURL, accessToken: accessToken)
  }
}

public protocol HomeAssistantStateListing: Sendable {
  func fetchStates(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) async throws -> [HomeAssistantState]
}

public protocol HomeAssistantStatePublishing: Sendable {
  func publishState(
    entityID: String,
    state: String,
    attributes: [String: JSONValue],
    baseURL: NormalizedBaseURL,
    accessToken: String,
    timeout: TimeInterval
  ) async throws
}

public struct HomeAssistantClient: Sendable {
  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport) {
    self.transport = transport
  }

  public func testAuthenticatedAPI(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) async throws -> HomeAssistantAPIStatus {
    guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CredentialStoreError.blankValue
    }

    var request = URLRequest(url: baseURL.authenticatedAPIURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

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

    do {
      let status = try JSONDecoder().decode(HomeAssistantAPIStatus.self, from: data)
      guard !status.message.isEmpty else {
        throw NetworkFailure.malformedResponse
      }
      return status
    } catch let failure as NetworkFailure {
      throw failure
    } catch {
      throw NetworkFailure.malformedResponse
    }
  }

  public func fetchState(
    entityID: String,
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) async throws -> HomeAssistantState {
    try await fetchState(
      entityID: entityID,
      baseURL: baseURL,
      accessToken: accessToken,
      timeout: ExecutionDeadline.defaultRequestTimeout
    )
  }

  public func fetchState(
    entityID: String,
    baseURL: NormalizedBaseURL,
    accessToken: String,
    timeout: TimeInterval
  ) async throws -> HomeAssistantState {
    guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CredentialStoreError.blankValue
    }

    var request = URLRequest(url: try baseURL.stateURL(entityID: entityID))
    request.httpMethod = "GET"
    request.timeoutInterval = timeout
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.data(for: request)
    } catch let failure as NetworkFailure {
      throw failure
    } catch {
      throw NetworkFailure.classify(error)
    }
    guard response.statusCode == 200 else {
      throw NetworkFailure.classify(
        statusCode: response.statusCode,
        headers: Self.stringHeaders(response)
      )
    }

    do {
      return try Self.homeAssistantDecoder().decode(HomeAssistantState.self, from: data)
    } catch {
      throw NetworkFailure.malformedResponse
    }
  }

  public func fetchStates(
    baseURL: NormalizedBaseURL,
    accessToken: String
  ) async throws -> [HomeAssistantState] {
    guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CredentialStoreError.blankValue
    }

    var request = URLRequest(url: baseURL.statesURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.data(for: request)
    } catch let failure as NetworkFailure {
      throw failure
    } catch {
      throw NetworkFailure.classify(error)
    }
    guard response.statusCode == 200 else {
      throw NetworkFailure.classify(
        statusCode: response.statusCode,
        headers: Self.stringHeaders(response)
      )
    }

    do {
      return try Self.homeAssistantDecoder().decode([HomeAssistantState].self, from: data)
    } catch {
      throw NetworkFailure.malformedResponse
    }
  }

  public func publishState(
    entityID: String,
    state: String,
    attributes: [String: JSONValue],
    baseURL: NormalizedBaseURL,
    accessToken: String,
    timeout: TimeInterval
  ) async throws {
    guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CredentialStoreError.blankValue
    }
    var request = URLRequest(url: try baseURL.stateURL(entityID: entityID))
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    request.httpBody = try encoder.encode(StateBody(state: state, attributes: attributes))

    let response: HTTPURLResponse
    do {
      (_, response) = try await transport.data(for: request)
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
  }

  private struct StateBody: Encodable {
    let state: String
    let attributes: [String: JSONValue]
  }

  private static func homeAssistantDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) {
        return date
      }
      let wholeSeconds = ISO8601DateFormatter()
      wholeSeconds.formatOptions = [.withInternetDateTime]
      if let date = wholeSeconds.date(from: value) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid RFC3339 timestamp"
      )
    }
    return decoder
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

extension HomeAssistantClient: AuthenticatedConnectionTesting {}
extension HomeAssistantClient: HomeAssistantStateFetching {}
extension HomeAssistantClient: HomeAssistantStateListing {}
extension HomeAssistantClient: HomeAssistantStatePublishing {}
