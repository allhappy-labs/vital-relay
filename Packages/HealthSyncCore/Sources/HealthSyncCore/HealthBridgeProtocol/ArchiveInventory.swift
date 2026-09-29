import Foundation

public struct ArchiveInventoryQuery: Codable, Sendable, Equatable {
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let userID: String
  public let sampleType: String
  public let start: String
  public let end: String
  public let limit: Int
  public let cursor: String?

  public init(
    requestID: String, userID: String, sampleType: String, start: String, end: String,
    limit: Int = 200, cursor: String? = nil
  ) {
    requestType = "archive_inventory"
    protocolVersion = 2
    self.requestID = requestID
    self.userID = userID
    self.sampleType = sampleType
    self.start = start
    self.end = end
    self.limit = limit
    self.cursor = cursor
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: [
        "request_type", "protocol_version", "request_id", "user_id",
        "sample_type", "start", "end", "limit", "cursor",
      ], error: .invalidRequest)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    requestType = try values.decode(String.self, forKey: .requestType)
    protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
    requestID = try values.decode(String.self, forKey: .requestID)
    userID = try values.decode(String.self, forKey: .userID)
    sampleType = try values.decode(String.self, forKey: .sampleType)
    start = try values.decode(String.self, forKey: .start)
    end = try values.decode(String.self, forKey: .end)
    limit = try values.decode(Int.self, forKey: .limit)
    cursor = try values.decodeIfPresent(String.self, forKey: .cursor)
  }

  public func validate() throws {
    guard requestType == "archive_inventory", protocolVersion == 2,
      ArchiveWire.validID(requestID), ArchiveWire.validID(userID),
      ArchiveWire.validType(sampleType),
      let lower = ArchiveWire.utcDate(start), let upper = ArchiveWire.utcDate(end), lower < upper,
      (1...200).contains(limit), cursor.map({ ArchiveWire.validText($0, max: 2048) }) ?? true
    else { throw ArchiveValidationError.invalidRequest }
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(requestType, forKey: .requestType)
    try values.encode(protocolVersion, forKey: .protocolVersion)
    try values.encode(requestID, forKey: .requestID)
    try values.encode(userID, forKey: .userID)
    try values.encode(sampleType, forKey: .sampleType)
    try values.encode(start, forKey: .start)
    try values.encode(end, forKey: .end)
    try values.encode(limit, forKey: .limit)
    try values.encode(cursor, forKey: .cursor)
  }

  enum CodingKeys: String, CodingKey {
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case userID = "user_id"
    case sampleType = "sample_type"
    case start, end, limit, cursor
  }
}

public struct ArchiveInventoryPage: Codable, Sendable, Equatable {
  public let ok: Bool
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let sampleIDs: [String]
  public let revision: Int64
  public let ownerGeneration: Int?
  public let nextCursor: String?

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: [
        "ok", "request_type", "protocol_version", "request_id", "sample_ids",
        "revision", "next_cursor",
      ], optional: ["owner_generation"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    ok = try values.decode(Bool.self, forKey: .ok)
    requestType = try values.decode(String.self, forKey: .requestType)
    protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
    requestID = try values.decode(String.self, forKey: .requestID)
    sampleIDs = try values.decode([String].self, forKey: .sampleIDs)
    revision = try values.decode(Int64.self, forKey: .revision)
    ownerGeneration = try values.decodeIfPresent(Int.self, forKey: .ownerGeneration)
    nextCursor = try values.decodeIfPresent(String.self, forKey: .nextCursor)
  }

  public func validate(query: ArchiveInventoryQuery) throws {
    guard ok, requestType == "archive_inventory", protocolVersion == 2,
      requestID == query.requestID, revision >= 0,
      ownerGeneration.map({ $0 >= 0 }) ?? true, sampleIDs.count <= query.limit,
      sampleIDs.allSatisfy(ArchiveWire.validUUID),
      Set(sampleIDs.map { $0.lowercased() }).count == sampleIDs.count,
      nextCursor.map({ ArchiveWire.validText($0, max: 2048) && $0 != query.cursor }) ?? true,
      nextCursor == nil || !sampleIDs.isEmpty
    else { throw ArchiveValidationError.invalidResponse }
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(ok, forKey: .ok)
    try values.encode(requestType, forKey: .requestType)
    try values.encode(protocolVersion, forKey: .protocolVersion)
    try values.encode(requestID, forKey: .requestID)
    try values.encode(sampleIDs, forKey: .sampleIDs)
    try values.encode(revision, forKey: .revision)
    try values.encodeIfPresent(ownerGeneration, forKey: .ownerGeneration)
    try values.encode(nextCursor, forKey: .nextCursor)
  }

  enum CodingKeys: String, CodingKey {
    case ok, revision
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case sampleIDs = "sample_ids"
    case nextCursor = "next_cursor"
    case ownerGeneration = "owner_generation"
  }
}

public protocol ArchiveInventoryFetching: Sendable {
  func page(query: ArchiveInventoryQuery, baseURL: NormalizedBaseURL) async throws
    -> ArchiveInventoryPage
}

public enum ArchiveReconciliationError: Error, Sendable, Equatable {
  case inventoryUnavailable, authorizationUnproven, intervalTooDense, inventoryUnstable
}
