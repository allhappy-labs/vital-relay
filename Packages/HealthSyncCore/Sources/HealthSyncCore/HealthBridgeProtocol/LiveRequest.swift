import Foundation

public struct HealthBridgeDataPoint: Encodable, Sendable, Equatable {
  public let timestamp: Date?
  public let value: JSONValue

  public init(timestamp: Date? = nil, value: JSONValue) {
    self.timestamp = timestamp
    self.value = value
  }

  var liveValue: JSONValue {
    var fields = ["value": value]
    if let timestamp {
      fields["timestamp"] = .string(ISO8601DateFormatter().string(from: timestamp))
    }
    return .object(fields)
  }
}

public struct LiveRequest: Encodable, Sendable, Equatable {
  public static let protocolVersion = 1

  public let token: String
  public let userID: String
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let data: [String: JSONValue]

  public init(
    token: String,
    userID: String,
    requestID: String,
    data: [String: [HealthBridgeDataPoint]]
  ) {
    self.token = token
    self.userID = userID
    requestType = "live"
    protocolVersion = Self.protocolVersion
    self.requestID = requestID
    self.data = data.mapValues { .array($0.map(\.liveValue)) }
  }

  public init(
    token: String,
    userID: String,
    requestID: String,
    specialMetric: MetricID,
    value: JSONValue
  ) {
    self.token = token
    self.userID = userID
    requestType = "live"
    protocolVersion = Self.protocolVersion
    self.requestID = requestID
    data = [specialMetric.rawValue: value]
  }

  public init(
    token: String,
    userID: String,
    requestID: String,
    entries: [LiveBatchEntry]
  ) {
    self.token = token
    self.userID = userID
    requestType = "live"
    protocolVersion = Self.protocolVersion
    self.requestID = requestID
    data = Dictionary(entries.map { ($0.key, $0.liveValue) }, uniquingKeysWith: { _, last in last })
  }

  public init(
    token: String,
    userID: String,
    requestID: String,
    medications: MedicationPayload
  ) {
    self.token = token
    self.userID = userID
    requestType = "live"
    protocolVersion = Self.protocolVersion
    self.requestID = requestID
    data = ["medications": .array(medications.records.map(\.liveValue))]
  }

  enum CodingKeys: String, CodingKey {
    case token
    case userID = "user_id"
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case data
  }
}
