import Foundation

public enum ArchiveValidationError: Error, Sendable, Equatable {
  case invalidRequest
  case invalidSample
  case invalidResponse
  case limitExceeded
}

enum ArchiveWire {
  private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }

  static func requireKeys(
    _ decoder: any Decoder, required: Set<String>, optional: Set<String> = [],
    error: ArchiveValidationError = .invalidResponse
  ) throws {
    let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
      throw error
    }
  }

  static func validID(_ value: String) -> Bool { RequestIDGenerator.isValid(value) }

  static func validType(_ value: String) -> Bool {
    value == "HKWorkoutType"
      || value.range(
        of: "^HK(Quantity|Category)TypeIdentifier[A-Za-z0-9]{1,96}$",
        options: .regularExpression) != nil
  }

  static func validText(_ value: String, max: Int = 256) -> Bool {
    !value.isEmpty && value.count <= max
      && !value.unicodeScalars.contains {
        CharacterSet.controlCharacters.contains($0)
      }
  }

  static func utcDate(_ value: String) -> Date? {
    guard
      value.range(
        of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?Z$",
        options: .regularExpression) != nil
    else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let separator = value.firstIndex(of: ".") else { return formatter.date(from: value) }
    // ISO8601DateFormatter truncates fractional seconds to milliseconds. Parse
    // the wire's permitted microseconds separately to retain boundary ordering.
    let wholeSeconds = String(value[..<separator]) + "Z"
    let digits = value[value.index(after: separator)..<value.index(before: value.endIndex)]
    guard let date = formatter.date(from: wholeSeconds), let fraction = Double("0." + digits)
    else { return nil }
    return date.addingTimeInterval(fraction)
  }

  static func validUTC(_ value: String) -> Bool { utcDate(value) != nil }

  static func encodedBytes<T: Encodable>(_ value: T) throws -> Int {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value).count
  }

  static func validUUID(_ value: String) -> Bool {
    value.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value.lowercased()
  }
}

public struct ArchiveSource: Codable, Sendable, Equatable {
  public let bundleID: String
  public let name: String
  public let revision: String

  public init(bundleID: String, name: String, revision: String) {
    self.bundleID = bundleID
    self.name = name
    self.revision = revision
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder, required: ["bundle_id", "name", "revision"], error: .invalidSample)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    bundleID = try values.decode(String.self, forKey: .bundleID)
    name = try values.decode(String.self, forKey: .name)
    revision = try values.decode(String.self, forKey: .revision)
  }

  func validate() throws {
    guard ArchiveWire.validText(bundleID), ArchiveWire.validText(name),
      ArchiveWire.validText(revision)
    else { throw ArchiveValidationError.invalidSample }
  }

  enum CodingKeys: String, CodingKey {
    case bundleID = "bundle_id"
    case name, revision
  }
}

public struct ArchiveDevice: Codable, Sendable, Equatable {
  public let manufacturer: String?
  public let model: String?
  public let name: String?
  public let hardwareVersion: String?
  public let softwareVersion: String?

  public init(
    manufacturer: String? = nil, model: String? = nil, name: String? = nil,
    hardwareVersion: String? = nil, softwareVersion: String? = nil
  ) {
    self.manufacturer = manufacturer
    self.model = model
    self.name = name
    self.hardwareVersion = hardwareVersion
    self.softwareVersion = softwareVersion
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder, required: [],
      optional: [
        "manufacturer", "model", "name", "hardware_version", "software_version",
      ], error: .invalidSample)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    manufacturer =
      try values.contains(.manufacturer)
      ? values.decode(String.self, forKey: .manufacturer) : nil
    model = try values.contains(.model) ? values.decode(String.self, forKey: .model) : nil
    name = try values.contains(.name) ? values.decode(String.self, forKey: .name) : nil
    hardwareVersion =
      try values.contains(.hardwareVersion)
      ? values.decode(String.self, forKey: .hardwareVersion) : nil
    softwareVersion =
      try values.contains(.softwareVersion)
      ? values.decode(String.self, forKey: .softwareVersion) : nil
  }

  func validate() throws {
    for value in [manufacturer, model, name, hardwareVersion, softwareVersion].compactMap({ $0 }) {
      guard ArchiveWire.validText(value) else { throw ArchiveValidationError.invalidSample }
    }
  }

  enum CodingKeys: String, CodingKey {
    case manufacturer, model, name
    case hardwareVersion = "hardware_version"
    case softwareVersion = "software_version"
  }
}

public struct ArchiveQuantityPayload: Codable, Sendable, Equatable {
  public let kind: String
  public let schemaVersion: Int
  public let rawValue: Double
  public let rawUnit: String
  public let canonicalValue: Double
  public let canonicalUnit: String

  public init(rawValue: Double, rawUnit: String, canonicalValue: Double, canonicalUnit: String) {
    kind = "quantity"
    schemaVersion = 1
    self.rawValue = rawValue
    self.rawUnit = rawUnit
    self.canonicalValue = canonicalValue
    self.canonicalUnit = canonicalUnit
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: [
        "kind", "schema_version", "raw_value", "raw_unit", "canonical_value", "canonical_unit",
      ], error: .invalidSample)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(String.self, forKey: .kind)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    rawValue = try values.decode(Double.self, forKey: .rawValue)
    rawUnit = try values.decode(String.self, forKey: .rawUnit)
    canonicalValue = try values.decode(Double.self, forKey: .canonicalValue)
    canonicalUnit = try values.decode(String.self, forKey: .canonicalUnit)
  }

  func validate() throws {
    guard kind == "quantity", schemaVersion == 1, rawValue.isFinite,
      canonicalValue.isFinite, ArchiveWire.validText(rawUnit),
      ArchiveWire.validText(canonicalUnit)
    else { throw ArchiveValidationError.invalidSample }
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case schemaVersion = "schema_version"
    case rawValue = "raw_value"
    case rawUnit = "raw_unit"
    case canonicalValue = "canonical_value"
    case canonicalUnit = "canonical_unit"
  }
}

public struct ArchiveCategoryPayload: Codable, Sendable, Equatable {
  public let kind: String
  public let schemaVersion: Int
  public let value: Int

  public init(value: Int) {
    kind = "category"
    schemaVersion = 1
    self.value = value
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder, required: ["kind", "schema_version", "value"], error: .invalidSample)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(String.self, forKey: .kind)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    value = try values.decode(Int.self, forKey: .value)
  }

  func validate() throws {
    guard kind == "category", schemaVersion == 1, (0...Int(Int32.max)).contains(value)
    else { throw ArchiveValidationError.invalidSample }
  }

  enum CodingKeys: String, CodingKey {
    case kind, value
    case schemaVersion = "schema_version"
  }
}

public struct ArchiveWorkoutQuantity: Codable, Sendable, Equatable {
  public let value: Double
  public let unit: String

  public init(value: Double, unit: String) {
    self.value = value
    self.unit = unit
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(decoder, required: ["value", "unit"], error: .invalidSample)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    value = try values.decode(Double.self, forKey: .value)
    unit = try values.decode(String.self, forKey: .unit)
  }

  func validate() throws {
    guard value.isFinite, ArchiveWire.validText(unit) else {
      throw ArchiveValidationError.invalidSample
    }
  }
}

public struct ArchiveWorkoutPayload: Codable, Sendable, Equatable {
  public let kind: String
  public let schemaVersion: Int
  public let activityType: String
  public let durationSeconds: Double
  public let totalEnergy: ArchiveWorkoutQuantity?
  public let totalDistance: ArchiveWorkoutQuantity?
  public let detail: [String: JSONValue]?

  public init(
    activityType: String, durationSeconds: Double,
    totalEnergy: ArchiveWorkoutQuantity? = nil,
    totalDistance: ArchiveWorkoutQuantity? = nil,
    detail: [String: JSONValue]? = nil
  ) {
    kind = "workout"
    schemaVersion = 1
    self.activityType = activityType
    self.durationSeconds = durationSeconds
    self.totalEnergy = totalEnergy
    self.totalDistance = totalDistance
    self.detail = detail
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: ["kind", "schema_version", "activity_type", "duration_seconds"],
      optional: ["total_energy", "total_distance", "detail"], error: .invalidSample)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(String.self, forKey: .kind)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    activityType = try values.decode(String.self, forKey: .activityType)
    durationSeconds = try values.decode(Double.self, forKey: .durationSeconds)
    totalEnergy =
      try values.contains(.totalEnergy)
      ? values.decode(ArchiveWorkoutQuantity.self, forKey: .totalEnergy) : nil
    totalDistance =
      try values.contains(.totalDistance)
      ? values.decode(ArchiveWorkoutQuantity.self, forKey: .totalDistance) : nil
    detail =
      try values.contains(.detail)
      ? values.decode([String: JSONValue].self, forKey: .detail) : nil
  }

  func validate() throws {
    guard kind == "workout", schemaVersion == 1, ArchiveWire.validText(activityType),
      durationSeconds.isFinite, durationSeconds >= 0
    else { throw ArchiveValidationError.invalidSample }
    try totalEnergy?.validate()
    try totalDistance?.validate()
    if let detail, try ArchiveWire.encodedBytes(detail) > 8_192 {
      throw ArchiveValidationError.limitExceeded
    }
  }

  enum CodingKeys: String, CodingKey {
    case kind, detail
    case schemaVersion = "schema_version"
    case activityType = "activity_type"
    case durationSeconds = "duration_seconds"
    case totalEnergy = "total_energy"
    case totalDistance = "total_distance"
  }
}

public enum ArchiveSamplePayload: Codable, Sendable, Equatable {
  case quantity(ArchiveQuantityPayload)
  case category(ArchiveCategoryPayload)
  case workout(ArchiveWorkoutPayload)

  public init(from decoder: any Decoder) throws {
    let kind = try decoder.container(keyedBy: KindKey.self).decode(String.self, forKey: .kind)
    switch kind {
    case "quantity": self = .quantity(try ArchiveQuantityPayload(from: decoder))
    case "category": self = .category(try ArchiveCategoryPayload(from: decoder))
    case "workout": self = .workout(try ArchiveWorkoutPayload(from: decoder))
    default: throw ArchiveValidationError.invalidSample
    }
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .quantity(let value): try value.encode(to: encoder)
    case .category(let value): try value.encode(to: encoder)
    case .workout(let value): try value.encode(to: encoder)
    }
  }

  func validate(sampleType: String) throws {
    switch (self, sampleType) {
    case (.quantity(let value), let type) where type.hasPrefix("HKQuantity"):
      try value.validate()
    case (.category(let value), let type) where type.hasPrefix("HKCategory"):
      try value.validate()
    case (.workout(let value), "HKWorkoutType"):
      try value.validate()
    default: throw ArchiveValidationError.invalidSample
    }
  }

  private enum KindKey: String, CodingKey { case kind }
}

public struct ArchiveSample: Codable, Sendable, Equatable {
  public let uuid: String
  public let start: String
  public let end: String
  public let source: ArchiveSource
  public let timeZone: String
  public let metadata: [String: JSONValue]
  public let payload: ArchiveSamplePayload
  public let device: ArchiveDevice?

  public init(
    uuid: String, start: String, end: String, source: ArchiveSource,
    timeZone: String, metadata: [String: JSONValue], payload: ArchiveSamplePayload,
    device: ArchiveDevice? = nil
  ) {
    self.uuid = uuid
    self.start = start
    self.end = end
    self.source = source
    self.timeZone = timeZone
    self.metadata = metadata
    self.payload = payload
    self.device = device
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: ["uuid", "start", "end", "source", "time_zone", "metadata", "payload"],
      optional: ["device"], error: .invalidSample)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    uuid = try values.decode(String.self, forKey: .uuid)
    start = try values.decode(String.self, forKey: .start)
    end = try values.decode(String.self, forKey: .end)
    source = try values.decode(ArchiveSource.self, forKey: .source)
    timeZone = try values.decode(String.self, forKey: .timeZone)
    metadata = try values.decode([String: JSONValue].self, forKey: .metadata)
    payload = try values.decode(ArchiveSamplePayload.self, forKey: .payload)
    device = try values.decodeIfPresent(ArchiveDevice.self, forKey: .device)
  }

  func validate(sampleType: String) throws {
    guard ArchiveWire.validUUID(uuid), let startDate = ArchiveWire.utcDate(start),
      let endDate = ArchiveWire.utcDate(end), startDate <= endDate,
      ArchiveWire.validText(timeZone, max: 128),
      TimeZone(identifier: timeZone) != nil
    else { throw ArchiveValidationError.invalidSample }
    try source.validate()
    try device?.validate()
    guard try ArchiveWire.encodedBytes(metadata) <= 8_192 else {
      throw ArchiveValidationError.limitExceeded
    }
    try payload.validate(sampleType: sampleType)
  }

  enum CodingKeys: String, CodingKey {
    case uuid, start, end, source, metadata, payload, device
    case timeZone = "time_zone"
  }
}
