import Foundation

public enum SyncCheckpointStoreError: Error, Equatable, Sendable {
  case emptyAnchor
  case unsupportedVersion
  case corruptedData
}

public protocol SyncCheckpointStore: Sendable {
  func anchor(for metric: MetricID) async throws -> Data?
  func commit(anchor: Data, for metric: MetricID) async throws
  func reset(metric: MetricID) async throws
  func resetAll() async throws
}

public enum SyncCheckpointCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ anchors: [MetricID: Data]) throws -> Data {
    guard anchors.values.allSatisfy({ !$0.isEmpty }) else {
      throw SyncCheckpointStoreError.emptyAnchor
    }
    let document = Document(
      version: currentVersion,
      anchors: Dictionary(uniqueKeysWithValues: anchors.map { ($0.key.rawValue, $0.value) })
    )
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(document)
    } catch {
      throw SyncCheckpointStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> [MetricID: Data] {
    do {
      let decoder = JSONDecoder()
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw SyncCheckpointStoreError.unsupportedVersion
      }
      let document = try decoder.decode(Document.self, from: data)
      var anchors: [MetricID: Data] = [:]
      for (key, value) in document.anchors {
        guard let metric = MetricID(rawValue: key), !value.isEmpty else {
          throw SyncCheckpointStoreError.corruptedData
        }
        anchors[metric] = value
      }
      return anchors
    } catch let error as SyncCheckpointStoreError {
      throw error
    } catch {
      throw SyncCheckpointStoreError.corruptedData
    }
  }

  private struct Header: Decodable {
    let version: Int
  }

  private struct Document: Codable {
    let version: Int
    let anchors: [String: Data]
  }
}

public actor InMemorySyncCheckpointStore: SyncCheckpointStore {
  private var anchors: [MetricID: Data]

  public init(anchors: [MetricID: Data] = [:]) {
    self.anchors = anchors
  }

  public func anchor(for metric: MetricID) throws -> Data? {
    try Task.checkCancellation()
    return anchors[metric]
  }

  public func commit(anchor: Data, for metric: MetricID) throws {
    try Task.checkCancellation()
    guard !anchor.isEmpty else {
      throw SyncCheckpointStoreError.emptyAnchor
    }
    anchors[metric] = anchor
  }

  public func reset(metric: MetricID) throws {
    try Task.checkCancellation()
    anchors[metric] = nil
  }

  public func resetAll() throws {
    try Task.checkCancellation()
    anchors.removeAll()
  }
}
