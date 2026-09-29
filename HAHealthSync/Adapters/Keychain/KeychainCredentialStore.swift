import Foundation
import HealthSyncCore
import Security

enum KeychainCredentialStoreError: Error, Equatable, Sendable {
  case interactionNotAllowed
  case accessDenied
  case invalidStoredValue
  case operationFailed(OSStatus)
}

actor KeychainCredentialStore: CredentialStore {
  static let defaultService = "com.olhapi.HAHealthSync.credentials"

  private let service: String

  init(service: String = defaultService) {
    self.service = service
  }

  func read(_ kind: CredentialKind) throws -> String? {
    var query = baseQuery(for: kind)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard var data = result as? Data else {
        throw KeychainCredentialStoreError.invalidStoredValue
      }
      defer { data.resetBytes(in: data.indices) }
      guard let value = String(data: data, encoding: .utf8) else {
        throw KeychainCredentialStoreError.invalidStoredValue
      }
      return value
    case errSecItemNotFound:
      return nil
    default:
      throw Self.error(for: status)
    }
  }

  func write(_ value: String, for kind: CredentialKind) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CredentialStoreError.blankValue
    }

    var data = Data(value.utf8)
    defer { data.resetBytes(in: data.indices) }

    var item = baseQuery(for: kind)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecValueData as String] = data

    let addStatus = SecItemAdd(item as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return
    }
    guard addStatus == errSecDuplicateItem else {
      throw Self.error(for: addStatus)
    }

    let attributes: [String: Any] = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(
      baseQuery(for: kind) as CFDictionary,
      attributes as CFDictionary
    )
    guard updateStatus == errSecSuccess else {
      throw Self.error(for: updateStatus)
    }
  }

  func delete(_ kind: CredentialKind) throws {
    let status = SecItemDelete(baseQuery(for: kind) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Self.error(for: status)
    }
  }

  func deleteAll() throws {
    for kind in CredentialKind.allCases {
      try delete(kind)
    }
  }

  private func baseQuery(for kind: CredentialKind) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: kind.rawValue,
    ]
  }

  private static func error(for status: OSStatus) -> KeychainCredentialStoreError {
    switch status {
    case errSecInteractionNotAllowed:
      .interactionNotAllowed
    case errSecAuthFailed, errSecUserCanceled:
      .accessDenied
    default:
      .operationFailed(status)
    }
  }
}
