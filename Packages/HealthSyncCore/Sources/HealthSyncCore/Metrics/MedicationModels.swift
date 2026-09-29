import CryptoKit
import Foundation

public enum MedicationDoseStatus: String, Codable, Sendable, Equatable {
  case pending
  case taken
  case skipped
}

public enum MedicationDoseSchedule: String, Codable, Sendable, Equatable {
  case scheduled
  case asNeeded
}

public struct MedicationConcept: Sendable, Equatable {
  public let id: String
  public let name: String?
  public let isArchived: Bool

  public init(id: String, name: String?, isArchived: Bool = false) {
    self.id = id
    self.name = name
    self.isArchived = isArchived
  }
}

public struct MedicationDose: Sendable, Equatable {
  public let id: UUID
  public let medicationID: String
  public let status: MedicationDoseStatus
  public let schedule: MedicationDoseSchedule
  public let doseQuantity: Double?
  public let unit: String?

  public init(
    id: UUID = UUID(),
    medicationID: String,
    status: MedicationDoseStatus,
    schedule: MedicationDoseSchedule,
    doseQuantity: Double? = nil,
    unit: String? = nil
  ) {
    self.id = id
    self.medicationID = medicationID
    self.status = status
    self.schedule = schedule
    self.doseQuantity = doseQuantity
    self.unit = unit
  }
}

public enum MedicationIdentifier: Sendable {
  public static func make(from stableData: Data) -> String {
    let digest = SHA256.hash(data: stableData)
    return "med_" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  public static func fingerprint(_ values: [String]) -> String {
    let canonical = values.sorted().joined(separator: "\u{1F}")
    return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  public static func isValid(_ value: String) -> Bool {
    value.range(of: #"^med_[a-f0-9]{32}$"#, options: .regularExpression) != nil
  }
}
