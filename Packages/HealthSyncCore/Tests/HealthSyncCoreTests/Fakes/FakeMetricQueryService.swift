import Foundation

@testable import HealthSyncCore

enum FakeMetricQueryError: Error, Equatable, Sendable {
  case authorizationDenied
  case queryFailed
}

actor FakeMetricQueryService: MetricQuerying {
  var readings: [MetricID: MetricReading] = [:]
  var workout: WorkoutSummary?
  var authorizationError: FakeMetricQueryError?
  var queryError: FakeMetricQueryError?
  private(set) var authorizedMetrics: Set<MetricID> = []
  /// Every metric a value was queried for, in order, so tests can prove a run did not query one.
  private(set) var readingRequests: [MetricID] = []

  func requestReadAuthorization(for metrics: Set<MetricID>) throws {
    if let authorizationError {
      throw authorizationError
    }
    authorizedMetrics = metrics
  }

  func currentReading(
    for definition: MetricDefinition,
    now: Date,
    calendar: Calendar
  ) throws -> MetricReading? {
    try Task.checkCancellation()
    readingRequests.append(definition.id)
    if let queryError {
      throw queryError
    }
    return readings[definition.id]
  }

  func latestWorkout(now: Date) throws -> WorkoutSummary? {
    try Task.checkCancellation()
    if let queryError {
      throw queryError
    }
    return workout
  }

  func setReading(_ reading: MetricReading?) {
    readings[reading?.metricID ?? .steps] = reading
  }

  func setWorkout(_ workout: WorkoutSummary?) {
    self.workout = workout
  }

  func configureReading(_ reading: MetricReading?, for metricID: MetricID) {
    readings[metricID] = reading
  }

  func configureQueryError(_ error: FakeMetricQueryError?) {
    queryError = error
  }
}
