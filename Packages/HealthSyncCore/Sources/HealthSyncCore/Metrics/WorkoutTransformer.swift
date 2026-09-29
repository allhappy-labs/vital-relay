import Foundation

public struct WorkoutSummary: Sendable, Equatable {
  public let activityName: String
  public let start: Date
  public let end: Date
  public let durationSeconds: Double
  public let distanceMetres: Double?
  public let activeEnergyKilocalories: Double?
  public let averageHeartRateBPM: Double?
  public let maximumHeartRateBPM: Double?

  public init(
    activityName: String,
    start: Date,
    end: Date,
    durationSeconds: Double,
    distanceMetres: Double? = nil,
    activeEnergyKilocalories: Double? = nil,
    averageHeartRateBPM: Double? = nil,
    maximumHeartRateBPM: Double? = nil
  ) {
    self.activityName = activityName
    self.start = start
    self.end = end
    self.durationSeconds = durationSeconds
    self.distanceMetres = distanceMetres
    self.activeEnergyKilocalories = activeEnergyKilocalories
    self.averageHeartRateBPM = averageHeartRateBPM
    self.maximumHeartRateBPM = maximumHeartRateBPM
  }
}

public enum WorkoutTransformationError: Error, Equatable, Sendable {
  case invalidWorkout
}

public enum WorkoutTransformer: Sendable {
  public static func transform(
    _ summary: WorkoutSummary,
    lastSynced: Date
  ) throws -> WorkoutPayload {
    let activityName = summary.activityName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !activityName.isEmpty,
      isFinite(summary.start),
      isFinite(summary.end),
      isFinite(lastSynced),
      summary.end >= summary.start,
      isValid(summary.durationSeconds),
      isValid(summary.distanceMetres),
      isValid(summary.activeEnergyKilocalories),
      isValid(summary.averageHeartRateBPM),
      isValid(summary.maximumHeartRateBPM)
    else {
      throw WorkoutTransformationError.invalidWorkout
    }

    var fields: [String: JSONValue] = [
      "workout_type": .string(activityName),
      "start_time": .string(timestamp(summary.start)),
      "end_time": .string(timestamp(summary.end)),
      "last_synced": .string(timestamp(lastSynced)),
      "duration_min": .number(summary.durationSeconds / 60),
    ]
    if let distanceMetres = summary.distanceMetres {
      fields["distance_km"] = .number(distanceMetres / 1_000)
    }
    if let activeEnergyKilocalories = summary.activeEnergyKilocalories {
      fields["active_energy_kcal"] = .number(activeEnergyKilocalories)
    }
    if let averageHeartRateBPM = summary.averageHeartRateBPM {
      fields["average_heart_rate_bpm"] = .number(averageHeartRateBPM)
    }
    if let maximumHeartRateBPM = summary.maximumHeartRateBPM {
      fields["max_heart_rate_bpm"] = .number(maximumHeartRateBPM)
    }
    return WorkoutPayload(fields: fields)
  }

  private static func isFinite(_ date: Date) -> Bool {
    date.timeIntervalSinceReferenceDate.isFinite
  }

  private static func isValid(_ value: Double) -> Bool {
    value.isFinite && value >= 0
  }

  private static func isValid(_ value: Double?) -> Bool {
    value.map(isValid) ?? true
  }

  private static func timestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
