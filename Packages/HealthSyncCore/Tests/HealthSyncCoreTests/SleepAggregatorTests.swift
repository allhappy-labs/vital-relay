import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sleep aggregation")
struct SleepAggregatorTests {
  private let now = ISO8601DateFormatter().date(from: "2026-08-28T08:00:00Z")!

  @Test("Maps Health Bridge stage codes explicitly")
  func stageCodes() {
    #expect(SleepStage.deep.healthBridgeCode == 0)
    #expect(SleepStage.core.healthBridgeCode == 1)
    #expect(SleepStage.rem.healthBridgeCode == 2)
    #expect(SleepStage.awake.healthBridgeCode == 3)
    #expect(SleepStage.asleepUnspecified.healthBridgeCode == -1)
    #expect(SleepStage.inBed.healthBridgeCode == nil)
  }

  @Test("Unions overlaps without counting in-bed time as sleep")
  func overlapAggregation() throws {
    let start = now.addingTimeInterval(-8 * 3_600)
    let intervals = [
      interval(stage: .inBed, start: start, duration: 8 * 3_600),
      interval(stage: .core, start: start.addingTimeInterval(600), duration: 3_600),
      interval(stage: .deep, start: start.addingTimeInterval(3_000), duration: 3_600),
      interval(stage: .rem, start: start.addingTimeInterval(6_000), duration: 1_800),
      interval(stage: .awake, start: start.addingTimeInterval(7_800), duration: 600),
      interval(stage: .asleepUnspecified, start: start.addingTimeInterval(8_400), duration: 1_200),
    ]

    let result = try SleepAggregator.aggregate(intervals: intervals, now: now)

    #expect(result[.sleepCore]?.value == 3_600)
    #expect(result[.sleepDeep]?.value == 3_600)
    #expect(result[.sleepREM]?.value == 1_800)
    #expect(result[.sleepAwake]?.value == 600)
    #expect(result[.sleepUnspecified]?.value == 1_200)
    #expect(result[.sleepDuration]?.value == 8_400)
    #expect(result[.asleepTime]?.value == start.addingTimeInterval(600).timeIntervalSince1970)
    #expect(result[.wakeTime]?.value == start.addingTimeInterval(9_600).timeIntervalSince1970)
    #expect(result[.sleepDetails]?.value == -1)
  }

  @Test("Duplicate IDs, cross-source overlap, and self-origin are deterministic")
  func duplicatesAndSources() throws {
    let start = now.addingTimeInterval(-3_600)
    let duplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let intervals = [
      interval(id: duplicateID, stage: .core, start: start, duration: 1_800, source: "watch"),
      interval(id: duplicateID, stage: .core, start: start, duration: 1_800, source: "watch"),
      interval(
        stage: .deep, start: start.addingTimeInterval(900), duration: 1_800, source: "phone"),
      interval(stage: .rem, start: start, duration: 30_000, source: "this", selfOrigin: true),
    ]

    let result = try SleepAggregator.aggregate(intervals: intervals, now: now)
    #expect(result[.sleepCore]?.value == 1_800)
    #expect(result[.sleepDeep]?.value == 1_800)
    #expect(result[.sleepDuration]?.value == 2_700)
  }

  @Test("Empty input emits zero durations but no timestamps or details")
  func empty() throws {
    let result = try SleepAggregator.aggregate(intervals: [], now: now)
    #expect(result[.sleepDuration]?.value == 0)
    #expect(result[.sleepREM]?.value == 0)
    #expect(result[.asleepTime] == nil)
    #expect(result[.wakeTime] == nil)
    #expect(result[.sleepDetails] == nil)
  }

  private func interval(
    id: UUID = UUID(),
    stage: SleepStage,
    start: Date,
    duration: TimeInterval,
    source: String = "fixture",
    selfOrigin: Bool = false
  ) -> SleepInterval {
    SleepInterval(
      id: id,
      stage: stage,
      start: start,
      end: start.addingTimeInterval(duration),
      sourceBundleIdentifier: source,
      isFromThisApplication: selfOrigin
    )
  }
}
