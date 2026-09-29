import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Backfill checkpoint store contract")
struct BackfillCheckpointStoreTests {
  @Test("Versioned checkpoint state round-trips without health values")
  func roundTrip() throws {
    let state = BackfillState(
      capability: .available(protocolVersion: 1),
      checkpoints: [
        .steps: BackfillCheckpoint(
          metricID: .steps,
          windowStart: Date(timeIntervalSince1970: 100),
          committedThrough: Date(timeIntervalSince1970: 200),
          requestID: "backfill.01234567"
        )
      ]
    )

    let data = try BackfillCheckpointCodec.encode(state)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains(#""version":1"#))
    #expect(text.contains("value") == false)
    #expect(try BackfillCheckpointCodec.decode(data) == state)
  }

  @Test("Unsupported versions and inconsistent checkpoints fail closed")
  func invalidDocuments() throws {
    let unsupported = Data(
      #"{"version":2,"state":{"capability":{"unprobed":{}},"checkpoints":{}}}"#.utf8)
    #expect(throws: BackfillCheckpointStoreError.unsupportedVersion) {
      try BackfillCheckpointCodec.decode(unsupported)
    }

    let inconsistent = BackfillState(
      checkpoints: [
        .steps: BackfillCheckpoint(
          metricID: .bodyMass,
          windowStart: Date(timeIntervalSince1970: 200),
          committedThrough: Date(timeIntervalSince1970: 100),
          requestID: "not valid"
        )
      ]
    )
    #expect(throws: BackfillCheckpointStoreError.corruptedData) {
      try BackfillCheckpointCodec.encode(inconsistent)
    }
    #expect(throws: BackfillCheckpointStoreError.corruptedData) {
      try BackfillCheckpointCodec.decode(Data("not-json".utf8))
    }
  }
}
