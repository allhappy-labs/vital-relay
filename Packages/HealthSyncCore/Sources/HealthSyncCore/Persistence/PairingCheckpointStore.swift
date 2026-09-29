import Foundation

public enum PairingCheckpointStoreError: Error, Sendable, Equatable {
  case unsupportedVersion
  case corruptedData
}

public protocol PairingCheckpointStore: Sendable {
  func checkpoint(for pairingID: UUID) async throws -> PairingCheckpoint?
  func commit(_ checkpoint: PairingCheckpoint) async throws
  func reset(pairingID: UUID) async throws
  func resetAll() async throws
}

public enum PairingCheckpointCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ checkpoints: [UUID: PairingCheckpoint]) throws -> Data {
    try validate(checkpoints)
    let document = Document(
      version: currentVersion,
      checkpoints: Dictionary(
        uniqueKeysWithValues: checkpoints.map { ($0.key.uuidString.lowercased(), $0.value) }
      )
    )
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(document)
    } catch let error as PairingCheckpointStoreError {
      throw error
    } catch {
      throw PairingCheckpointStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> [UUID: PairingCheckpoint] {
    do {
      let decoder = JSONDecoder()
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw PairingCheckpointStoreError.unsupportedVersion
      }
      let document = try decoder.decode(Document.self, from: data)
      var checkpoints: [UUID: PairingCheckpoint] = [:]
      for (key, checkpoint) in document.checkpoints {
        guard let pairingID = UUID(uuidString: key), pairingID == checkpoint.pairingID else {
          throw PairingCheckpointStoreError.corruptedData
        }
        checkpoints[pairingID] = checkpoint
      }
      try validate(checkpoints)
      return checkpoints
    } catch let error as PairingCheckpointStoreError {
      throw error
    } catch {
      throw PairingCheckpointStoreError.corruptedData
    }
  }

  private static func validate(_ checkpoints: [UUID: PairingCheckpoint]) throws {
    for (pairingID, checkpoint) in checkpoints {
      guard pairingID == checkpoint.pairingID else {
        throw PairingCheckpointStoreError.corruptedData
      }
      try checkpoint.validate()
    }
  }

  private struct Header: Decodable {
    let version: Int
  }

  private struct Document: Codable {
    let version: Int
    let checkpoints: [String: PairingCheckpoint]
  }
}

public actor InMemoryPairingCheckpointStore: PairingCheckpointStore {
  private var checkpoints: [UUID: PairingCheckpoint]

  public init(checkpoints: [UUID: PairingCheckpoint] = [:]) {
    self.checkpoints = checkpoints
  }

  public func checkpoint(for pairingID: UUID) throws -> PairingCheckpoint? {
    try Task.checkCancellation()
    return checkpoints[pairingID]
  }

  public func commit(_ checkpoint: PairingCheckpoint) throws {
    try Task.checkCancellation()
    try checkpoint.validate()
    checkpoints[checkpoint.pairingID] = checkpoint
  }

  public func reset(pairingID: UUID) throws {
    try Task.checkCancellation()
    checkpoints[pairingID] = nil
  }

  public func resetAll() throws {
    try Task.checkCancellation()
    checkpoints.removeAll()
  }
}
