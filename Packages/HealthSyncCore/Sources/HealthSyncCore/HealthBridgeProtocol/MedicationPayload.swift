import Foundation

public enum MedicationPayloadError: Error, Sendable, Equatable {
  case emptyPayload
  case invalidIdentifier
  case invalidName
  case invalidCounts
  case invalidDose
  case invalidUnit
}

public enum MedicationBridgeState: String, Codable, Sendable, Equatable {
  case pending
  case partial
  case taken
}

public struct MedicationBridgeRecord: Sendable, Equatable {
  public let id: String
  public let state: MedicationBridgeState
  public let name: String?
  public let taken: Int
  public let scheduled: Int
  public let doseTaken: Double?
  public let unit: String?
  public let summary: String

  public init(
    id: String,
    state: MedicationBridgeState,
    name: String?,
    taken: Int,
    scheduled: Int,
    doseTaken: Double?,
    unit: String?,
    summary: String
  ) throws {
    guard MedicationIdentifier.isValid(id) else { throw MedicationPayloadError.invalidIdentifier }
    guard name.map(Self.validText) ?? true else { throw MedicationPayloadError.invalidName }
    guard taken >= 0, scheduled >= 0 else { throw MedicationPayloadError.invalidCounts }
    guard doseTaken.map({ $0.isFinite && $0 >= 0 }) ?? true else {
      throw MedicationPayloadError.invalidDose
    }
    guard unit.map(Self.validUnit) ?? true else { throw MedicationPayloadError.invalidUnit }
    self.id = id
    self.state = state
    self.name = name
    self.taken = taken
    self.scheduled = scheduled
    self.doseTaken = doseTaken
    self.unit = unit
    self.summary = summary
  }

  var liveValue: JSONValue {
    var object: [String: JSONValue] = [
      "id": .string(id),
      "state": .string(state.rawValue),
      "taken": .number(Double(taken)),
      "scheduled": .number(Double(scheduled)),
      "summary": .string(summary),
    ]
    if let name { object["name"] = .string(name) }
    if let doseTaken { object["dose_taken"] = .number(doseTaken) }
    if let unit { object["unit"] = .string(unit) }
    return .object(object)
  }

  private static func validText(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= 128
      && trimmed.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }

  private static func validUnit(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= 32
      && trimmed.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }
}

public struct MedicationPayload: Sendable, Equatable {
  public let records: [MedicationBridgeRecord]

  public init(records: [MedicationBridgeRecord]) throws {
    guard !records.isEmpty else { throw MedicationPayloadError.emptyPayload }
    guard Set(records.map(\.id)).count == records.count else {
      throw MedicationPayloadError.invalidIdentifier
    }
    self.records = records.sorted { $0.id < $1.id }
  }

  public static func aggregate(
    concepts: [MedicationConcept],
    doses: [MedicationDose]
  ) throws -> MedicationPayload {
    let records = try concepts.filter { !$0.isArchived }.map { concept in
      let matching = doses.filter { $0.medicationID == concept.id }
      let scheduled = matching.filter { $0.schedule == .scheduled }.count
      let takenDoses = matching.filter { $0.status == .taken }
      let taken = takenDoses.count
      let state: MedicationBridgeState
      if scheduled == 0 {
        state = taken > 0 ? .taken : .pending
      } else if taken >= scheduled {
        state = .taken
      } else if taken > 0 {
        state = .partial
      } else {
        state = .pending
      }

      let numericDoses = takenDoses.compactMap(\.doseQuantity)
      let doseTaken = numericDoses.isEmpty ? nil : numericDoses.reduce(0, +)
      let units = Set(takenDoses.compactMap(\.unit))
      let unit = units.count == 1 ? units.first : nil
      let summary =
        scheduled > 0 ? "\(taken) of \(scheduled) taken" : "\(taken) taken as needed"
      return try MedicationBridgeRecord(
        id: concept.id,
        state: state,
        name: concept.name,
        taken: taken,
        scheduled: scheduled,
        doseTaken: doseTaken,
        unit: unit,
        summary: summary
      )
    }
    return try MedicationPayload(records: records)
  }
}
