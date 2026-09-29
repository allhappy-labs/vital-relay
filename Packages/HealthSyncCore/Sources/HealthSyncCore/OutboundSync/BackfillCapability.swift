public enum BackfillIncompatibility: String, Codable, Sendable, Equatable {
  case unsupportedRecorder
  case unsupportedProtocol
  case unsupportedAcknowledgement
  case unsupportedStatisticsPolicy
}

public enum BackfillCapability: Codable, Sendable, Equatable {
  case disabledByUser
  case unprobed
  case available(protocolVersion: Int)
  case incompatible(reason: BackfillIncompatibility)
  case temporarilyUnavailable
}
