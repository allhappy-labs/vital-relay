import Foundation
import Testing

@testable import HealthSyncCore

@Suite("ArchiveImport checkpoint")
struct ArchiveImportCheckpointStoreTests {
  private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

  @Test func mergingAndGapsPreserveOlderMissingIntervals() {
    var coverage = ArchiveIntervals()
    coverage.insert(DateInterval(start: date(30), end: date(40)))
    coverage.insert(DateInterval(start: date(20), end: date(30)))
    coverage.insert(DateInterval(start: date(25), end: date(35)))
    #expect(coverage.intervals == [DateInterval(start: date(20), end: date(40))])
    #expect(
      coverage.gaps(in: DateInterval(start: date(10), end: date(50))) == [
        DateInterval(start: date(10), end: date(20)), DateInterval(start: date(40), end: date(50)),
      ])
  }

  @Test func versionedCheckpointRoundTripsIndependentTypesAndRejectsCorruption() throws {
    var state = ArchiveImportCheckpoint()
    var steps = ArchiveTypeCheckpoint()
    steps.observedAuthorizationBoundary = date(20)
    steps.anchor = Data([1, 2, 3])
    steps.baselineAnchor = Data([8, 9])
    steps.scanInterval = DateInterval(start: date(20), end: date(90))
    steps.cursor = ArchiveScanCursor(
      type: .stepCount, interval: steps.scanInterval!,
      windowStart: date(20), windowEnd: date(50), anchor: Data([4]))
    steps.scanned.insert(DateInterval(start: date(20), end: date(40)))
    state.types[.stepCount] = steps
    state.uploaderFingerprint = "0123456789ab"
    state.ownerGeneration = 1
    state.types[.bodyMass] = ArchiveTypeCheckpoint()
    state.metricEarliestDates[.steps] = date(25)
    let data = try ArchiveCheckpointCodec.encode(state)
    #expect(try ArchiveCheckpointCodec.decode(data) == state)
    #expect(throws: ArchiveCheckpointStoreError.corruptedData) {
      try ArchiveCheckpointCodec.decode(Data("{}".utf8))
    }
    #expect(throws: ArchiveCheckpointStoreError.unsupportedVersion) {
      try ArchiveCheckpointCodec.decode(Data("{\"version\":99}".utf8))
    }
    #expect(throws: ArchiveCheckpointStoreError.corruptedData) {
      try ArchiveCheckpointCodec.decode(BackfillCheckpointCodec.encode(BackfillState()))
    }
  }

  @Test func pendingJournalRoundTripsExactPayloadAndStableIdentityWithoutCredentials() throws {
    let url = try #require(
      Bundle.module.url(forResource: "archive-batch-v2", withExtension: "json"))
    let batch = try ArchiveBatch.decodeValidated(Data(contentsOf: url))
    var state = ArchiveImportCheckpoint()
    state.userID = batch.userID
    state.destination = "https://example.invalid"
    state.uploaderFingerprint = "0123456789ab"
    state.ownerGeneration = 1
    state.types[.stepCount] = ArchiveTypeCheckpoint()
    var next = ArchiveTypeCheckpoint()
    next.anchor = Data([3, 4])
    state.pending = ArchivePendingBatch(type: .stepCount, batch: batch, nextCheckpoint: next)
    let data = try ArchiveCheckpointCodec.encode(state)
    let restored = try ArchiveCheckpointCodec.decode(data)
    #expect(restored.pending?.batch == batch)
    #expect(restored.pending?.nextCheckpoint.anchor == Data([3, 4]))
    #expect(String(decoding: data, as: UTF8.self).contains("\"token\"") == false)
    #expect(String(decoding: data, as: UTF8.self).contains("\"ownerGeneration\":1"))
    state.ownerGeneration = 0
    #expect(throws: ArchiveCheckpointStoreError.corruptedData) {
      try ArchiveCheckpointCodec.encode(state)
    }
  }

  @Test func comparisonMetadataRoundTripsWithoutUUIDsAndRejectsInvalidState() throws {
    var state = ArchiveImportCheckpoint()
    var checkpoint = ArchiveTypeCheckpoint()
    checkpoint.reconciliationRequired = true
    var scope = ArchiveIntervals()
    scope.insert(DateInterval(start: date(100), end: date(200)))
    checkpoint.reconciliationIntervals = scope
    checkpoint.inventoryComparison = ArchiveInventoryComparison(
      interval: DateInterval(start: date(100), end: date(200)), revision: 3, cursor: "opaque.cursor"
    )
    state.types[.stepCount] = checkpoint
    #expect(try ArchiveCheckpointCodec.decode(ArchiveCheckpointCodec.encode(state)) == state)
    state.types[.stepCount]?.inventoryComparison = ArchiveInventoryComparison(
      interval: DateInterval(start: date(100), end: date(200)), revision: -1,
      cursor: "opaque.cursor")
    #expect(throws: ArchiveCheckpointStoreError.corruptedData) {
      try ArchiveCheckpointCodec.encode(state)
    }
    state.types[.stepCount]?.inventoryComparison = ArchiveInventoryComparison(
      interval: DateInterval(start: date(100), end: date(200)), cursor: "without.revision")
    #expect(throws: ArchiveCheckpointStoreError.corruptedData) {
      try ArchiveCheckpointCodec.encode(state)
    }
  }
}
