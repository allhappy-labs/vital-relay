import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Medication checkpoint store contract")
struct MedicationCheckpointStoreTests {
  @Test("Versioned value-free checkpoint round-trips")
  func roundTrip() throws {
    let id = MedicationIdentifier.make(from: Data("medication".utf8))
    let checkpoint = MedicationCheckpoint(
      anchor: Data([1, 2, 3]),
      medicationIDs: [id],
      sourceFingerprint: MedicationIdentifier.fingerprint([id])
    )

    let data = try MedicationCheckpointCodec.encode(checkpoint)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains(#""version":1"#))
    #expect(text.contains("dose") == false)
    #expect(text.contains("name") == false)
    #expect(try MedicationCheckpointCodec.decode(data) == checkpoint)
  }

  @Test("Malformed identifiers fingerprints and versions fail closed")
  func invalid() {
    #expect(throws: MedicationCheckpointStoreError.corruptedData) {
      try MedicationCheckpointCodec.encode(
        MedicationCheckpoint(anchor: nil, medicationIDs: ["unsafe"], sourceFingerprint: "")
      )
    }
    #expect(throws: MedicationCheckpointStoreError.unsupportedVersion) {
      try MedicationCheckpointCodec.decode(Data(#"{"version":2}"#.utf8))
    }
    #expect(throws: MedicationCheckpointStoreError.corruptedData) {
      try MedicationCheckpointCodec.decode(Data("not-json".utf8))
    }
  }
}
