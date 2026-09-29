import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class ProtectedConfigurationStoreTests: XCTestCase {
  private let configuration = AppConfiguration(
    baseURL: "https://ha.example.com",
    allowsConfirmedLocalHTTP: false,
    healthBridgeUserID: "oleh",
    selectedMetrics: [.steps, .bodyMass],
    backgroundSyncEnabled: true
  )

  func testMissingFileReturnsDefaults() async throws {
    try await withStore { store, _ in
      let loadedConfiguration = try await store.load()
      XCTAssertEqual(loadedConfiguration, .default)
    }
  }

  func testSaveAtomicallyReplacesConfiguration() async throws {
    try await withStore { store, directoryURL in
      try await store.save(configuration)

      var replacement = configuration
      replacement.baseURL = "https://second.example.com"
      replacement.selectedMetrics = [.restingHeartRate]
      try await store.save(replacement)

      let loadedConfiguration = try await store.load()
      XCTAssertEqual(loadedConfiguration, replacement)
      let files = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
      )
      XCTAssertEqual(files.map(\.lastPathComponent), ["configuration-v1.json"])
    }
  }

  func testCorruptedFileFailsClosed() async throws {
    try await withStore { store, _ in
      try FileManager.default.createDirectory(
        at: store.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("not-json".utf8).write(to: store.fileURL)

      do {
        _ = try await store.load()
        XCTFail("Expected corruptedData")
      } catch {
        XCTAssertEqual(error as? ConfigurationStoreError, .corruptedData)
      }
    }
  }

  func testFileIsExcludedFromBackup() async throws {
    try await withStore { store, _ in
      try await store.save(configuration)

      let resourceValues = try store.fileURL.resourceValues(
        forKeys: [.isExcludedFromBackupKey]
      )
      XCTAssertEqual(resourceValues.isExcludedFromBackup, true)
    }
  }

  func testDeclaresExactFileProtectionOptions() {
    XCTAssertEqual(
      ProtectedConfigurationStore.fileProtection,
      .completeUntilFirstUserAuthentication
    )
    XCTAssertTrue(
      ProtectedConfigurationStore.writingOptions.contains(
        .completeFileProtectionUntilFirstUserAuthentication
      )
    )
    XCTAssertTrue(ProtectedConfigurationStore.writingOptions.contains(.atomic))
  }

  func testFilesystemReportsExactProtectionWhenSupported() async throws {
    try await withStore { store, _ in
      try await store.save(configuration)

      let attributes = try FileManager.default.attributesOfItem(
        atPath: store.fileURL.path
      )
      guard let protection = attributes[.protectionKey] as? FileProtectionType else {
        throw XCTSkip("CoreSimulator does not report iOS data-protection metadata")
      }
      XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }
  }

  private func withStore(
    operation: (ProtectedConfigurationStore, URL) async throws -> Void
  ) async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "HAHealthSyncTests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = ProtectedConfigurationStore(directoryURL: directoryURL)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    try await operation(store, directoryURL)
  }
}
