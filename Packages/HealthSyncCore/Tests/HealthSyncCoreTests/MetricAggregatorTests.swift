import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Metric aggregation")
struct MetricAggregatorTests {
  private var now: Date {
    ISO8601DateFormatter().date(from: "2026-08-28T12:00:00Z")!
  }
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  @Test("Daily cumulative sums distinct samples and returns zero when empty")
  func cumulative() throws {
    let definition = try #require(MetricRegistry[.steps])
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let samples = [
      sample(id: firstID, hourOffset: -2, value: 100),
      sample(id: firstID, hourOffset: -2, value: 100),
      sample(hourOffset: -1, value: 250),
      sample(hourOffset: -25, value: 9_999),
    ]

    let reading = try MetricAggregator.aggregate(
      samples: samples,
      definition: definition,
      now: now,
      calendar: calendar
    )
    let empty = try MetricAggregator.aggregate(
      samples: [],
      definition: definition,
      now: now,
      calendar: calendar
    )

    #expect(reading?.value == 350)
    #expect(empty?.value == 0)
  }

  @Test(arguments: [AggregationStrategy.dailyAverage, .dailyMinimum, .dailyMaximum])
  func statistics(strategy: AggregationStrategy) throws {
    let definition = numericDefinition(strategy: strategy)
    let reading = try MetricAggregator.aggregate(
      samples: [sample(hourOffset: -2, value: 2), sample(hourOffset: -1, value: 8)],
      definition: definition,
      now: now,
      calendar: calendar
    )
    let expected =
      switch strategy {
      case .dailyAverage: 5.0
      case .dailyMinimum: 2.0
      case .dailyMaximum: 8.0
      default: 0.0
      }
    #expect(reading?.value == expected)
  }

  @Test("Interval aggregation unions overlapping and touching intervals")
  func intervalUnion() throws {
    let definition = try #require(MetricRegistry[.mindfulMinutes])
    let start = now.addingTimeInterval(-3_600)
    let samples = [
      interval(start: start, end: start.addingTimeInterval(600)),
      interval(start: start.addingTimeInterval(300), end: start.addingTimeInterval(900)),
      interval(start: start.addingTimeInterval(900), end: start.addingTimeInterval(1_200)),
    ]

    let reading = try MetricAggregator.aggregate(
      samples: samples,
      definition: definition,
      now: now,
      calendar: calendar
    )

    #expect(reading?.value == 1_200)
  }

  private func sample(
    id: UUID = UUID(),
    hourOffset: Double,
    value: Double
  ) -> HealthSample {
    let timestamp = now.addingTimeInterval(hourOffset * 3_600)
    return HealthSample(id: id, timestamp: timestamp, value: value, unit: .count)
  }

  private func interval(start: Date, end: Date) -> HealthSample {
    HealthSample(
      id: UUID(),
      startDate: start,
      endDate: end,
      value: 0,
      unit: .seconds
    )
  }

  private func numericDefinition(strategy: AggregationStrategy) -> MetricDefinition {
    MetricDefinition(
      id: .steps,
      healthObjectType: .stepCount,
      displayName: "Fixture",
      category: .activity,
      healthKitUnit: .count,
      bridgeUnit: .count,
      aggregation: strategy,
      syncWindow: .currentDay,
      supportsBackgroundDelivery: true,
      canWriteToHealthKit: false,
      minimumIOSMajorVersion: 18,
      transformation: .unitConversion,
      validation: 0...100
    )
  }
}
