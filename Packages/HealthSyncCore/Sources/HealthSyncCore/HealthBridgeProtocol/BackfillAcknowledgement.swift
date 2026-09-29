public enum BackfillAcknowledgementValidationError: Error, Sendable, Equatable {
  case notOK
  case notCommitted
  case unsupportedProtocol
  case requestIDMismatch
  case unsupportedRecorder
  case unexpectedStatisticsPolicy
  case invalidCounts
}

public struct BackfillAcknowledgement: Decodable, Sendable, Equatable {
  public let ok: Bool
  public let committed: Bool
  public let protocolVersion: Int
  public let requestID: String
  public let recorderSchema: Int
  public let database: String
  public let received: Int
  public let inserted: Int
  public let skipped: Int
  public let entities: Int
  public let statisticsPolicy: String

  public func validate(requestID expectedRequestID: String) throws {
    guard ok else { throw BackfillAcknowledgementValidationError.notOK }
    guard committed else { throw BackfillAcknowledgementValidationError.notCommitted }
    guard protocolVersion == BackfillRequest.protocolVersion else {
      throw BackfillAcknowledgementValidationError.unsupportedProtocol
    }
    guard requestID == expectedRequestID else {
      throw BackfillAcknowledgementValidationError.requestIDMismatch
    }
    guard recorderSchema == 53, database == "sqlite" else {
      throw BackfillAcknowledgementValidationError.unsupportedRecorder
    }
    guard statisticsPolicy == "history_only" else {
      throw BackfillAcknowledgementValidationError.unexpectedStatisticsPolicy
    }
    guard received >= 0, inserted >= 0, skipped >= 0, entities > 0,
      inserted + skipped == received, entities <= received
    else {
      throw BackfillAcknowledgementValidationError.invalidCounts
    }
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case committed
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case recorderSchema = "recorder_schema"
    case database
    case received
    case inserted
    case skipped
    case entities
    case statisticsPolicy = "statistics_policy"
  }
}
