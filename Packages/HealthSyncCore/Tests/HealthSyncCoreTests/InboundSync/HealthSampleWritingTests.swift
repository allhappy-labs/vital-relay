import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Health sample writer contract")
struct HealthSampleWritingTests {
  @Test("Fake records scoped authorization and exact idempotent write")
  func fakeRecordsCalls() async throws {
    let fake = FakeHealthSampleWriter()
    let write = HealthSampleWrite(
      destination: .bodyMass,
      value: 70,
      date: Date(timeIntervalSince1970: 1_788_052_801),
      syncIdentifier: "ha-health-sync." + String(repeating: "a", count: 64),
      syncVersion: 1
    )

    try await fake.requestWriteAuthorization(for: [.bodyMass])
    try await fake.save(write)

    #expect(await fake.authorizedDestinations == [.bodyMass])
    #expect(await fake.savedSamples == [write])
  }

  @Test("Fake forwards failures and cancellation without saving")
  func fakeForwardsFailureAndCancellation() async throws {
    let failure = FakeHealthSampleWriter(error: FakeHealthSampleWriter.Failure.expected)
    await #expect(throws: FakeHealthSampleWriter.Failure.expected) {
      try await failure.requestWriteAuthorization(for: [.bodyMass])
    }

    let cancelled = FakeHealthSampleWriter()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await cancelled.save(
        HealthSampleWrite(
          destination: .bodyMass,
          value: 70,
          date: .now,
          syncIdentifier: "ha-health-sync." + String(repeating: "a", count: 64),
          syncVersion: 1
        )
      )
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await cancelled.savedSamples.isEmpty)
  }
}

private actor FakeHealthSampleWriter: HealthSampleWriting {
  enum Failure: Error { case expected }

  let error: (any Error)?
  private(set) var authorizedDestinations: Set<HealthObjectTypeID> = []
  private(set) var savedSamples: [HealthSampleWrite] = []

  init(error: (any Error)? = nil) {
    self.error = error
  }

  func requestWriteAuthorization(for destinations: Set<HealthObjectTypeID>) throws {
    try Task.checkCancellation()
    if let error { throw error }
    authorizedDestinations.formUnion(destinations)
  }

  func save(_ sample: HealthSampleWrite) throws {
    try Task.checkCancellation()
    if let error { throw error }
    savedSamples.append(sample)
  }
}
