import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Health Bridge medication payload")
struct MedicationPayloadTests {
  private let firstID = MedicationIdentifier.make(from: Data("first".utf8))
  private let secondID = MedicationIdentifier.make(from: Data("second".utf8))

  @Test("Aggregates pending partial and taken medication states deterministically")
  func aggregation() throws {
    let payload = try MedicationPayload.aggregate(
      concepts: [
        MedicationConcept(id: secondID, name: "Second"),
        MedicationConcept(id: firstID, name: "First"),
        MedicationConcept(
          id: MedicationIdentifier.make(from: Data("archived".utf8)),
          name: "Archived",
          isArchived: true
        ),
      ],
      doses: [
        MedicationDose(
          medicationID: firstID,
          status: .taken,
          schedule: .scheduled,
          doseQuantity: 250,
          unit: "mg"
        ),
        MedicationDose(
          medicationID: firstID,
          status: .pending,
          schedule: .scheduled,
          doseQuantity: 250,
          unit: "mg"
        ),
        MedicationDose(
          medicationID: secondID,
          status: .taken,
          schedule: .asNeeded,
          doseQuantity: 1,
          unit: "tablet"
        ),
      ]
    )

    #expect(payload.records.map(\.id) == [firstID, secondID].sorted())
    let first = try #require(payload.records.first { $0.id == firstID })
    #expect(first.state == .partial)
    #expect(first.taken == 1)
    #expect(first.scheduled == 2)
    #expect(first.doseTaken == 250)
    #expect(first.unit == "mg")
    #expect(first.summary == "1 of 2 taken")
    let second = try #require(payload.records.first { $0.id == secondID })
    #expect(second.state == .taken)
    #expect(second.summary == "1 taken as needed")
  }

  @Test("Encodes the special top-level medications array")
  func wireShape() throws {
    let payload = try MedicationPayload.aggregate(
      concepts: [MedicationConcept(id: firstID, name: "Example medication")],
      doses: [
        MedicationDose(
          medicationID: firstID,
          status: .taken,
          schedule: .scheduled,
          doseQuantity: 500,
          unit: "mg"
        )
      ]
    )
    let request = LiveRequest(
      token: "example-secret",
      userID: "fixture-user",
      requestID: "live.01234567",
      medications: payload
    )

    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    let data = try #require(object["data"] as? [String: Any])
    let medications = try #require(data["medications"] as? [[String: Any]])
    #expect(medications.count == 1)
    #expect(medications[0]["id"] as? String == firstID)
    #expect(medications[0]["state"] as? String == "taken")
    #expect(medications[0]["dose_taken"] as? Double == 500)
    #expect(object["token"] as? String == "example-secret")
  }

  @Test("Rejects malformed identifiers fields doses and empty payloads")
  func validation() {
    #expect(throws: MedicationPayloadError.invalidIdentifier) {
      try MedicationBridgeRecord(
        id: "unsafe id", state: .pending, name: nil, taken: 0, scheduled: 0,
        doseTaken: nil, unit: nil, summary: "0 taken as needed"
      )
    }
    #expect(throws: MedicationPayloadError.invalidDose) {
      try MedicationBridgeRecord(
        id: firstID, state: .taken, name: "Example", taken: 1, scheduled: 1,
        doseTaken: .nan, unit: "mg", summary: "1 of 1 taken"
      )
    }
    #expect(throws: MedicationPayloadError.emptyPayload) {
      try MedicationPayload(records: [])
    }
  }

  @Test("Stable identifiers are opaque bounded and deterministic")
  func identifiers() {
    let repeated = MedicationIdentifier.make(from: Data("first".utf8))
    #expect(repeated == firstID)
    #expect(firstID.count == 36)
    #expect(MedicationIdentifier.isValid(firstID))
    #expect(firstID.contains("first") == false)
  }
}
