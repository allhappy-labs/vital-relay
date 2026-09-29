import Foundation
import Security

enum ArchiveUploaderCredentialStoreError: Error, Equatable, Sendable {
  case invalidStoredValue
  case operationFailed(OSStatus)
}

actor ArchiveUploaderCredentialStore {
  static let account = "archive-uploader-credential"

  private let service: String

  init(service: String = KeychainCredentialStore.defaultService) {
    self.service = service
  }

  func loadOrCreate() throws -> String {
    if let saved = try read() {
      return Self.encode(saved)
    }

    var bytes = Data(count: 32)
    defer { bytes.resetBytes(in: bytes.indices) }
    let randomStatus = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard randomStatus == errSecSuccess else {
      throw ArchiveUploaderCredentialStoreError.operationFailed(randomStatus)
    }

    var item = baseQuery()
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecAttrSynchronizable as String] = false
    item[kSecValueData as String] = bytes
    let status = SecItemAdd(item as CFDictionary, nil)
    switch status {
    case errSecSuccess:
      return Self.encode(bytes)
    case errSecDuplicateItem:
      guard let saved = try read() else {
        throw ArchiveUploaderCredentialStoreError.operationFailed(status)
      }
      return Self.encode(saved)
    default:
      throw ArchiveUploaderCredentialStoreError.operationFailed(status)
    }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ArchiveUploaderCredentialStoreError.operationFailed(status)
    }
  }

  private func read() throws -> Data? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let bytes = result as? Data, bytes.count == 32 else {
        throw ArchiveUploaderCredentialStoreError.invalidStoredValue
      }
      return bytes
    case errSecItemNotFound:
      return nil
    default:
      throw ArchiveUploaderCredentialStoreError.operationFailed(status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: Self.account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private static func encode(_ bytes: Data) -> String {
    bytes.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
