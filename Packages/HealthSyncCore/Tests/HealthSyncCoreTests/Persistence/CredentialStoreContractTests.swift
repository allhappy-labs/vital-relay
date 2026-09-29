import Testing

@testable import HealthSyncCore

@Suite("Credential store contract")
struct CredentialStoreContractTests {
  @Test("Credentials remain separate")
  func credentialsRemainSeparate() async throws {
    let store = InMemoryCredentialStore()

    try await store.write("webhook-value", for: .webhookSecret)
    try await store.write("access-value", for: .accessToken)
    try await store.write("updated-webhook-value", for: .webhookSecret)

    #expect(try await store.read(.webhookSecret) == "updated-webhook-value")
    #expect(try await store.read(.accessToken) == "access-value")
  }

  @Test("Missing and deleted credentials return nil")
  func absenceBehavior() async throws {
    let store = InMemoryCredentialStore()

    #expect(try await store.read(.webhookSecret) == nil)
    try await store.write("webhook-value", for: .webhookSecret)
    try await store.delete(.webhookSecret)
    #expect(try await store.read(.webhookSecret) == nil)
  }

  @Test("Blank credential values are rejected")
  func blankValuesAreRejected() async {
    let store = InMemoryCredentialStore()

    do {
      try await store.write(" \n\t ", for: .accessToken)
      Issue.record("Expected blankValue")
    } catch {
      #expect(error as? CredentialStoreError == .blankValue)
    }
  }

  @Test("Delete all removes both exact records")
  func deleteAllRemovesBothCredentials() async throws {
    let store = InMemoryCredentialStore()
    try await store.write("webhook-value", for: .webhookSecret)
    try await store.write("access-value", for: .accessToken)

    try await store.deleteAll()

    #expect(try await store.read(.webhookSecret) == nil)
    #expect(try await store.read(.accessToken) == nil)
  }

  @Test("Credential accounts are stable and explicit")
  func credentialAccountsAreStable() {
    #expect(CredentialKind.webhookSecret.rawValue == "health-bridge-webhook-secret")
    #expect(CredentialKind.accessToken.rawValue == "home-assistant-long-lived-token")
  }
}
