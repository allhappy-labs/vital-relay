import Foundation

public struct ArchiveCoverage: Codable, Sendable, Equatable {
  public let kind: String
  public let start: String?
  public let end: String?
  public let anchor: String?
  public let authorizationStart: String?

  public init(
    kind: String, start: String? = nil, end: String? = nil,
    anchor: String? = nil, authorizationStart: String? = nil
  ) {
    self.kind = kind
    self.start = start
    self.end = end
    self.anchor = anchor
    self.authorizationStart = authorizationStart
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(String.self, forKey: .kind)
    if kind == "interval" {
      try ArchiveWire.requireKeys(
        decoder, required: ["kind", "start", "end", "authorization_start"],
        error: .invalidRequest)
      start = try values.decode(String.self, forKey: .start)
      end = try values.decode(String.self, forKey: .end)
      anchor = nil
    } else if kind == "anchor" {
      try ArchiveWire.requireKeys(
        decoder, required: ["kind", "anchor", "authorization_start"],
        error: .invalidRequest)
      start = nil
      end = nil
      anchor = try values.decode(String.self, forKey: .anchor)
    } else {
      throw ArchiveValidationError.invalidRequest
    }
    authorizationStart = try values.decodeIfPresent(String.self, forKey: .authorizationStart)
  }

  func validate() throws {
    if let authorizationStart, !ArchiveWire.validUTC(authorizationStart) {
      throw ArchiveValidationError.invalidRequest
    }
    switch kind {
    case "interval":
      guard let start, let end, anchor == nil,
        let startDate = ArchiveWire.utcDate(start),
        let endDate = ArchiveWire.utcDate(end), startDate < endDate
      else { throw ArchiveValidationError.invalidRequest }
    case "anchor":
      guard start == nil, end == nil, let anchor,
        ArchiveWire.validText(anchor, max: 4_096)
      else { throw ArchiveValidationError.invalidRequest }
    default: throw ArchiveValidationError.invalidRequest
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(authorizationStart, forKey: .authorizationStart)
    if kind == "interval" {
      try container.encode(start, forKey: .start)
      try container.encode(end, forKey: .end)
    } else {
      try container.encode(anchor, forKey: .anchor)
    }
  }

  enum CodingKeys: String, CodingKey {
    case kind, start, end, anchor
    case authorizationStart = "authorization_start"
  }
}

public struct ArchiveDeletion: Codable, Sendable, Equatable {
  public let uuid: String

  public init(uuid: String) { self.uuid = uuid }

  public init(from decoder: any Decoder) throws {
    uuid = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(uuid)
  }
}

public struct ArchiveBatch: Codable, Sendable, Equatable {
  public static let protocolVersion = 2
  public static let maximumBytes = 262_144
  public static let maximumSamples = 200
  public static let maximumDeletions = 200

  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let userID: String
  public let batchID: String
  public let sampleType: String
  public let coverage: ArchiveCoverage
  public let samples: [ArchiveSample]
  public let deletions: [ArchiveDeletion]
  public let expectedInventoryRevision: Int64?
  public let expectedOwnerGeneration: Int?

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: [
        "request_type", "protocol_version", "request_id", "user_id", "batch_id",
        "sample_type", "coverage", "samples", "deletions",
      ], optional: ["expected_inventory_revision", "expected_owner_generation"],
      error: .invalidRequest)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    requestType = try values.decode(String.self, forKey: .requestType)
    protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
    requestID = try values.decode(String.self, forKey: .requestID)
    userID = try values.decode(String.self, forKey: .userID)
    batchID = try values.decode(String.self, forKey: .batchID)
    sampleType = try values.decode(String.self, forKey: .sampleType)
    coverage = try values.decode(ArchiveCoverage.self, forKey: .coverage)
    samples = try values.decode([ArchiveSample].self, forKey: .samples)
    deletions = try values.decode([ArchiveDeletion].self, forKey: .deletions)
    expectedInventoryRevision =
      values.contains(.expectedInventoryRevision)
      ? try values.decode(Int64.self, forKey: .expectedInventoryRevision) : nil
    expectedOwnerGeneration =
      values.contains(.expectedOwnerGeneration)
      ? try values.decode(Int.self, forKey: .expectedOwnerGeneration) : nil
  }

  public init(
    requestID: String, userID: String, batchID: String, sampleType: String,
    coverage: ArchiveCoverage, samples: [ArchiveSample], deletions: [ArchiveDeletion],
    expectedInventoryRevision: Int64? = nil, expectedOwnerGeneration: Int? = nil
  ) {
    requestType = "archive_batch"
    protocolVersion = Self.protocolVersion
    self.requestID = requestID
    self.userID = userID
    self.batchID = batchID
    self.sampleType = sampleType
    self.coverage = coverage
    self.samples = samples
    self.deletions = deletions
    self.expectedInventoryRevision = expectedInventoryRevision
    self.expectedOwnerGeneration = expectedOwnerGeneration
  }

  public func validate(
    maxBytes: Int = maximumBytes, maxSamples: Int = maximumSamples,
    maxDeletions: Int = maximumDeletions
  ) throws {
    guard requestType == "archive_batch", protocolVersion == Self.protocolVersion,
      ArchiveWire.validID(requestID), ArchiveWire.validID(userID),
      ArchiveWire.validID(batchID), ArchiveWire.validType(sampleType),
      !samples.isEmpty || !deletions.isEmpty
    else { throw ArchiveValidationError.invalidRequest }
    if let expectedInventoryRevision {
      guard expectedInventoryRevision >= 0, samples.isEmpty, !deletions.isEmpty else {
        throw ArchiveValidationError.invalidRequest
      }
    }
    if let expectedOwnerGeneration {
      guard expectedOwnerGeneration >= 0, expectedInventoryRevision != nil else {
        throw ArchiveValidationError.invalidRequest
      }
    }
    guard samples.count <= maxSamples, deletions.count <= maxDeletions,
      maxSamples <= Self.maximumSamples, maxDeletions <= Self.maximumDeletions,
      maxBytes <= Self.maximumBytes
    else { throw ArchiveValidationError.limitExceeded }
    try coverage.validate()
    for sample in samples { try sample.validate(sampleType: sampleType) }
    guard deletions.allSatisfy({ ArchiveWire.validUUID($0.uuid) }),
      Set(samples.map { $0.uuid.lowercased() } + deletions.map { $0.uuid.lowercased() }).count
        == samples.count + deletions.count
    else { throw ArchiveValidationError.invalidSample }
    guard try ArchiveWire.encodedBytes(self) <= maxBytes else {
      throw ArchiveValidationError.limitExceeded
    }
  }

  public static func decodeValidated(_ data: Data) throws -> Self {
    guard data.count <= maximumBytes else { throw ArchiveValidationError.limitExceeded }
    let batch = try JSONDecoder().decode(Self.self, from: data)
    try batch.validate()
    return batch
  }

  enum CodingKeys: String, CodingKey {
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case userID = "user_id"
    case batchID = "batch_id"
    case sampleType = "sample_type"
    case coverage, samples, deletions
    case expectedInventoryRevision = "expected_inventory_revision"
    case expectedOwnerGeneration = "expected_owner_generation"
  }
}
