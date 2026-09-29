import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Calendar and DST aggregation")
struct DSTAggregationTests {
  @Test(arguments: [("2026-03-29T12:00:00+02:00", 23.0), ("2026-10-25T12:00:00+01:00", 25.0)])
  func localDayUsesCalendarBoundaries(argument: (String, Double)) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
    let now = try #require(ISO8601DateFormatter().date(from: argument.0))
    let interval = try #require(
      MetricAggregator.dateInterval(for: .currentDay, now: now, calendar: calendar))
    #expect(interval.duration / 3_600 == argument.1)

    let definition = try #require(MetricRegistry[.steps])
    let samples = [
      HealthSample(timestamp: interval.start, value: 1, unit: .count),
      HealthSample(timestamp: interval.end.addingTimeInterval(-1), value: 2, unit: .count),
      HealthSample(timestamp: interval.start.addingTimeInterval(-1), value: 100, unit: .count),
      HealthSample(timestamp: interval.end, value: 100, unit: .count),
    ]
    let reading = try MetricAggregator.aggregate(
      samples: samples,
      definition: definition,
      now: now,
      calendar: calendar
    )
    #expect(reading?.value == 3)
  }
}
