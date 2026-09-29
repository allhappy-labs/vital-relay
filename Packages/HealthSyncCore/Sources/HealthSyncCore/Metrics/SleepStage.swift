import Foundation

public enum SleepStage: String, Codable, CaseIterable, Sendable {
  case inBed
  case awake
  case asleepUnspecified
  case core
  case deep
  case rem

  public var healthBridgeCode: Int? {
    switch self {
    case .deep: 0
    case .core: 1
    case .rem: 2
    case .awake: 3
    case .asleepUnspecified: -1
    case .inBed: nil
    }
  }

  var isAsleep: Bool {
    switch self {
    case .asleepUnspecified, .core, .deep, .rem: true
    case .inBed, .awake: false
    }
  }
}

public struct SleepInterval: Sendable, Equatable {
  public let id: UUID
  public let stage: SleepStage
  public let start: Date
  public let end: Date
  public let sourceBundleIdentifier: String
  public let isFromThisApplication: Bool

  public init(
    id: UUID = UUID(),
    stage: SleepStage,
    start: Date,
    end: Date,
    sourceBundleIdentifier: String,
    isFromThisApplication: Bool = false
  ) {
    self.id = id
    self.stage = stage
    self.start = start
    self.end = end
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.isFromThisApplication = isFromThisApplication
  }
}
