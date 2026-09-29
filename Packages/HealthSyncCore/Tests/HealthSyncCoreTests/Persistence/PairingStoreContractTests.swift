import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Pairing store contract")
struct PairingStoreContractTests {
  @Test("Saves updates deletes and orders deterministically")
  func mutatesByStableID() async throws {
    let store = InMemoryPairingStore()
    let second = pairing(id: "20000000-0000-0000-0000-000000000002", entity: "sensor.zeta")
    var first = pairing(id: "10000000-0000-0000-0000-000000000001", entity: "sensor.alpha")

    try await store.save(second)
    try await store.save(first)
    #expect(try await store.all().map(\.entityID) == ["sensor.alpha", "sensor.zeta"])

    first.isEnabled = false
    try await store.save(first)
    #expect(try await store.all().first?.isEnabled == false)

    try await store.delete(id: second.id)
    #expect(try await store.all() == [first])
    try await store.deleteAll()
    #expect(try await store.all().isEmpty)
  }

  @Test("Duplicate validation is atomic")
  func duplicateSaveDoesNotMutate() async throws {
    let store = InMemoryPairingStore()
    let original = pairing(id: "10000000-0000-0000-0000-000000000001", entity: "sensor.mass")
    let duplicate = pairing(id: "20000000-0000-0000-0000-000000000002", entity: "sensor.mass")
    try await store.save(original)

    await #expect(throws: PairingValidationError.duplicateEnabledPairing) {
      try await store.save(duplicate)
    }
    #expect(try await store.all() == [original])
  }

  @Test("Versioned coding round-trips without credential fields")
  func codecRoundTrip() throws {
    let pairings = [pairing(id: "10000000-0000-0000-0000-000000000001", entity: "sensor.mass")]
    let data = try PairingCodec.encode(pairings)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains(#""version":1"#))
    #expect(!text.localizedCaseInsensitiveContains("token"))
    #expect(!text.localizedCaseInsensitiveContains("secret"))
    #expect(try PairingCodec.decode(data) == pairings)
    #expect(throws: PairingStoreError.unsupportedVersion) {
      try PairingCodec.decode(Data(#"{"version":2,"pairings":[]}"#.utf8))
    }
    #expect(throws: PairingStoreError.corruptedData) {
      try PairingCodec.decode(Data("invalid".utf8))
    }
  }

  private func pairing(id: String, entity: String) -> Pairing {
    Pairing(
      id: UUID(uuidString: id)!,
      entityID: entity,
      destination: .bodyMass,
      sourceUnit: .kilograms,
      destinationUnit: .kilograms,
      transformation: .identity,
      isEnabled: true
    )
  }
}
