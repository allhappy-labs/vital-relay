import Foundation
import HealthSyncCore

enum ProtectedPairingStoreError: Error, Equatable, Sendable {
  case applicationSupportUnavailable
  case operationFailed
}

actor ProtectedPairingStore: PairingStore {
  nonisolated static let fileProtection =
    FileProtectionType.completeUntilFirstUserAuthentication
  nonisolated static let writingOptions: Data.WritingOptions = [
    .atomic, .completeFileProtectionUntilFirstUserAuthentication,
  ]

  nonisolated let fileURL: URL

  private let directoryURL: URL
  private let fileManager: FileManager

  init(directoryURL: URL, fileManager: FileManager = .default) {
    self.directoryURL = directoryURL
    self.fileManager = fileManager
    fileURL = directoryURL.appending(path: "pairings-v1.json", directoryHint: .notDirectory)
  }

  init(fileManager: FileManager = .default) throws {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ProtectedPairingStoreError.applicationSupportUnavailable
    }
    let directoryURL = applicationSupportURL.appending(
      path: "com.olhapi.HAHealthSync",
      directoryHint: .isDirectory
    )
    self.directoryURL = directoryURL
    self.fileManager = fileManager
    fileURL = directoryURL.appending(path: "pairings-v1.json", directoryHint: .notDirectory)
  }

  func all() throws -> [Pairing] {
    guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
    do {
      return try PairingCodec.decode(Data(contentsOf: fileURL))
    } catch let error as PairingStoreError {
      throw error
    } catch let error as PairingValidationError {
      throw error
    } catch {
      throw ProtectedPairingStoreError.operationFailed
    }
  }

  func save(_ pairing: Pairing) throws {
    let current = try all()
    try PairingValidator.validate(pairing, existing: current)
    var replacement = current.filter { $0.id != pairing.id }
    replacement.append(pairing)
    try write(replacement)
  }

  func delete(id: UUID) throws {
    let replacement = try all().filter { $0.id != id }
    if replacement.isEmpty {
      try deleteAll()
    } else {
      try write(replacement)
    }
  }

  func deleteAll() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw ProtectedPairingStoreError.operationFailed
    }
  }

  private func write(_ pairings: [Pairing]) throws {
    let data = try PairingCodec.encode(pairings)
    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: Self.fileProtection]
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
      throw ProtectedPairingStoreError.operationFailed
    }
  }
}
