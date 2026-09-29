import Foundation

public struct ArchiveCapability: Codable, Sendable, Equatable {
  public let ok: Bool
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let archiveSchemaVersion: Int
  public let maxBatchBytes: Int
  public let maxSamplesPerBatch: Int
  public let maxDeletionsPerBatch: Int
  public let supportedSampleTypes: [String]
  public let supportedMetrics: [String]
  public let archiveAvailable: Bool
  public let statisticsAvailable: Bool
  public let ownershipContractVersion: Int?
  public let ownerState: ArchiveOwnerState?
  public let ownerGeneration: Int?
  public let claimID: String?
  public let fingerprint: String?
  public let expiresAt: String?

  public var supportsOwnershipContract: Bool {
    ownershipContractVersion == 1 && archiveSchemaVersion == 3 && ownerState != nil
      && ownerGeneration != nil
  }

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: [
        "ok", "request_type", "protocol_version", "request_id", "archive_schema_version",
        "max_batch_bytes", "max_samples_per_batch", "max_deletions_per_batch",
        "supported_sample_types", "supported_metrics", "archive_available", "statistics_available",
      ],
      optional: [
        "ownership_contract_version", "owner_state", "owner_generation", "claim_id",
        "fingerprint", "expires_at",
      ])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    ok = try values.decode(Bool.self, forKey: .ok)
    requestType = try values.decode(String.self, forKey: .requestType)
    protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
    requestID = try values.decode(String.self, forKey: .requestID)
    archiveSchemaVersion = try values.decode(Int.self, forKey: .archiveSchemaVersion)
    maxBatchBytes = try values.decode(Int.self, forKey: .maxBatchBytes)
    maxSamplesPerBatch = try values.decode(Int.self, forKey: .maxSamplesPerBatch)
    maxDeletionsPerBatch = try values.decode(Int.self, forKey: .maxDeletionsPerBatch)
    supportedSampleTypes = try values.decode([String].self, forKey: .supportedSampleTypes)
    supportedMetrics = try values.decode([String].self, forKey: .supportedMetrics)
    archiveAvailable = try values.decode(Bool.self, forKey: .archiveAvailable)
    statisticsAvailable = try values.decode(Bool.self, forKey: .statisticsAvailable)
    ownershipContractVersion = try values.decodeIfPresent(
      Int.self, forKey: .ownershipContractVersion)
    ownerState = try values.decodeIfPresent(ArchiveOwnerState.self, forKey: .ownerState)
    ownerGeneration = try values.decodeIfPresent(Int.self, forKey: .ownerGeneration)
    claimID = try values.decodeIfPresent(String.self, forKey: .claimID)
    fingerprint = try values.decodeIfPresent(String.self, forKey: .fingerprint)
    expiresAt = try values.decodeIfPresent(String.self, forKey: .expiresAt)
  }

  public func validate(requestID expectedRequestID: String) throws {
    guard ok, requestType == "archive_capability", protocolVersion == 2,
      ArchiveWire.validID(requestID), requestID == expectedRequestID,
      (1...3).contains(archiveSchemaVersion),
      (1...ArchiveBatch.maximumBytes).contains(maxBatchBytes),
      (1...ArchiveBatch.maximumSamples).contains(maxSamplesPerBatch),
      (1...ArchiveBatch.maximumDeletions).contains(maxDeletionsPerBatch),
      supportedSampleTypes.count <= 256, supportedMetrics.count <= 256,
      Set(supportedSampleTypes).count == supportedSampleTypes.count,
      Set(supportedMetrics).count == supportedMetrics.count,
      supportedSampleTypes.allSatisfy(ArchiveWire.validType),
      supportedMetrics.allSatisfy(ArchiveWire.validID)
    else { throw ArchiveValidationError.invalidResponse }
    if ownershipContractVersion != nil || ownerState != nil || ownerGeneration != nil {
      guard ownershipContractVersion == 1, let ownerState, let ownerGeneration,
        ownerGeneration >= 0
      else { throw ArchiveValidationError.invalidResponse }
      if ownerState == .pending {
        guard let claimID, ArchiveWire.validID(claimID),
          let fingerprint, fingerprint.count == 12,
          fingerprint.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
          let expiresAt, ArchiveWire.validUTC(expiresAt)
        else { throw ArchiveValidationError.invalidResponse }
      } else if claimID != nil || fingerprint != nil || expiresAt != nil {
        throw ArchiveValidationError.invalidResponse
      }
    } else if claimID != nil || fingerprint != nil || expiresAt != nil {
      throw ArchiveValidationError.invalidResponse
    }
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case archiveSchemaVersion = "archive_schema_version"
    case maxBatchBytes = "max_batch_bytes"
    case maxSamplesPerBatch = "max_samples_per_batch"
    case maxDeletionsPerBatch = "max_deletions_per_batch"
    case supportedSampleTypes = "supported_sample_types"
    case supportedMetrics = "supported_metrics"
    case archiveAvailable = "archive_available"
    case statisticsAvailable = "statistics_available"
    case ownershipContractVersion = "ownership_contract_version"
    case ownerState = "owner_state"
    case ownerGeneration = "owner_generation"
    case claimID = "claim_id"
    case fingerprint
    case expiresAt = "expires_at"
  }
}
