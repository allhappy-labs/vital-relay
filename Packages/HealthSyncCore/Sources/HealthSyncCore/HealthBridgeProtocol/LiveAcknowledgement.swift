public enum LiveAcknowledgementValidationError: Error, Equatable, Sendable {
  case notOK
  case notApplied
  case unexpectedRequestType
  case unsupportedProtocol
  case requestIDMismatch
  case unexpectedCounts
}

public enum LiveBatchResult: Sendable, Equatable {
  case applied
  case partial
}

public struct LiveAcknowledgement: Decodable, Sendable, Equatable {
  public let ok: Bool
  public let applied: Bool
  public let integrationVersion: String?
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let receivedEntities: Int
  public let updatedEntities: Int
  public let skippedEntities: Int
  public let lastSyncUpdated: Bool?
  public let error: String?

  private func validateIdentity(requestID expectedRequestID: String) throws {
    guard ok else {
      throw LiveAcknowledgementValidationError.notOK
    }
    guard applied else {
      throw LiveAcknowledgementValidationError.notApplied
    }
    guard requestType == "live" else {
      throw LiveAcknowledgementValidationError.unexpectedRequestType
    }
    guard protocolVersion == LiveRequest.protocolVersion else {
      throw LiveAcknowledgementValidationError.unsupportedProtocol
    }
    guard requestID == expectedRequestID else {
      throw LiveAcknowledgementValidationError.requestIDMismatch
    }
  }

  public func validate(requestID expectedRequestID: String) throws {
    try validateIdentity(requestID: expectedRequestID)
    guard receivedEntities == 1, updatedEntities == 1, skippedEntities == 0 else {
      throw LiveAcknowledgementValidationError.unexpectedCounts
    }
  }

  public func validateMedications(
    requestID expectedRequestID: String,
    medicationCount: Int
  ) throws {
    try validateIdentity(requestID: expectedRequestID)
    guard medicationCount > 0, receivedEntities == 1,
      updatedEntities == medicationCount, skippedEntities == 0
    else { throw LiveAcknowledgementValidationError.unexpectedCounts }
  }

  public func batchResult(
    requestID expectedRequestID: String,
    entryCount: Int
  ) throws -> LiveBatchResult {
    try validateIdentity(requestID: expectedRequestID)
    guard entryCount > 0 else { throw LiveAcknowledgementValidationError.unexpectedCounts }
    return receivedEntities == entryCount && updatedEntities == entryCount && skippedEntities == 0
      ? .applied : .partial
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case applied
    case integrationVersion = "integration_version"
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case receivedEntities = "received_entities"
    case updatedEntities = "updated_entities"
    case skippedEntities = "skipped_entities"
    case lastSyncUpdated = "last_sync_updated"
    case error
  }
}

public struct WebhookConnectionAcknowledgement: Decodable, Sendable, Equatable {
  public let ok: Bool
  public let integrationVersion: String?
  public let backfillProtocol: Int
  public let backfillAcknowledgement: String
  public let statisticsPolicy: String

  public init(
    ok: Bool,
    integrationVersion: String?,
    backfillProtocol: Int,
    backfillAcknowledgement: String,
    statisticsPolicy: String
  ) {
    self.ok = ok
    self.integrationVersion = integrationVersion
    self.backfillProtocol = backfillProtocol
    self.backfillAcknowledgement = backfillAcknowledgement
    self.statisticsPolicy = statisticsPolicy
  }

  public func validate() throws {
    guard ok,
      backfillProtocol == 1,
      backfillAcknowledgement == "committed",
      statisticsPolicy == "history_only"
    else {
      throw LiveAcknowledgementValidationError.notOK
    }
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case integrationVersion = "integration_version"
    case backfillProtocol = "backfill_protocol"
    case backfillAcknowledgement = "backfill_ack"
    case statisticsPolicy = "statistics_policy"
  }
}
