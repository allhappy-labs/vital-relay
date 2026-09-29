import Foundation

public struct ArchiveMetricProjectionStatus: Codable, Sendable, Equatable {
  public let metric: String
  public let state: String
  public let lastError: String?

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(decoder, required: ["metric", "state", "last_error"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    metric = try values.decode(String.self, forKey: .metric)
    state = try values.decode(String.self, forKey: .state)
    lastError = try values.decodeIfPresent(String.self, forKey: .lastError)
  }

  func validate() throws {
    guard ArchiveWire.validID(metric), ArchiveProjectionState(rawValue: state) != nil,
      lastError == nil || lastError!.count <= 256
    else { throw ArchiveValidationError.invalidResponse }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(metric, forKey: .metric)
    try container.encode(state, forKey: .state)
    try container.encode(lastError, forKey: .lastError)
  }

  enum CodingKeys: String, CodingKey {
    case metric, state
    case lastError = "last_error"
  }
}

public struct ArchiveProjectionStatus: Codable, Sendable, Equatable {
  public let ok: Bool
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let metrics: [ArchiveMetricProjectionStatus]

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder, required: ["ok", "request_type", "protocol_version", "request_id", "metrics"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    ok = try values.decode(Bool.self, forKey: .ok)
    requestType = try values.decode(String.self, forKey: .requestType)
    protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
    requestID = try values.decode(String.self, forKey: .requestID)
    metrics = try values.decode([ArchiveMetricProjectionStatus].self, forKey: .metrics)
  }

  public func validate(requestID expectedRequestID: String) throws {
    guard ok, requestType == "archive_status", protocolVersion == 2,
      ArchiveWire.validID(requestID), requestID == expectedRequestID,
      metrics.count <= 256, Set(metrics.map(\.metric)).count == metrics.count
    else { throw ArchiveValidationError.invalidResponse }
    for metric in metrics { try metric.validate() }
  }

  enum CodingKeys: String, CodingKey {
    case ok, metrics
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
  }
}
