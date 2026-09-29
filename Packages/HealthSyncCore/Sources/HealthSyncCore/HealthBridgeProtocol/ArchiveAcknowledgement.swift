import Foundation

public enum ArchiveProjectionState: String, Codable, Sendable {
  case pending, current, failed
}

public struct ArchiveAcknowledgement: Codable, Sendable, Equatable {
  public let ok: Bool
  public let archiveCommit: String
  public let protocolVersion: Int
  public let requestID: String
  public let batchID: String
  public let receivedSamples: Int
  public let committedSamples: Int
  public let receivedDeletions: Int
  public let committedDeletions: Int
  public let projectionState: String

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: [
        "ok", "archive_commit", "protocol_version", "request_id", "batch_id",
        "received_samples", "committed_samples", "received_deletions", "committed_deletions",
        "projection_state",
      ])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    ok = try values.decode(Bool.self, forKey: .ok)
    archiveCommit = try values.decode(String.self, forKey: .archiveCommit)
    protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
    requestID = try values.decode(String.self, forKey: .requestID)
    batchID = try values.decode(String.self, forKey: .batchID)
    receivedSamples = try values.decode(Int.self, forKey: .receivedSamples)
    committedSamples = try values.decode(Int.self, forKey: .committedSamples)
    receivedDeletions = try values.decode(Int.self, forKey: .receivedDeletions)
    committedDeletions = try values.decode(Int.self, forKey: .committedDeletions)
    projectionState = try values.decode(String.self, forKey: .projectionState)
  }

  public func validate(
    requestID expectedRequestID: String, batchID expectedBatchID: String,
    samples: Int, deletions: Int
  ) throws {
    guard ok, archiveCommit == "committed", protocolVersion == 2,
      ArchiveWire.validID(requestID), ArchiveWire.validID(batchID),
      requestID == expectedRequestID, batchID == expectedBatchID,
      receivedSamples == samples, receivedDeletions == deletions,
      (0...receivedSamples).contains(committedSamples),
      (0...receivedDeletions).contains(committedDeletions),
      receivedSamples <= ArchiveBatch.maximumSamples,
      receivedDeletions <= ArchiveBatch.maximumDeletions,
      ArchiveProjectionState(rawValue: projectionState) != nil
    else { throw ArchiveValidationError.invalidResponse }
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case archiveCommit = "archive_commit"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case batchID = "batch_id"
    case receivedSamples = "received_samples"
    case committedSamples = "committed_samples"
    case receivedDeletions = "received_deletions"
    case committedDeletions = "committed_deletions"
    case projectionState = "projection_state"
  }
}
