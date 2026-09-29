import Foundation

public struct MedicationCheckpoint: Codable, Sendable, Equatable {
  public let anchor: Data?
  public let medicationIDs: [String]
  public let sourceFingerprint: String

  public init(anchor: Data?, medicationIDs: [String], sourceFingerprint: String) {
    self.anchor = anchor
    self.medicationIDs = medicationIDs.sorted()
    self.sourceFingerprint = sourceFingerprint
  }
}

public protocol MedicationCheckpointStore: Sendable {
  func load() async throws -> MedicationCheckpoint?
  func save(_ checkpoint: MedicationCheckpoint) async throws
  func reset() async throws
}

public enum MedicationCheckpointStoreError: Error, Sendable, Equatable {
  case unsupportedVersion
  case corruptedData
}

public enum MedicationCheckpointCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ checkpoint: MedicationCheckpoint) throws -> Data {
    try validate(checkpoint)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return try encoder.encode(Document(version: currentVersion, checkpoint: checkpoint))
    } catch {
      throw MedicationCheckpointStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> MedicationCheckpoint {
    do {
      let decoder = JSONDecoder()
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw MedicationCheckpointStoreError.unsupportedVersion
      }
      let checkpoint = try decoder.decode(Document.self, from: data).checkpoint
      try validate(checkpoint)
      return checkpoint
    } catch let error as MedicationCheckpointStoreError {
      throw error
    } catch {
      throw MedicationCheckpointStoreError.corruptedData
    }
  }

  private static func validate(_ checkpoint: MedicationCheckpoint) throws {
    guard !checkpoint.sourceFingerprint.isEmpty,
      checkpoint.sourceFingerprint.count <= 128,
      Set(checkpoint.medicationIDs).count == checkpoint.medicationIDs.count,
      checkpoint.medicationIDs.allSatisfy(MedicationIdentifier.isValid)
    else { throw MedicationCheckpointStoreError.corruptedData }
  }

  private struct Header: Decodable { let version: Int }
  private struct Document: Codable {
    let version: Int
    let checkpoint: MedicationCheckpoint
  }
}

public actor InMemoryMedicationCheckpointStore: MedicationCheckpointStore {
  private var checkpoint: MedicationCheckpoint?

  public init(checkpoint: MedicationCheckpoint? = nil) {
    self.checkpoint = checkpoint
  }

  public func load() throws -> MedicationCheckpoint? {
    try Task.checkCancellation()
    return checkpoint
  }

  public func save(_ checkpoint: MedicationCheckpoint) throws {
    try Task.checkCancellation()
    _ = try MedicationCheckpointCodec.encode(checkpoint)
    self.checkpoint = checkpoint
  }

  public func reset() throws {
    try Task.checkCancellation()
    checkpoint = nil
  }
}
