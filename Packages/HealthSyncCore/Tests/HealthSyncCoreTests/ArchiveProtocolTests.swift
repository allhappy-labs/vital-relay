import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Archive protocol v2")
struct ArchiveProtocolTests {
  @Test func wireDatesPreserveMicrosecondsAndSampleOrdering() throws {
    let date = try #require(ArchiveWire.utcDate("1970-01-01T00:01:40.000600Z"))
    #expect(abs(date.timeIntervalSince1970 - 100.0006) < 0.0000001)
    var batch = try fixtureObject("archive-batch-v2")
    var samples = batch["samples"] as! [[String: Any]]
    samples[0]["start"] = "2024-01-01T10:00:00.000600Z"
    samples[0]["end"] = "2024-01-01T10:00:00.000400Z"
    batch["samples"] = samples
    #expect(throws: ArchiveValidationError.invalidSample) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: batch))
    }
    samples[0]["end"] = "2024-01-01T10:00:00.000601Z"
    batch["samples"] = samples
    let data = try JSONSerialization.data(withJSONObject: batch)
    try expectSameJSON(data, JSONEncoder().encode(ArchiveBatch.decodeValidated(data)))
  }

  @Test("Canonical batch round trips and retains typed quantity payload")
  func batchFixture() throws {
    let data = try fixtureData(named: "archive-batch-v2")
    let batch = try JSONDecoder().decode(ArchiveBatch.self, from: data)
    try batch.validate()
    #expect(batch.sampleType == "HKQuantityTypeIdentifierStepCount")
    #expect(batch.samples.count == 1)
    guard case .quantity(let quantity) = batch.samples[0].payload else {
      Issue.record("Expected quantity payload")
      return
    }
    #expect(quantity.rawValue == 12)
    #expect(quantity.canonicalUnit == "count")
    try expectSameJSON(data, JSONEncoder().encode(batch))
  }

  @Test("Canonical responses round trip and validate")
  func responseFixtures() throws {
    for (name, key) in [
      ("archive-capability-v2", "response"),
      ("archive-status-v2", "response"),
    ] {
      let original = try fixtureObject(name)[key]!
      let data = try JSONSerialization.data(withJSONObject: original)
      if name == "archive-capability-v2" {
        let response = try JSONDecoder().decode(ArchiveCapability.self, from: data)
        try response.validate(requestID: "request-capability-001")
        #expect(response.supportedSampleTypes.contains("HKWorkoutType"))
        try expectSameJSON(data, JSONEncoder().encode(response))
      } else {
        let response = try JSONDecoder().decode(ArchiveProjectionStatus.self, from: data)
        try response.validate(requestID: "request-status-001")
        #expect(response.metrics.count == 2)
        try expectSameJSON(data, JSONEncoder().encode(response))
      }
    }
    let data = try fixtureData(named: "archive-ack-v2")
    let ack = try JSONDecoder().decode(ArchiveAcknowledgement.self, from: data)
    try ack.validate(requestID: "request-batch-001", batchID: "batch-001", samples: 1, deletions: 0)
    try expectSameJSON(data, JSONEncoder().encode(ack))
  }

  @Test("Rejects incompatible acknowledgements")
  func invalidAcknowledgements() throws {
    for (key, value) in [
      ("protocol_version", 1 as Any), ("request_id", "other"),
      ("batch_id", "other"), ("archive_commit", "pending"),
      ("committed_samples", 2), ("received_samples", -1),
      ("projection_state", "unknown"),
    ] {
      var json = try fixtureObject("archive-ack-v2")
      json[key] = value
      let ack = try JSONDecoder().decode(
        ArchiveAcknowledgement.self, from: JSONSerialization.data(withJSONObject: json))
      #expect(throws: (any Error).self) {
        try ack.validate(
          requestID: "request-batch-001", batchID: "batch-001", samples: 1, deletions: 0)
      }
    }
  }

  @Test("Rejects invalid capability limits and status states")
  func invalidResponses() throws {
    var capability = try fixtureObject("archive-capability-v2")["response"] as! [String: Any]
    capability["max_batch_bytes"] = 262_145
    let cap = try JSONDecoder().decode(
      ArchiveCapability.self, from: JSONSerialization.data(withJSONObject: capability))
    #expect(throws: (any Error).self) {
      try cap.validate(requestID: "request-capability-001")
    }
    var status = try fixtureObject("archive-status-v2")["response"] as! [String: Any]
    status["metrics"] = [["metric": "steps", "state": "unknown", "last_error": NSNull()]]
    let decoded = try JSONDecoder().decode(
      ArchiveProjectionStatus.self, from: JSONSerialization.data(withJSONObject: status))
    #expect(throws: (any Error).self) {
      try decoded.validate(requestID: "request-status-001")
    }

    capability = try fixtureObject("archive-capability-v2")["response"] as! [String: Any]
    capability["archive_schema_version"] = 4
    let futureSchema = try JSONDecoder().decode(
      ArchiveCapability.self, from: JSONSerialization.data(withJSONObject: capability))
    #expect(throws: (any Error).self) {
      try futureSchema.validate(requestID: "request-capability-001")
    }
  }

  @Test("Schema three requires a typed ownership contract")
  func ownedCapability() throws {
    var json = try fixtureObject("archive-capability-v2")["response"] as! [String: Any]
    json["archive_schema_version"] = 3
    let legacy = try JSONDecoder().decode(
      ArchiveCapability.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(!legacy.supportsOwnershipContract)
    json["ownership_contract_version"] = 1
    json["owner_state"] = "active"
    json["owner_generation"] = 2
    let owned = try JSONDecoder().decode(
      ArchiveCapability.self, from: JSONSerialization.data(withJSONObject: json))
    try owned.validate(requestID: "request-capability-001")
    #expect(owned.supportsOwnershipContract)
    #expect(owned.ownerState == .active)
    #expect(owned.ownerGeneration == 2)
  }

  @Test("Conditional deletion carries generation without storing uploader proof")
  func conditionalGeneration() throws {
    var json = try fixtureObject("archive-batch-v2")
    json["samples"] = []
    json["deletions"] = ["bd085ccc-22f4-4e80-a865-149bb5b0d1d4"]
    json["expected_inventory_revision"] = 4
    json["expected_owner_generation"] = 2
    let data = try JSONSerialization.data(withJSONObject: json)
    let batch = try ArchiveBatch.decodeValidated(data)
    #expect(batch.expectedOwnerGeneration == 2)
    let encoded = try JSONEncoder().encode(batch)
    try expectSameJSON(data, encoded)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("uploader_credential"))
  }

  @Test func schemaTwoAndConditionalDeletionAreSupportedWithoutFutureVersions() throws {
    var capability = try fixtureObject("archive-capability-v2")["response"] as! [String: Any]
    capability["archive_schema_version"] = 2
    let supported = try JSONDecoder().decode(
      ArchiveCapability.self, from: JSONSerialization.data(withJSONObject: capability))
    try supported.validate(requestID: "request-capability-001")
    capability["protocol_version"] = 3
    let future = try JSONDecoder().decode(
      ArchiveCapability.self, from: JSONSerialization.data(withJSONObject: capability))
    #expect(throws: (any Error).self) { try future.validate(requestID: "request-capability-001") }

    var batch = try fixtureObject("archive-batch-v2")
    batch["samples"] = []
    batch["deletions"] = ["bd085ccc-22f4-4e80-a865-149bb5b0d1d4"]
    batch["expected_inventory_revision"] = Int64.max
    let data = try JSONSerialization.data(withJSONObject: batch)
    try expectSameJSON(data, JSONEncoder().encode(ArchiveBatch.decodeValidated(data)))
    for invalid: Any in [-1, NSNull(), "1", true] {
      batch["expected_inventory_revision"] = invalid
      #expect(throws: (any Error).self) {
        try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: batch))
      }
    }
  }

  @Test("Rejects missing or extra response fields")
  func strictResponses() throws {
    for (name, key) in [
      ("archive-capability-v2", "archive_available"),
      ("archive-ack-v2", "archive_commit"),
      ("archive-status-v2", "metrics"),
    ] {
      var json = try fixtureObject(name)
      if let wrapped = json["response"] as? [String: Any] { json = wrapped }
      json.removeValue(forKey: key)
      json["unexpected"] = true
      let data = try JSONSerialization.data(withJSONObject: json)
      switch name {
      case "archive-capability-v2":
        #expect(throws: (any Error).self) {
          _ = try JSONDecoder().decode(ArchiveCapability.self, from: data)
        }
      case "archive-ack-v2":
        #expect(throws: (any Error).self) {
          _ = try JSONDecoder().decode(ArchiveAcknowledgement.self, from: data)
        }
      default:
        #expect(throws: (any Error).self) {
          _ = try JSONDecoder().decode(ArchiveProjectionStatus.self, from: data)
        }
      }
    }

    var status = try fixtureObject("archive-status-v2")["response"] as! [String: Any]
    status["metrics"] = [["metric": "steps", "state": "pending"]]
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(
        ArchiveProjectionStatus.self, from: JSONSerialization.data(withJSONObject: status))
    }
  }

  @Test("Rejects invalid batch type, duplicate IDs and byte ceiling")
  func invalidBatches() throws {
    var json = try fixtureObject("archive-batch-v2")
    json["sample_type"] = "HKWorkoutTypeIdentifier"
    let badType = try JSONDecoder().decode(
      ArchiveBatch.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: (any Error).self) { try badType.validate() }

    json = try fixtureObject("archive-batch-v2")
    let sample = (json["samples"] as! [[String: Any]])[0]
    json["deletions"] = [sample["uuid"]!]
    let duplicate = try JSONDecoder().decode(
      ArchiveBatch.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: (any Error).self) { try duplicate.validate() }

    json = try fixtureObject("archive-batch-v2")
    json["padding"] = String(repeating: "x", count: 262_144)
    #expect(throws: (any Error).self) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: json))
    }
  }

  @Test("Deletion-only batch uses typed tombstones and round trips")
  func deletionBatch() throws {
    var json = try fixtureObject("archive-batch-v2")
    let sample = (json["samples"] as! [[String: Any]])[0]
    json["samples"] = []
    json["deletions"] = [sample["uuid"]!]
    let data = try JSONSerialization.data(withJSONObject: json)
    let batch = try ArchiveBatch.decodeValidated(data)
    #expect(batch.deletions.first?.uuid == "bd085ccc-22f4-4e80-a865-149bb5b0d1d4")
    try expectSameJSON(data, JSONEncoder().encode(batch))
  }

  @Test("Rejects unknown fields and equal instants written with different precision")
  func strictBatch() throws {
    var json = try fixtureObject("archive-batch-v2")
    json["unexpected"] = true
    #expect(throws: (any Error).self) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: json))
    }

    json = try fixtureObject("archive-batch-v2")
    var coverage = json["coverage"] as! [String: Any]
    coverage["start"] = "2024-01-01T00:00:00Z"
    coverage["end"] = "2024-01-01T00:00:00.0Z"
    json["coverage"] = coverage
    #expect(throws: (any Error).self) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: json))
    }

    json = try fixtureObject("archive-batch-v2")
    var samples = json["samples"] as! [[String: Any]]
    var source = samples[0]["source"] as! [String: Any]
    source["extra"] = "unexpected"
    samples[0]["source"] = source
    json["samples"] = samples
    #expect(throws: (any Error).self) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: json))
    }

    json = try fixtureObject("archive-batch-v2")
    samples = json["samples"] as! [[String: Any]]
    var payload = samples[0]["payload"] as! [String: Any]
    payload["extra"] = "unexpected"
    samples[0]["payload"] = payload
    json["samples"] = samples
    #expect(throws: (any Error).self) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: json))
    }
  }

  @Test("Category and workout payloads retain their own wire shapes")
  func otherPayloads() throws {
    for (type, payload) in [
      (
        "HKCategoryTypeIdentifierSleepAnalysis",
        [
          "kind": "category", "schema_version": 1, "value": 3,
        ] as [String: Any]
      ),
      (
        "HKWorkoutType",
        [
          "kind": "workout", "schema_version": 1, "activity_type": "running",
          "duration_seconds": 1800, "total_energy": ["value": 200, "unit": "kcal"],
          "detail": ["indoor": false],
        ] as [String: Any]
      ),
    ] {
      var json = try fixtureObject("archive-batch-v2")
      json["sample_type"] = type
      var samples = json["samples"] as! [[String: Any]]
      samples[0]["payload"] = payload
      json["samples"] = samples
      let data = try JSONSerialization.data(withJSONObject: json)
      let batch = try ArchiveBatch.decodeValidated(data)
      try expectSameJSON(data, JSONEncoder().encode(batch))
    }
  }

  @Test("Present workout detail must be an object")
  func invalidWorkoutOptional() throws {
    var json = try fixtureObject("archive-batch-v2")
    json["sample_type"] = "HKWorkoutType"
    var samples = json["samples"] as! [[String: Any]]
    samples[0]["payload"] =
      [
        "kind": "workout", "schema_version": 1, "activity_type": "running",
        "duration_seconds": 1800, "detail": NSNull(),
      ] as [String: Any]
    json["samples"] = samples
    #expect(throws: (any Error).self) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: json))
    }
  }

  private func fixtureObject(_ name: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: fixtureData(named: name)) as? [String: Any])
  }

  private func expectSameJSON(_ left: Data, _ right: Data) throws {
    let leftObject = try JSONSerialization.jsonObject(with: left) as! NSDictionary
    let rightObject = try JSONSerialization.jsonObject(with: right) as! NSDictionary
    #expect(leftObject == rightObject)
  }
}
