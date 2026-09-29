import Foundation

public enum SleepAggregationError: Error, Equatable, Sendable {
  case invalidInterval
}

public enum SleepAggregator: Sendable {
  public static func aggregate(
    intervals: [SleepInterval],
    now: Date
  ) throws -> [MetricID: MetricReading] {
    guard now.timeIntervalSinceReferenceDate.isFinite else {
      throw SleepAggregationError.invalidInterval
    }

    let eligible = try deduplicated(
      intervals.filter { !$0.isFromThisApplication && $0.stage != .inBed }
    )
    let asleep = eligible.filter(\.stage.isAsleep)

    var readings: [MetricID: MetricReading] = [:]
    readings[.sleepDuration] = durationReading(.sleepDuration, intervals: asleep, now: now)
    readings[.sleepREM] = durationReading(
      .sleepREM, intervals: eligible.filter { $0.stage == .rem }, now: now)
    readings[.sleepCore] = durationReading(
      .sleepCore, intervals: eligible.filter { $0.stage == .core }, now: now)
    readings[.sleepDeep] = durationReading(
      .sleepDeep, intervals: eligible.filter { $0.stage == .deep }, now: now)
    readings[.sleepAwake] = durationReading(
      .sleepAwake, intervals: eligible.filter { $0.stage == .awake }, now: now)
    readings[.sleepUnspecified] = durationReading(
      .sleepUnspecified,
      intervals: eligible.filter { $0.stage == .asleepUnspecified },
      now: now
    )

    if let sleepStart = asleep.map(\.start).min() {
      readings[.asleepTime] = MetricReading(
        metricID: .asleepTime,
        timestamp: sleepStart,
        value: sleepStart.timeIntervalSince1970
      )
    }
    if let wakeTime = asleep.map(\.end).max() {
      readings[.wakeTime] = MetricReading(
        metricID: .wakeTime,
        timestamp: wakeTime,
        value: wakeTime.timeIntervalSince1970
      )
    }
    if let latest = latestStage(in: eligible), let code = latest.stage.healthBridgeCode {
      readings[.sleepDetails] = MetricReading(
        metricID: .sleepDetails,
        timestamp: latest.start,
        value: Double(code)
      )
    }

    return readings
  }

  private static func deduplicated(_ intervals: [SleepInterval]) throws -> [SleepInterval] {
    var result: [UUID: SleepInterval] = [:]
    for interval in intervals {
      guard
        interval.start.timeIntervalSinceReferenceDate.isFinite,
        interval.end.timeIntervalSinceReferenceDate.isFinite,
        interval.end > interval.start
      else {
        throw SleepAggregationError.invalidInterval
      }

      if let current = result[interval.id] {
        if isPreferred(interval, over: current) {
          result[interval.id] = interval
        }
      } else {
        result[interval.id] = interval
      }
    }
    return Array(result.values)
  }

  private static func durationReading(
    _ metricID: MetricID,
    intervals: [SleepInterval],
    now: Date
  ) -> MetricReading {
    MetricReading(metricID: metricID, timestamp: now, value: unionDuration(intervals))
  }

  private static func unionDuration(_ intervals: [SleepInterval]) -> TimeInterval {
    let sorted = intervals.sorted {
      if $0.start != $1.start { return $0.start < $1.start }
      if $0.end != $1.end { return $0.end < $1.end }
      return $0.id.uuidString < $1.id.uuidString
    }

    var total: TimeInterval = 0
    var currentStart: Date?
    var currentEnd: Date?
    for interval in sorted {
      guard let accumulatedStart = currentStart, let accumulatedEnd = currentEnd else {
        currentStart = interval.start
        currentEnd = interval.end
        continue
      }
      if interval.start <= accumulatedEnd {
        currentEnd = max(accumulatedEnd, interval.end)
      } else {
        total += accumulatedEnd.timeIntervalSince(accumulatedStart)
        currentStart = interval.start
        currentEnd = interval.end
      }
    }
    if let accumulatedStart = currentStart, let accumulatedEnd = currentEnd {
      total += accumulatedEnd.timeIntervalSince(accumulatedStart)
    }
    return total
  }

  private static func latestStage(in intervals: [SleepInterval]) -> SleepInterval? {
    intervals.max { lhs, rhs in
      isPreferred(rhs, over: lhs)
    }
  }

  private static func isPreferred(_ candidate: SleepInterval, over current: SleepInterval) -> Bool {
    if candidate.start != current.start { return candidate.start > current.start }
    if candidate.end != current.end { return candidate.end > current.end }
    if candidate.sourceBundleIdentifier != current.sourceBundleIdentifier {
      return candidate.sourceBundleIdentifier > current.sourceBundleIdentifier
    }
    return candidate.id.uuidString > current.id.uuidString
  }
}
