import Foundation

public struct BackfillCheckpoint: Codable, Sendable, Equatable {
  public let metricID: MetricID
  public let windowStart: Date
  public let committedThrough: Date
  public let requestID: String

  public init(
    metricID: MetricID,
    windowStart: Date,
    committedThrough: Date,
    requestID: String
  ) {
    self.metricID = metricID
    self.windowStart = windowStart
    self.committedThrough = committedThrough
    self.requestID = requestID
  }
}

public struct BackfillState: Codable, Sendable, Equatable {
  public var capability: BackfillCapability
  public var checkpoints: [MetricID: BackfillCheckpoint]

  public init(
    capability: BackfillCapability = .unprobed,
    checkpoints: [MetricID: BackfillCheckpoint] = [:]
  ) {
    self.capability = capability
    self.checkpoints = checkpoints
  }
}

public enum BackfillCheckpointStoreError: Error, Sendable, Equatable {
  case unsupportedVersion
  case corruptedData
}

public protocol BackfillCheckpointStore: Sendable {
  func load() async throws -> BackfillState
  func save(_ state: BackfillState) async throws
  func reset() async throws
}

public enum BackfillCheckpointCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ state: BackfillState) throws -> Data {
    try validate(state)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return try encoder.encode(Document(version: currentVersion, state: state))
    } catch {
      throw BackfillCheckpointStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> BackfillState {
    do {
      let decoder = JSONDecoder()
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw BackfillCheckpointStoreError.unsupportedVersion
      }
      let state = try decoder.decode(Document.self, from: data).state
      try validate(state)
      return state
    } catch let error as BackfillCheckpointStoreError {
      throw error
    } catch {
      throw BackfillCheckpointStoreError.corruptedData
    }
  }

  private static func validate(_ state: BackfillState) throws {
    for (metricID, checkpoint) in state.checkpoints {
      guard metricID == checkpoint.metricID,
        checkpoint.windowStart <= checkpoint.committedThrough,
        RequestIDGenerator.isValid(checkpoint.requestID)
      else { throw BackfillCheckpointStoreError.corruptedData }
    }
  }

  private struct Header: Decodable { let version: Int }
  private struct Document: Codable {
    let version: Int
    let state: BackfillState
  }
}

public actor InMemoryBackfillCheckpointStore: BackfillCheckpointStore {
  private var state: BackfillState

  public init(state: BackfillState = BackfillState()) {
    self.state = state
  }

  public func load() throws -> BackfillState {
    try Task.checkCancellation()
    return state
  }

  public func save(_ state: BackfillState) throws {
    try Task.checkCancellation()
    _ = try BackfillCheckpointCodec.encode(state)
    self.state = state
  }

  public func reset() throws {
    try Task.checkCancellation()
    state = BackfillState()
  }
}
