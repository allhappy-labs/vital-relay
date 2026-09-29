import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Metric freshness store")
struct MetricFreshnessStoreTests {
  private static let referenceDate = Date(timeIntervalSince1970: 1_788_035_400)

  private static let selection: Set<MetricID> = [.steps, .bodyMass, .restingHeartRate]

  private static func update(
    checked: Set<MetricID> = [],
    sent: Set<MetricID> = [],
    at date: Date = MetricFreshnessStoreTests.referenceDate,
    selected: Set<MetricID> = MetricFreshnessStoreTests.selection,
    rotationOffset: Int? = nil,
    completedSweepAt: Date? = nil
  ) -> MetricFreshnessUpdate {
    MetricFreshnessUpdate(
      checked: checked,
      sent: sent,
      at: date,
      selected: selected,
      rotationOffset: rotationOffset,
      completedSweepAt: completedSweepAt
    )
  }

  @Test("An update stores check dates and later updates touch only the metrics they name")
  func updatesTouchOnlyTheMetricsTheyName() async throws {
    let store = InMemoryMetricFreshnessStore()
    let firstDate = Self.referenceDate
    let secondDate = Self.referenceDate.addingTimeInterval(60)

    try await store.record(Self.update(checked: [.steps, .bodyMass], at: firstDate))
    try await store.record(Self.update(checked: [.steps], at: secondDate))

    let snapshot = await store.snapshot()
    #expect(snapshot.lastCheckedAt[.steps] == secondDate)
    #expect(snapshot.lastCheckedAt[.bodyMass] == firstDate)
    #expect(snapshot.lastCheckedAt[.restingHeartRate] == nil)
  }

  @Test("Checks and sends are recorded independently")
  func checksAndSendsAreIndependent() async throws {
    let store = InMemoryMetricFreshnessStore()

    try await store.record(Self.update(checked: [.steps]))
    try await store.record(
      Self.update(sent: [.bodyMass], at: Self.referenceDate.addingTimeInterval(120)))

    let snapshot = await store.snapshot()
    #expect(snapshot.lastCheckedAt == [.steps: Self.referenceDate])
    #expect(snapshot.lastSentAt == [.bodyMass: Self.referenceDate.addingTimeInterval(120)])
  }

  @Test("One update records checks, sends, the sweep date and the offset in a single write")
  func oneUpdateRecordsEverything() async throws {
    let store = InMemoryMetricFreshnessStore()

    try await store.record(
      Self.update(
        checked: [.steps, .bodyMass],
        sent: [.steps],
        rotationOffset: 3,
        completedSweepAt: Self.referenceDate
      )
    )

    let snapshot = await store.snapshot()
    #expect(snapshot.lastCheckedAt == [.steps: Self.referenceDate, .bodyMass: Self.referenceDate])
    #expect(snapshot.lastSentAt == [.steps: Self.referenceDate])
    #expect(snapshot.lastFullSweepAt == Self.referenceDate)
    #expect(snapshot.rotationOffset == 3)
  }

  @Test("An update without a sweep date advances the offset and leaves the sweep alone")
  func rotationWithoutCompletionLeavesTheSweepDateAlone() async throws {
    let store = InMemoryMetricFreshnessStore()

    try await store.record(Self.update(checked: [.steps], rotationOffset: 1))

    let snapshot = await store.snapshot()
    #expect(snapshot.rotationOffset == 1)
    #expect(snapshot.lastFullSweepAt == nil)
  }

  @Test("An update without an offset leaves the offset where it is")
  func anUpdateWithoutAnOffsetKeepsTheCurrentOne() async throws {
    let store = InMemoryMetricFreshnessStore(
      snapshot: MetricFreshnessSnapshot(rotationOffset: 2)
    )

    try await store.record(Self.update(checked: [.steps]))

    #expect(await store.snapshot().rotationOffset == 2)
  }

  @Test("An update drops entries outside its selection but keeps the sweep and offset")
  func updatesDropUnselectedMetricsOnly() async throws {
    let store = InMemoryMetricFreshnessStore()
    try await store.record(
      Self.update(
        checked: Self.selection,
        sent: Self.selection,
        rotationOffset: 2,
        completedSweepAt: Self.referenceDate
      )
    )

    try await store.record(Self.update(selected: [.steps, .bodyMass]))

    let snapshot = await store.snapshot()
    #expect(snapshot.lastCheckedAt == [.steps: Self.referenceDate, .bodyMass: Self.referenceDate])
    #expect(snapshot.lastSentAt == [.steps: Self.referenceDate, .bodyMass: Self.referenceDate])
    #expect(snapshot.lastFullSweepAt == Self.referenceDate)
    #expect(snapshot.rotationOffset == 2)
  }

  @Test("reset returns an empty snapshot")
  func resetReturnsEmptySnapshot() async throws {
    let store = InMemoryMetricFreshnessStore()
    try await store.record(
      Self.update(checked: [.steps], rotationOffset: 5, completedSweepAt: Self.referenceDate))

    try await store.reset()

    let snapshot = await store.snapshot()
    #expect(snapshot == MetricFreshnessSnapshot())
  }

  @Test("Codec round trips a populated snapshot")
  func codecRoundTrips() throws {
    let snapshot = MetricFreshnessSnapshot(
      lastCheckedAt: [.steps: Self.referenceDate, .bodyMass: Self.referenceDate],
      lastSentAt: [.restingHeartRate: Self.referenceDate],
      lastFullSweepAt: Self.referenceDate,
      rotationOffset: 4
    )

    let encoded = try MetricFreshnessCodec.encode(snapshot)

    #expect(try MetricFreshnessCodec.decode(encoded) == snapshot)
  }

  @Test("A version-1 document missing rotationOffset and lastFullSweepAt decodes with defaults")
  func missingOptionalFieldsDecodeWithDefaults() throws {
    let json = Data(
      #"{"version":1,"lastCheckedAt":{"steps":1788035400},"lastSentAt":{}}"#.utf8)

    let snapshot = try MetricFreshnessCodec.decode(json)

    #expect(snapshot.lastCheckedAt == [.steps: Self.referenceDate])
    #expect(snapshot.lastFullSweepAt == nil)
    #expect(snapshot.rotationOffset == 0)
  }

  @Test("An unknown version throws unsupportedVersion")
  func unknownVersionThrows() {
    #expect(throws: MetricFreshnessStoreError.unsupportedVersion) {
      try MetricFreshnessCodec.decode(Data(#"{"version":2}"#.utf8))
    }
  }

  @Test("An update that only drops a deselected metric still counts as a change")
  func deselectionOnlyUpdateIsAChange() {
    let snapshot = MetricFreshnessSnapshot(lastCheckedAt: [.distance: Self.referenceDate])

    let update = MetricFreshnessUpdate(at: Self.referenceDate, selected: [.steps])

    // Nothing was checked, sent, rotated or swept, but the write is what evicts `.distance`.
    #expect(update.changes(snapshot))
  }

  @Test("An update that records nothing against an unchanged selection changes nothing")
  func emptyUpdateIsNotAChange() {
    let snapshot = MetricFreshnessSnapshot(
      lastCheckedAt: [.steps: Self.referenceDate],
      lastFullSweepAt: Self.referenceDate,
      rotationOffset: 2
    )

    let update = MetricFreshnessUpdate(at: Self.referenceDate, selected: [.steps])

    #expect(!update.changes(snapshot))
  }

  @Test("A non-MetricID key throws corruptedData")
  func nonMetricIDKeyThrows() {
    let json = Data(
      #"{"version":1,"lastCheckedAt":{"not-a-metric":1788035400},"lastSentAt":{}}"#.utf8)

    #expect(throws: MetricFreshnessStoreError.corruptedData) {
      try MetricFreshnessCodec.decode(json)
    }
  }
}
