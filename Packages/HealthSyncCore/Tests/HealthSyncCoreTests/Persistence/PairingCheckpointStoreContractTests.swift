import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Pairing checkpoint store contract")
struct PairingCheckpointStoreContractTests {
  private let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  private let secondID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

  @Test("Checkpoints are independent replaceable and resettable")
  func lifecycle() async throws {
    let store = InMemoryPairingCheckpointStore()
    let first = checkpoint(pairingID: firstID, value: 70)
    let second = checkpoint(pairingID: secondID, value: 80)
    let replacement = checkpoint(pairingID: firstID, value: 71)

    try await store.commit(first)
    try await store.commit(second)
    try await store.commit(replacement)
    #expect(try await store.checkpoint(for: firstID) == replacement)
    #expect(try await store.checkpoint(for: secondID) == second)

    try await store.reset(pairingID: firstID)
    #expect(try await store.checkpoint(for: firstID) == nil)
    try await store.resetAll()
    #expect(try await store.checkpoint(for: secondID) == nil)
  }

  @Test("Exact duplicate matching includes all normalized state fields")
  func duplicateMatching() {
    let checkpoint = checkpoint(pairingID: firstID, value: 70)
    let state = NormalizedHomeAssistantState(
      entityID: checkpoint.entityID,
      lastUpdated: checkpoint.homeAssistantUpdatedAt,
      normalizedValue: checkpoint.normalizedValue,
      destination: checkpoint.destination
    )

    #expect(checkpoint.matches(state))
    let changed = NormalizedHomeAssistantState(
      entityID: state.entityID,
      lastUpdated: state.lastUpdated,
      normalizedValue: 71,
      destination: state.destination
    )
    #expect(!checkpoint.matches(changed))
  }

  @Test("Cancellation and invalid checkpoints never replace committed state")
  func failedCommitRollsBack() async throws {
    let original = checkpoint(pairingID: firstID, value: 70)
    let store = InMemoryPairingCheckpointStore(checkpoints: [firstID: original])
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await store.commit(checkpoint(pairingID: firstID, value: 71))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await store.checkpoint(for: firstID) == original)
  }

  @Test("Versioned coding round-trips and corruption fails closed")
  func coding() throws {
    let value = checkpoint(pairingID: firstID, value: 70)
    let encoded = try PairingCheckpointCodec.encode([firstID: value])
    #expect(try PairingCheckpointCodec.decode(encoded) == [firstID: value])
    #expect(throws: PairingCheckpointStoreError.unsupportedVersion) {
      try PairingCheckpointCodec.decode(Data(#"{"version":2,"checkpoints":{}}"#.utf8))
    }
    #expect(throws: PairingCheckpointStoreError.corruptedData) {
      try PairingCheckpointCodec.decode(Data("invalid".utf8))
    }
  }

  private func checkpoint(pairingID: UUID, value: Double) -> PairingCheckpoint {
    let date = Date(timeIntervalSince1970: 1_788_052_801)
    let identity = SyncIdentity.make(
      pairingID: pairingID,
      entityID: "sensor.body_mass",
      homeAssistantUpdatedAt: date,
      normalizedValue: value,
      destination: .bodyMass
    )
    return PairingCheckpoint(
      pairingID: pairingID,
      entityID: "sensor.body_mass",
      homeAssistantUpdatedAt: date,
      normalizedValue: value,
      destination: .bodyMass,
      syncIdentifier: identity.identifier,
      syncVersion: identity.version
    )
  }
}
