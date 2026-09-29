import Foundation

public enum ConfigurationStoreError: Error, Equatable, Sendable {
  case invalidUserID
  case unsupportedVersion
  case corruptedData
}

public protocol ConfigurationStore: Sendable {
  func load() async throws -> AppConfiguration
  func save(_ configuration: AppConfiguration) async throws
  func delete() async throws
}

public enum ConfigurationCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ configuration: AppConfiguration) throws -> Data {
    try configuration.validate()
    let document = Document(version: currentVersion, configuration: configuration)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return try encoder.encode(document)
    } catch {
      throw ConfigurationStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> AppConfiguration {
    let decoder = JSONDecoder()
    do {
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw ConfigurationStoreError.unsupportedVersion
      }
      let document = try decoder.decode(Document.self, from: data)
      try document.configuration.validate()
      return document.configuration
    } catch let error as ConfigurationStoreError {
      throw error
    } catch {
      throw ConfigurationStoreError.corruptedData
    }
  }

  private struct Header: Decodable {
    let version: Int
  }

  private struct Document: Codable {
    let version: Int
    let configuration: AppConfiguration
  }
}

public actor InMemoryConfigurationStore: ConfigurationStore {
  private var configuration: AppConfiguration?

  public init(configuration: AppConfiguration? = nil) {
    self.configuration = configuration
  }

  public func load() throws -> AppConfiguration {
    configuration ?? .default
  }

  public func save(_ configuration: AppConfiguration) throws {
    try configuration.validate()
    self.configuration = configuration
  }

  public func delete() throws {
    configuration = nil
  }
}
