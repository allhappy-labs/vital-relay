import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sync status store contract")
struct SyncStatusStoreContractTests {
  private let start = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Combined reports retain only directional counts")
  func combinedReport() async throws {
    let store = InMemorySyncStatusStore()
    let report = BidirectionalSyncReport(
      trigger: .background,
      outbound: SyncReport(
        trigger: .background,
        attemptedMetrics: 2,
        synchronizedMetrics: 1,
        skippedMetrics: 1,
        failures: [],
        startedAt: start,
        finishedAt: start.addingTimeInterval(1)
      ),
      inbound: InboundSyncReport(
        trigger: .background,
        attemptedPairings: 1,
        savedPairings: 1,
        skippedPairings: 0,
        failures: [],
        startedAt: start,
        finishedAt: start.addingTimeInterval(1)
      ),
      startedAt: start,
      finishedAt: start.addingTimeInterval(1)
    )

    try await store.record(report: report)

    let snapshot = await store.snapshot()
    let event = try #require(snapshot.recentEvents.last)
    #expect(event.attemptedMetrics == 2)
    #expect(event.synchronizedMetrics == 1)
    #expect(event.skippedMetrics == 1)
    #expect(event.attemptedPairings == 1)
    #expect(event.savedPairings == 1)
    #expect(event.skippedPairings == 0)
    #expect(snapshot.lastSuccessfulAt == report.finishedAt)
  }

  @Test("Legacy events default pairing counts to zero")
  func legacyPairingCounts() throws {
    let data = Data(
      #"{"version":1,"snapshot":{"registrations":[],"recentEvents":[{"trigger":"background","attemptedMetrics":2,"synchronizedMetrics":1,"skippedMetrics":1,"failureCategories":[],"finishedAt":0}]}}"#
        .utf8
    )

    let snapshot = try SyncStatusCodec.decode(data)
    let event = try #require(snapshot.recentEvents.first)

    #expect(event.attemptedPairings == 0)
    #expect(event.savedPairings == 0)
    #expect(event.skippedPairings == 0)
  }

  @Test("Legacy events decode the scope fields as absent")
  func legacyScopeFields() throws {
    let data = Data(
      #"{"version":1,"snapshot":{"registrations":[],"recentEvents":[{"trigger":"background","attemptedMetrics":2,"synchronizedMetrics":1,"skippedMetrics":1,"failureCategories":[],"finishedAt":0}]}}"#
        .utf8
    )

    let snapshot = try SyncStatusCodec.decode(data)
    let event = try #require(snapshot.recentEvents.first)

    #expect(event.scopeReason == nil)
    #expect(event.requestedMetrics == nil)
    #expect(event.collectedMetrics == nil)
    #expect(event.collectSeconds == nil)
    #expect(event.sendSeconds == nil)
    #expect(event.changedTypes == nil)
    #expect(event.starvedMetrics == nil)
    #expect(event.deferredMetrics == nil)
  }

  @Test("A truncated run records how many metrics it deferred")
  func deferredMetricsAreRecorded() async throws {
    let store = InMemorySyncStatusStore()
    let report = SyncReport(
      trigger: .healthKitObserver,
      attemptedMetrics: 88,
      synchronizedMetrics: 4,
      skippedMetrics: 0,
      failures: [],
      startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 12),
      collectedMetrics: 40,
      deferredMetrics: 48
    )

    try await store.record(report: report)
    let snapshot = try await store.snapshot()
    let event = try #require(snapshot.recentEvents.last)

    // Truncation has to be tellable from failure in the device data; that is the whole point of
    // carrying the count out of the report.
    #expect(event.deferredMetrics == 48)
    let restored = try SyncStatusCodec.decode(SyncStatusCodec.encode(snapshot))
    #expect(restored.recentEvents.last?.deferredMetrics == 48)
  }

  @Test("A directional failure preserves counts without identifiers")
  func partialFailureIsValueFree() async throws {
    let pairingID = UUID(uuidString: "7581B12B-14FE-43C2-971C-07EA1721E6D5")!
    let store = InMemorySyncStatusStore()
    let report = BidirectionalSyncReport(
      trigger: .manual,
      outbound: SyncReport(
        trigger: .manual,
        attemptedMetrics: 1,
        synchronizedMetrics: 1,
        skippedMetrics: 0,
        failures: [],
        startedAt: start,
        finishedAt: start.addingTimeInterval(1)
      ),
      inbound: InboundSyncReport(
        trigger: .manual,
        attemptedPairings: 1,
        savedPairings: 0,
        skippedPairings: 0,
        failures: [.init(pairingID: pairingID, category: .validation)],
        startedAt: start,
        finishedAt: start.addingTimeInterval(1)
      ),
      startedAt: start,
      finishedAt: start.addingTimeInterval(1)
    )

    try await store.record(report: report)

    let snapshot = await store.snapshot()
    #expect(snapshot.lastSuccessfulAt == nil)
    #expect(snapshot.lastFailure?.metricID == nil)
    #expect(snapshot.lastFailure?.category == .validation)
    #expect(snapshot.recentEvents.last?.synchronizedMetrics == 1)
    let encoded = try SyncStatusCodec.encode(snapshot)
    let text = try #require(String(data: encoded, encoding: .utf8))
    #expect(!text.contains(pairingID.uuidString))
    #expect(!text.contains("entityID"))
  }

  @Test("A successful no-change run clears a prior locked-device defer")
  func successfulNoChangeRunClearsLockedDefer() async throws {
    let finishedAt = start.addingTimeInterval(1)
    let store = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(
        lastFailure: SyncStatusFailure(
          metricID: nil,
          category: .deviceLocked,
          at: start
        )
      )
    )
    let report = BidirectionalSyncReport(
      trigger: .background,
      outbound: SyncReport(
        trigger: .background,
        attemptedMetrics: 2,
        synchronizedMetrics: 0,
        skippedMetrics: 2,
        failures: [],
        startedAt: start,
        finishedAt: finishedAt
      ),
      inbound: InboundSyncReport(
        trigger: .background,
        attemptedPairings: 1,
        savedPairings: 0,
        skippedPairings: 1,
        failures: [],
        startedAt: start,
        finishedAt: finishedAt
      ),
      startedAt: start,
      finishedAt: finishedAt
    )

    try await store.record(report: report)

    let snapshot = await store.snapshot()
    #expect(snapshot.lastSuccessfulAt == finishedAt)
    #expect(snapshot.lastFailure == nil)
  }

  @Test("A successful outbound no-change run clears a prior locked-device defer")
  func successfulOutboundNoChangeRunClearsLockedDefer() async throws {
    let finishedAt = start.addingTimeInterval(1)
    let store = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(
        lastFailure: SyncStatusFailure(
          metricID: nil,
          category: .deviceLocked,
          at: start
        )
      )
    )

    try await store.record(
      report: SyncReport(
        trigger: .background,
        attemptedMetrics: 2,
        synchronizedMetrics: 0,
        skippedMetrics: 2,
        failures: [],
        startedAt: start,
        finishedAt: finishedAt
      )
    )

    let snapshot = await store.snapshot()
    #expect(snapshot.lastSuccessfulAt == finishedAt)
    #expect(snapshot.lastFailure == nil)
  }

  @Test("Status is value-free, bounded, and independently registered")
  func lifecycle() async throws {
    let store = InMemorySyncStatusStore()
    try await store.recordAttempt(trigger: .manual, at: start)
    try await store.setRegistration(.registered(at: start), for: .steps)
    try await store.setRegistration(.disabled, for: .bodyMass)

    for offset in 0...100 {
      let date = start.addingTimeInterval(Double(offset))
      try await store.record(
        report: SyncReport(
          trigger: .background,
          attemptedMetrics: 2,
          synchronizedMetrics: 2,
          skippedMetrics: 0,
          failures: [],
          startedAt: date,
          finishedAt: date
        )
      )
    }

    let snapshot = await store.snapshot()
    #expect(SyncStatusSnapshot.maximumRecentEvents == 100)
    #expect(snapshot.lastAttemptedAt == start.addingTimeInterval(100))
    #expect(snapshot.lastSuccessfulAt == start.addingTimeInterval(100))
    #expect(snapshot.recentEvents.count == 100)
    #expect(snapshot.recentEvents.first?.finishedAt == start.addingTimeInterval(1))
    #expect(snapshot.recentEvents.last?.finishedAt == start.addingTimeInterval(100))
    #expect(snapshot.registrations[.steps] == .registered(at: start))
    #expect(snapshot.registrations[.bodyMass] == .disabled)

    let encoded = try SyncStatusCodec.encode(snapshot)
    let text = try #require(String(data: encoded, encoding: .utf8))
    #expect(!text.contains("reading"))
    #expect(!text.contains("healthValue"))
    #expect(try SyncStatusCodec.decode(encoded) == snapshot)

    try await store.reset()
    #expect(await store.snapshot() == SyncStatusSnapshot())
  }

  @Test("Failures retain only metric, category, and timestamp")
  func failure() async throws {
    let store = InMemorySyncStatusStore()
    let report = SyncReport(
      trigger: .shortcut,
      attemptedMetrics: 1,
      synchronizedMetrics: 0,
      skippedMetrics: 0,
      failures: [.init(metricID: .steps, category: .unauthorized)],
      startedAt: start,
      finishedAt: start.addingTimeInterval(1)
    )

    try await store.record(report: report)

    let snapshot = await store.snapshot()
    #expect(
      snapshot.lastFailure
        == SyncStatusFailure(
          metricID: .steps,
          category: .unauthorized,
          at: start.addingTimeInterval(1)
        )
    )
    #expect(snapshot.lastSuccessfulAt == nil)
    #expect(snapshot.recentEvents.first?.failureCategories == [.unauthorized])
  }

  @Test("Versioned status coding fails closed")
  func coding() throws {
    #expect(throws: SyncStatusStoreError.corruptedData) {
      try SyncStatusCodec.decode(Data("not-json".utf8))
    }
    #expect(throws: SyncStatusStoreError.unsupportedVersion) {
      try SyncStatusCodec.decode(Data(#"{"version":2,"snapshot":{}}"#.utf8))
    }
  }
}
