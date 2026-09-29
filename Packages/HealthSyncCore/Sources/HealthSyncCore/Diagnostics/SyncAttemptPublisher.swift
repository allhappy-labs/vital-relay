import Foundation

public protocol SyncAttemptPublishing: Sendable {
  /// Publishes the attempt and returns the failure category, or `nil` on success or when
  /// publishing is disabled or not configured.
  @discardableResult
  func publish(_ event: SyncStatusEvent, deadline: ExecutionDeadline?) async -> SyncFailureCategory?
  func publishTest() async throws
}

public enum SyncAttemptPublisherError: Error, Equatable, Sendable {
  case disabled
}

public actor SyncAttemptPublisher: SyncAttemptPublishing {
  public static let publishTimeout: TimeInterval = 5

  private let configurationStore: any ConfigurationStore
  private let credentialStore: any CredentialStore
  private let client: any HomeAssistantStatePublishing
  private let now: @Sendable () -> Date

  public init(
    configurationStore: any ConfigurationStore,
    credentialStore: any CredentialStore,
    client: any HomeAssistantStatePublishing,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.configurationStore = configurationStore
    self.credentialStore = credentialStore
    self.client = client
    self.now = now
  }

  @discardableResult
  public func publish(
    _ event: SyncStatusEvent,
    deadline: ExecutionDeadline?
  ) async -> SyncFailureCategory? {
    guard let endpoint = try? await endpoint(requireEnabled: true) else { return nil }
    let accessToken: String
    do {
      accessToken = try await self.accessToken()
    } catch {
      return .credential
    }
    let timeout: TimeInterval
    if let deadline {
      guard let bounded = try? deadline.requestTimeout(now: now(), ceiling: Self.publishTimeout)
      else { return .deadlineExceeded }
      timeout = bounded
    } else {
      timeout = Self.publishTimeout
    }
    do {
      try await client.publishState(
        entityID: Self.entityID(userID: endpoint.userID),
        state: Self.timestamp(event.startedAt ?? event.finishedAt),
        attributes: Self.attributes(for: event, userID: endpoint.userID),
        baseURL: endpoint.baseURL,
        accessToken: accessToken,
        timeout: timeout
      )
      return nil
    } catch {
      return Self.failureCategory(for: error)
    }
  }

  public func publishTest() async throws {
    let target = try await target(requireEnabled: false)
    try await client.publishState(
      entityID: Self.entityID(userID: target.userID),
      state: Self.timestamp(now()),
      attributes: [
        "device_class": .string("timestamp"),
        "friendly_name": .string("Health Bridge sync attempt (\(target.userID))"),
        "trigger": .string("test"),
        "outcome": .string("test"),
      ],
      baseURL: target.baseURL,
      accessToken: target.accessToken,
      timeout: Self.publishTimeout
    )
  }

  public static func entityID(userID: String) -> String {
    let slug = String(
      userID.lowercased().map { character in
        character.isASCII && (character.isLetter || character.isNumber) || character == "_"
          ? character : "_"
      }
    )
    return "sensor.health_bridge_sync_attempt_\(slug)"
  }

  public static func outcome(for event: SyncStatusEvent) -> String {
    if event.outcome == .interrupted { return "interrupted" }
    if event.synchronizedMetrics + event.savedPairings > 0 { return "exported" }
    if event.failureCategories.contains(.deviceLocked) { return "locked" }
    if !event.failureCategories.isEmpty { return "failed" }
    return "no_changes"
  }

  public static func attributes(for event: SyncStatusEvent, userID: String) -> [String: JSONValue] {
    [
      "device_class": .string("timestamp"),
      "friendly_name": .string("Health Bridge sync attempt (\(userID))"),
      "trigger": .string(event.trigger.rawValue),
      "outcome": .string(outcome(for: event)),
      "exported_metrics": .number(Double(event.synchronizedMetrics)),
      "imported_pairings": .number(Double(event.savedPairings)),
      "failure_category": event.failureCategories.first.map { .string($0.rawValue) } ?? .null,
      "duration_s": event.duration.map { .number(($0 * 10).rounded() / 10) } ?? .null,
      "throttled_wakes_before": .number(Double(event.throttledWakesBefore)),
    ]
  }

  private static func timestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private struct Endpoint: Sendable {
    let baseURL: NormalizedBaseURL
    let userID: String
  }

  private struct Target: Sendable {
    let baseURL: NormalizedBaseURL
    let accessToken: String
    let userID: String
  }

  private func target(requireEnabled: Bool) async throws -> Target {
    let endpoint = try await endpoint(requireEnabled: requireEnabled)
    return Target(
      baseURL: endpoint.baseURL,
      accessToken: try await accessToken(),
      userID: endpoint.userID
    )
  }

  private func endpoint(requireEnabled: Bool) async throws -> Endpoint {
    let configuration = try await configurationStore.load()
    try configuration.validate()
    if requireEnabled, !configuration.publishSyncAttempts {
      throw SyncAttemptPublisherError.disabled
    }
    let baseURL = try NormalizedBaseURL.parse(
      configuration.baseURL,
      allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP
    )
    return Endpoint(baseURL: baseURL, userID: configuration.healthBridgeUserID)
  }

  private func accessToken() async throws -> String {
    guard let accessToken = try await credentialStore.read(.accessToken),
      !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw CredentialStoreError.blankValue
    }
    return accessToken
  }

  private static func failureCategory(for error: any Error) -> SyncFailureCategory {
    if error is CancellationError { return .cancelled }
    guard let failure = error as? NetworkFailure else { return .transport }
    return switch failure {
    case .cancelled: .cancelled
    case .timeout: .timeout
    case .dnsFailure: .dnsFailure
    case .offline: .offline
    case .connectionLost: .connectionLost
    case .tlsFailure: .tlsFailure
    case .unauthorized: .unauthorized
    case .forbidden: .forbidden
    case .notFound: .notFound
    case .validation: .validation
    case .rateLimited: .rateLimited
    case .server: .server
    case .malformedResponse: .malformedResponse
    case .protocolMismatch: .protocolMismatch
    case .unexpectedStatus, .transport: .transport
    }
  }
}
