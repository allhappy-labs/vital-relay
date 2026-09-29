import Foundation

public enum CredentialKind: String, CaseIterable, Sendable {
  case webhookSecret = "health-bridge-webhook-secret"
  case accessToken = "home-assistant-long-lived-token"
}

public enum CredentialStoreError: Error, Equatable, Sendable {
  case blankValue
}

public protocol CredentialStore: Sendable {
  func read(_ kind: CredentialKind) async throws -> String?
  func write(_ value: String, for kind: CredentialKind) async throws
  func delete(_ kind: CredentialKind) async throws
  func deleteAll() async throws
}

public actor InMemoryCredentialStore: CredentialStore {
  private var values: [CredentialKind: String] = [:]

  public init() {}

  public func read(_ kind: CredentialKind) throws -> String? {
    values[kind]
  }

  public func write(_ value: String, for kind: CredentialKind) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CredentialStoreError.blankValue
    }
    values[kind] = value
  }

  public func delete(_ kind: CredentialKind) throws {
    values[kind] = nil
  }

  public func deleteAll() throws {
    values.removeAll()
  }
}
