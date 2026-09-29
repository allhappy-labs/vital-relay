import Foundation

public protocol MetricQuerying: Sendable {
  func requestReadAuthorization(for metrics: Set<MetricID>) async throws
  func currentReading(
    for definition: MetricDefinition,
    now: Date,
    calendar: Calendar
  ) async throws -> MetricReading?
  func latestWorkout(now: Date) async throws -> WorkoutSummary?
}

extension MetricQuerying {
  public func latestWorkout(now: Date) async throws -> WorkoutSummary? {
    nil
  }
}
