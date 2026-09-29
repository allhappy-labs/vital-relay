import Foundation

public enum BackfillRequestValidationError: Error, Sendable, Equatable {
  case blankToken
  case invalidUserID
  case invalidRequestID
  case emptyData
  case duplicateMetric
  case ineligibleMetric
  case invalidPointCount
  case tooManyPoints
  case nonFiniteValue
  case invalidTimeWindow
  case futureTimestamp
}

public struct BackfillPoint: Encodable, Sendable, Equatable {
  public let timestamp: Date
  public let value: Double

  public init(timestamp: Date, value: Double) {
    self.timestamp = timestamp
    self.value = value
  }

  enum CodingKeys: String, CodingKey {
    case timestamp
    case value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(ISO8601DateFormatter().string(from: timestamp), forKey: .timestamp)
    try container.encode(value, forKey: .value)
  }
}

public struct BackfillSeries: Sendable, Equatable {
  public let metricID: MetricID
  public let points: [BackfillPoint]

  public init(metricID: MetricID, points: [BackfillPoint]) {
    self.metricID = metricID
    self.points = points
  }
}

public struct BackfillRequest: Encodable, Sendable, Equatable {
  public static let protocolVersion = 1
  public static let maximumPointsPerEntity = 721
  public static let maximumTotalPoints = 2_500
  public static let maximumAge: TimeInterval = (14 * 24 * 60 * 60) + (15 * 60)
  public static let maximumFutureSkew: TimeInterval = 5 * 60

  public let token: String
  public let userID: String
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let data: [String: [BackfillPoint]]

  public init(
    token: String,
    userID: String,
    requestID: String,
    series: [BackfillSeries],
    now: Date = Date()
  ) throws {
    guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw BackfillRequestValidationError.blankToken
    }
    guard !userID.isEmpty, userID.count <= 128 else {
      throw BackfillRequestValidationError.invalidUserID
    }
    guard RequestIDGenerator.isValid(requestID) else {
      throw BackfillRequestValidationError.invalidRequestID
    }
    guard !series.isEmpty else { throw BackfillRequestValidationError.emptyData }

    var encodedData: [String: [BackfillPoint]] = [:]
    var totalPoints = 0
    for item in series {
      guard encodedData[item.metricID.rawValue] == nil else {
        throw BackfillRequestValidationError.duplicateMetric
      }
      guard Self.isEligible(item.metricID) else {
        throw BackfillRequestValidationError.ineligibleMetric
      }
      guard (2...Self.maximumPointsPerEntity).contains(item.points.count) else {
        throw BackfillRequestValidationError.invalidPointCount
      }
      totalPoints += item.points.count
      guard totalPoints <= Self.maximumTotalPoints else {
        throw BackfillRequestValidationError.tooManyPoints
      }
      guard item.points.allSatisfy({ $0.value.isFinite }) else {
        throw BackfillRequestValidationError.nonFiniteValue
      }
      let dates = item.points.map(\.timestamp)
      guard let earliest = dates.min(), let latest = dates.max(),
        latest.timeIntervalSince(earliest) <= Self.maximumAge,
        now.timeIntervalSince(earliest) <= Self.maximumAge
      else {
        throw BackfillRequestValidationError.invalidTimeWindow
      }
      guard latest.timeIntervalSince(now) <= Self.maximumFutureSkew else {
        throw BackfillRequestValidationError.futureTimestamp
      }
      encodedData[item.metricID.rawValue] = item.points
    }

    self.token = token
    self.userID = userID
    requestType = "backfill"
    protocolVersion = Self.protocolVersion
    self.requestID = requestID
    data = encodedData
  }

  private static func isEligible(_ metricID: MetricID) -> Bool {
    guard let definition = MetricRegistry[metricID] else { return false }
    return definition.availability == .available && definition.bridgeUnit != .none
      && definition.bridgeUnit != .unixSeconds
      && definition.aggregation != .latestWorkout
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
