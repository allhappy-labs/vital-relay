import Foundation

public enum MetricAggregationError: Error, Equatable, Sendable {
  case invalidCalendarWindow
  case unsupportedStrategy
  case invalidAggregate
}

public enum MetricAggregator: Sendable {
  public static func dateInterval(
    for window: SyncWindow,
    now: Date,
    calendar: Calendar
  ) -> DateInterval? {
    let today = calendar.startOfDay(for: now)
    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
      return nil
    }
    switch window {
    case .currentDay:
      return DateInterval(start: today, end: tomorrow)
    case .trailingDays(let days):
      guard days > 0,
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today)
      else {
        return nil
      }
      return DateInterval(start: start, end: tomorrow)
    }
  }

  public static func aggregate(
    samples: [HealthSample],
    definition: MetricDefinition,
    now: Date,
    calendar: Calendar
  ) throws -> MetricReading? {
    guard let window = dateInterval(for: definition.syncWindow, now: now, calendar: calendar) else {
      throw MetricAggregationError.invalidCalendarWindow
    }
    let eligible = deduplicated(
      samples.filter {
        !$0.isFromThisApplication && !$0.isImportedFromHomeAssistant
          && $0.timestamp >= window.start && $0.timestamp < window.end
      }
    )

    switch definition.aggregation {
    case .latestSample:
      guard let sample = SampleOrdering.preferred(eligible) else { return nil }
      return try MetricTransformer.transform(sample, using: definition)
    case .dailyCumulativeSum:
      let values = try eligible.map { try MetricTransformer.transform($0, using: definition).value }
      return try reading(values.reduce(0, +), timestamp: now, definition: definition)
    case .dailyAverage:
      let values = try eligible.map { try MetricTransformer.transform($0, using: definition).value }
      guard !values.isEmpty else { return nil }
      return try reading(
        values.reduce(0, +) / Double(values.count), timestamp: now, definition: definition)
    case .dailyMinimum:
      let values = try eligible.map { try MetricTransformer.transform($0, using: definition).value }
      guard let value = values.min() else { return nil }
      return try reading(value, timestamp: now, definition: definition)
    case .dailyMaximum:
      let values = try eligible.map { try MetricTransformer.transform($0, using: definition).value }
      guard let value = values.max() else { return nil }
      return try reading(value, timestamp: now, definition: definition)
    case .intervalDuration:
      let duration = unionDuration(of: eligible, clippedTo: window)
      return try reading(duration, timestamp: now, definition: definition)
    case .sleepStageDuration, .latestWorkout, .categoryStateConversion:
      throw MetricAggregationError.unsupportedStrategy
    }
  }

  private static func deduplicated(_ samples: [HealthSample]) -> [HealthSample] {
    Array(
      samples.reduce(into: [UUID: HealthSample]()) { result, sample in
        if let current = result[sample.id] {
          if SampleOrdering.isPreferred(sample, over: current) {
            result[sample.id] = sample
          }
        } else {
          result[sample.id] = sample
        }
      }.values
    )
  }

  private static func unionDuration(
    of samples: [HealthSample],
    clippedTo window: DateInterval
  ) -> TimeInterval {
    let intervals = samples.compactMap { sample -> DateInterval? in
      let start = max(sample.startDate, window.start)
      let end = min(sample.endDate, window.end)
      return end > start ? DateInterval(start: start, end: end) : nil
    }.sorted { $0.start < $1.start }

    var total: TimeInterval = 0
    var current: DateInterval?
    for interval in intervals {
      guard let accumulated = current else {
        current = interval
        continue
      }
      if interval.start <= accumulated.end {
        current = DateInterval(start: accumulated.start, end: max(accumulated.end, interval.end))
      } else {
        total += accumulated.duration
        current = interval
      }
    }
    return total + (current?.duration ?? 0)
  }

  private static func reading(
    _ value: Double,
    timestamp: Date,
    definition: MetricDefinition
  ) throws -> MetricReading {
    guard value.isFinite, definition.validation.contains(value) else {
      throw MetricAggregationError.invalidAggregate
    }
    return MetricReading(metricID: definition.id, timestamp: timestamp, value: value)
  }
}
