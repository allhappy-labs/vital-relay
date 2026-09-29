import Foundation
import HealthSyncCore

enum ProtectedConfigurationStoreError: Error, Equatable, Sendable {
  case applicationSupportUnavailable
  case operationFailed
}

actor ProtectedConfigurationStore: ConfigurationStore {
  nonisolated static let fileProtection =
    FileProtectionType.completeUntilFirstUserAuthentication
  nonisolated static let writingOptions: Data.WritingOptions = [
    .atomic, .completeFileProtectionUntilFirstUserAuthentication,
  ]

  nonisolated let fileURL: URL

  private let directoryURL: URL
  private let fileManager: FileManager

  init(
    directoryURL: URL,
    fileManager: FileManager = .default
  ) {
    self.directoryURL = directoryURL
    self.fileManager = fileManager
    fileURL = directoryURL.appending(path: "configuration-v1.json", directoryHint: .notDirectory)
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ProtectedConfigurationStoreError.applicationSupportUnavailable
    }
    let directoryURL = applicationSupportURL.appending(
      path: "com.olhapi.HAHealthSync",
      directoryHint: .isDirectory
    )
    self.directoryURL = directoryURL
    self.fileManager = fileManager
    fileURL = directoryURL.appending(path: "configuration-v1.json", directoryHint: .notDirectory)
  }

  func load() throws -> AppConfiguration {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return .default
    }

    do {
      let data = try Data(contentsOf: fileURL)
      return try ConfigurationCodec.decode(data)
    } catch let error as ConfigurationStoreError {
      throw error
    } catch {
      throw ProtectedConfigurationStoreError.operationFailed
    }
  }

  func save(_ configuration: AppConfiguration) throws {
    let data = try ConfigurationCodec.encode(configuration)
    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [
          .protectionKey: Self.fileProtection
        ]
      )
      try data.write(to: fileURL, options: Self.writingOptions)
      try fileManager.setAttributes(
        [.protectionKey: Self.fileProtection],
        ofItemAtPath: fileURL.path
      )
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      var protectedFileURL = fileURL
      try protectedFileURL.setResourceValues(resourceValues)
    } catch {
      throw ProtectedConfigurationStoreError.operationFailed
    }
  }

  func delete() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return
    }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw ProtectedConfigurationStoreError.operationFailed
    }
  }
}
