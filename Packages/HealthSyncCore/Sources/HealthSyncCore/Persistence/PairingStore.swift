import Foundation

public enum PairingStoreError: Error, Sendable, Equatable {
  case unsupportedVersion
  case corruptedData
}

public protocol PairingStore: Sendable {
  func all() async throws -> [Pairing]
  func save(_ pairing: Pairing) async throws
  func delete(id: UUID) async throws
  func deleteAll() async throws
}

public enum PairingCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ pairings: [Pairing]) throws -> Data {
    try validate(pairings)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return try encoder.encode(Document(version: currentVersion, pairings: ordered(pairings)))
    } catch let error as PairingValidationError {
      throw error
    } catch {
      throw PairingStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> [Pairing] {
    let decoder = JSONDecoder()
    do {
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw PairingStoreError.unsupportedVersion
      }
      let document = try decoder.decode(Document.self, from: data)
      try validate(document.pairings)
      return ordered(document.pairings)
    } catch let error as PairingStoreError {
      throw error
    } catch let error as PairingValidationError {
      throw error
    } catch {
      throw PairingStoreError.corruptedData
    }
  }

  public static func ordered(_ pairings: [Pairing]) -> [Pairing] {
    pairings.sorted {
      if $0.entityID != $1.entityID { return $0.entityID < $1.entityID }
      if $0.destination.rawValue != $1.destination.rawValue {
        return $0.destination.rawValue < $1.destination.rawValue
      }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  private static func validate(_ pairings: [Pairing]) throws {
    for pairing in pairings {
      try PairingValidator.validate(pairing, existing: pairings)
    }
  }

  private struct Header: Decodable {
    let version: Int
  }

  private struct Document: Codable {
    let version: Int
    let pairings: [Pairing]
  }
}

public actor InMemoryPairingStore: PairingStore {
  private var pairings: [Pairing]

  public init() {
    pairings = []
  }

  public init(pairings: [Pairing]) throws {
    _ = try PairingCodec.encode(pairings)
    self.pairings = PairingCodec.ordered(pairings)
  }

  public func all() throws -> [Pairing] {
    pairings
  }

  public func save(_ pairing: Pairing) throws {
    try PairingValidator.validate(pairing, existing: pairings)
    var replacement = pairings.filter { $0.id != pairing.id }
    replacement.append(pairing)
    _ = try PairingCodec.encode(replacement)
    pairings = PairingCodec.ordered(replacement)
  }

  public func delete(id: UUID) throws {
    pairings.removeAll { $0.id == id }
  }

  public func deleteAll() throws {
    pairings.removeAll()
  }
}
