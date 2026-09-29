import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sample source selection")
struct SourceSelectionTests {
  private let timestamp = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Latest ties prefer non-user-entered then source and UUID lexicographically")
  func deterministicLatestTie() throws {
    let definition = try #require(MetricRegistry[.bodyMass])
    let samples = [
      sample(
        id: "00000000-0000-0000-0000-000000000003", source: "z.source", user: false, value: 90),
      sample(id: "00000000-0000-0000-0000-000000000002", source: "a.source", user: true, value: 80),
      sample(
        id: "00000000-0000-0000-0000-000000000001", source: "a.source", user: false, value: 70),
    ]

    let reading = try MetricAggregator.aggregate(
      samples: samples,
      definition: definition,
      now: timestamp,
      calendar: .current
    )

    #expect(reading?.value == 70)
  }

  @Test("Excludes this app and includes all other HealthKit sources")
  func originExclusion() throws {
    let definition = try #require(MetricRegistry[.steps])
    let samples = [
      HealthSample(timestamp: timestamp, value: 10, unit: .count, sourceBundleIdentifier: "watch"),
      HealthSample(timestamp: timestamp, value: 20, unit: .count, sourceBundleIdentifier: "other"),
      HealthSample(
        timestamp: timestamp,
        value: 10_000,
        unit: .count,
        sourceBundleIdentifier: "this-app",
        isFromThisApplication: true
      ),
    ]

    let reading = try MetricAggregator.aggregate(
      samples: samples,
      definition: definition,
      now: timestamp,
      calendar: .current
    )
    #expect(reading?.value == 30)
  }

  @Test("Excludes the Home Assistant origin marker even from another source")
  func homeAssistantOriginExclusion() throws {
    let definition = try #require(MetricRegistry[.steps])
    let samples = [
      HealthSample(timestamp: timestamp, value: 10, unit: .count),
      HealthSample(
        timestamp: timestamp,
        value: 10_000,
        unit: .count,
        sourceBundleIdentifier: "restored-source",
        isImportedFromHomeAssistant: true
      ),
    ]

    let reading = try MetricAggregator.aggregate(
      samples: samples,
      definition: definition,
      now: timestamp,
      calendar: .current
    )
    #expect(reading?.value == 10)
  }

  private func sample(
    id: String,
    source: String,
    user: Bool,
    value: Double
  ) -> HealthSample {
    HealthSample(
      id: UUID(uuidString: id)!,
      timestamp: timestamp,
      value: value,
      unit: .kilograms,
      sourceBundleIdentifier: source,
      isUserEntered: user
    )
  }
}
