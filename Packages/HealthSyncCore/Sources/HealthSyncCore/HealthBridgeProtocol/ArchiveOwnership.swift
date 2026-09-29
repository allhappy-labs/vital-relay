import Foundation

public enum ArchiveOwnerState: String, Codable, Sendable {
  case unbound
  case pending
  case active
  case notOwner = "not_owner"
}

public struct ArchiveOwnerClaimStatus: Codable, Sendable, Equatable {
  public let ok: Bool
  public let requestType: String
  public let protocolVersion: Int
  public let requestID: String
  public let ownershipContractVersion: Int
  public let ownerState: ArchiveOwnerState
  public let ownerGeneration: Int
  public let claimID: String?
  public let fingerprint: String?
  public let expiresAt: String?

  public init(from decoder: any Decoder) throws {
    try ArchiveWire.requireKeys(
      decoder,
      required: [
        "ok", "request_type", "protocol_version", "request_id",
        "ownership_contract_version", "owner_state", "owner_generation",
      ], optional: ["claim_id", "fingerprint", "expires_at"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    ok = try values.decode(Bool.self, forKey: .ok)
    requestType = try values.decode(String.self, forKey: .requestType)
    protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
    requestID = try values.decode(String.self, forKey: .requestID)
    ownershipContractVersion = try values.decode(Int.self, forKey: .ownershipContractVersion)
    ownerState = try values.decode(ArchiveOwnerState.self, forKey: .ownerState)
    ownerGeneration = try values.decode(Int.self, forKey: .ownerGeneration)
    claimID = try values.decodeIfPresent(String.self, forKey: .claimID)
    fingerprint = try values.decodeIfPresent(String.self, forKey: .fingerprint)
    expiresAt = try values.decodeIfPresent(String.self, forKey: .expiresAt)
  }

  public func validate(requestID expectedRequestID: String) throws {
    guard ok, requestType == "archive_owner_claim", protocolVersion == 2,
      requestID == expectedRequestID, ownershipContractVersion == 1,
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
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case requestType = "request_type"
    case protocolVersion = "protocol_version"
    case requestID = "request_id"
    case ownershipContractVersion = "ownership_contract_version"
    case ownerState = "owner_state"
    case ownerGeneration = "owner_generation"
    case claimID = "claim_id"
    case fingerprint
    case expiresAt = "expires_at"
  }
}
