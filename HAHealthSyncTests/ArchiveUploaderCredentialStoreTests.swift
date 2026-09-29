import Foundation
import HealthSyncCore
import Security
import XCTest

@testable import HAHealthSync

final class ArchiveUploaderCredentialStoreTests: XCTestCase {
  func testLoadOrCreatePersistsA32ByteBase64URLValue() async throws {
    let service = testService()
    defer { deleteTestItems(service: service) }
    let store = ArchiveUploaderCredentialStore(service: service)

    let first = try await store.loadOrCreate()
    let second = try await ArchiveUploaderCredentialStore(service: service).loadOrCreate()

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.count, 43)
    XCTAssertTrue(
      first.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    let base64 =
      first.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/") + "="
    XCTAssertEqual(Data(base64Encoded: base64)?.count, 32)
  }

  func testDeleteCreatesANewCredential() async throws {
    let service = testService()
    defer { deleteTestItems(service: service) }
    let store = ArchiveUploaderCredentialStore(service: service)

    let first = try await store.loadOrCreate()
    try await store.delete()
    let second = try await store.loadOrCreate()

    XCTAssertNotEqual(first, second)
  }

  func testKeychainItemIsDeviceOnlyAndNonSynchronizing() async throws {
    let service = testService()
    defer { deleteTestItems(service: service) }
    let store = ArchiveUploaderCredentialStore(service: service)
    _ = try await store.loadOrCreate()

    var query = baseQuery(service: service)
    query[kSecAttrAccount as String] = ArchiveUploaderCredentialStore.account
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
    let attributes = try XCTUnwrap(result as? [String: Any])
    XCTAssertEqual(
      attributes[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
    XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
  }

  func testDeletePreservesWebhookAndAPICredentials() async throws {
    let service = testService()
    defer { deleteTestItems(service: service) }
    let existing = KeychainCredentialStore(service: service)
    try await existing.write("webhook-value", for: .webhookSecret)
    try await existing.write("api-value", for: .accessToken)

    let store = ArchiveUploaderCredentialStore(service: service)
    _ = try await store.loadOrCreate()
    try await store.delete()

    let webhook = try await existing.read(.webhookSecret)
    let api = try await existing.read(.accessToken)
    XCTAssertEqual(webhook, "webhook-value")
    XCTAssertEqual(api, "api-value")
  }

  private func testService() -> String {
    "com.olhapi.HAHealthSync.credentials.tests.\(UUID().uuidString)"
  }

  private func baseQuery(service: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
  }

  private func deleteTestItems(service: String) {
    SecItemDelete(baseQuery(service: service) as CFDictionary)
  }
}
