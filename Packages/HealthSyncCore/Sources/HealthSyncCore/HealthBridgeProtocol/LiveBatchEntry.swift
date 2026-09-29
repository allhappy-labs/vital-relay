import Foundation

public enum LiveBatchEntry: Sendable, Equatable {
  case reading(MetricReading)
  case workout(WorkoutPayload)

  public var key: String {
    switch self {
    case .reading(let reading): reading.metricID.rawValue
    case .workout: MetricID.lastAppleWorkout.rawValue
    }
  }

  var liveValue: JSONValue {
    switch self {
    case .reading(let reading):
      .array([
        HealthBridgeDataPoint(timestamp: reading.timestamp, value: .number(reading.value))
          .liveValue
      ])
    case .workout(let payload):
      payload.liveValue
    }
  }
}
