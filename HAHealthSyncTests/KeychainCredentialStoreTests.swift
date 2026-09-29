import HealthSyncCore
import Security
import XCTest

@testable import HAHealthSync

final class KeychainCredentialStoreTests: XCTestCase {
  func testUsesExactProductionServiceAndAccounts() {
    XCTAssertEqual(
      KeychainCredentialStore.defaultService,
      "com.olhapi.HAHealthSync.credentials"
    )
    XCTAssertEqual(
      CredentialKind.webhookSecret.rawValue,
      "health-bridge-webhook-secret"
    )
    XCTAssertEqual(
      CredentialKind.accessToken.rawValue,
      "home-assistant-long-lived-token"
    )
  }

  func testSeparatesUpdatesAndDeletesCredentials() async throws {
    let service = testService()
    let store = KeychainCredentialStore(service: service)
    defer { deleteTestItems(service: service) }

    try await store.write("webhook-value", for: .webhookSecret)
    try await store.write("access-value", for: .accessToken)
    try await store.write("updated-webhook-value", for: .webhookSecret)

    let webhookSecret = try await store.read(.webhookSecret)
    let accessToken = try await store.read(.accessToken)
    XCTAssertEqual(webhookSecret, "updated-webhook-value")
    XCTAssertEqual(accessToken, "access-value")

    try await store.deleteAll()
    let deletedWebhookSecret = try await store.read(.webhookSecret)
    let deletedAccessToken = try await store.read(.accessToken)
    XCTAssertNil(deletedWebhookSecret)
    XCTAssertNil(deletedAccessToken)
  }

  func testRejectsBlankValues() async {
    let service = testService()
    let store = KeychainCredentialStore(service: service)
    defer { deleteTestItems(service: service) }

    do {
      try await store.write(" \n ", for: .accessToken)
      XCTFail("Expected blankValue")
    } catch {
      XCTAssertEqual(error as? CredentialStoreError, .blankValue)
    }
  }

  func testUsesDeviceOnlyAfterFirstUnlockAccessibility() async throws {
    let service = testService()
    let store = KeychainCredentialStore(service: service)
    defer { deleteTestItems(service: service) }
    try await store.write("webhook-value", for: .webhookSecret)

    var query = baseQuery(service: service, kind: .webhookSecret)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?

    XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
    let attributes = try XCTUnwrap(result as? [String: Any])
    XCTAssertEqual(
      attributes[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
  }

  private func testService() -> String {
    "com.olhapi.HAHealthSync.credentials.tests.\(UUID().uuidString)"
  }

  private func baseQuery(
    service: String,
    kind: CredentialKind? = nil
  ) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if let kind {
      query[kSecAttrAccount as String] = kind.rawValue
    }
    return query
  }

  private func deleteTestItems(service: String) {
    SecItemDelete(baseQuery(service: service) as CFDictionary)
  }
}
