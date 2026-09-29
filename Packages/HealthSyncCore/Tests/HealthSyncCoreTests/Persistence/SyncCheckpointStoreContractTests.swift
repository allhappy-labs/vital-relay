import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sync checkpoint store contract")
struct SyncCheckpointStoreContractTests {
  @Test("Anchors are independent, replaceable, and resettable")
  func lifecycle() async throws {
    let store = InMemorySyncCheckpointStore()
    let first = Data([1, 2, 3])
    let replacement = Data([4, 5, 6])
    let body = Data([7, 8, 9])

    try await store.commit(anchor: first, for: .steps)
    try await store.commit(anchor: body, for: .bodyMass)
    try await store.commit(anchor: replacement, for: .steps)

    #expect(try await store.anchor(for: .steps) == replacement)
    #expect(try await store.anchor(for: .bodyMass) == body)
    try await store.reset(metric: .steps)
    #expect(try await store.anchor(for: .steps) == nil)
    #expect(try await store.anchor(for: .bodyMass) == body)
    try await store.resetAll()
    #expect(try await store.anchor(for: .bodyMass) == nil)
  }

  @Test("Empty and cancelled commits never replace an anchor")
  func failedCommits() async throws {
    let original = Data([1])
    let store = InMemorySyncCheckpointStore(anchors: [.steps: original])

    await #expect(throws: SyncCheckpointStoreError.emptyAnchor) {
      try await store.commit(anchor: Data(), for: .steps)
    }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await store.commit(anchor: Data([2]), for: .steps)
    }
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(try await store.anchor(for: .steps) == original)
  }

  @Test("Versioned checkpoint coding fails closed")
  func coding() throws {
    let anchors: [MetricID: Data] = [.steps: Data([1]), .bodyMass: Data([2])]
    let encoded = try SyncCheckpointCodec.encode(anchors)
    #expect(try SyncCheckpointCodec.decode(encoded) == anchors)

    #expect(throws: SyncCheckpointStoreError.corruptedData) {
      try SyncCheckpointCodec.decode(Data("not-json".utf8))
    }
    #expect(throws: SyncCheckpointStoreError.unsupportedVersion) {
      try SyncCheckpointCodec.decode(Data(#"{"version":2,"anchors":{}}"#.utf8))
    }
    #expect(throws: SyncCheckpointStoreError.emptyAnchor) {
      try SyncCheckpointCodec.encode([.steps: Data()])
    }
  }
}
