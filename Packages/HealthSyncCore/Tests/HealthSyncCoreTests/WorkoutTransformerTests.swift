import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Workout transformation")
struct WorkoutTransformerTests {
  private let start = ISO8601DateFormatter().date(from: "2026-08-27T18:20:00Z")!
  private let end = ISO8601DateFormatter().date(from: "2026-08-27T19:05:00Z")!
  private let synced = ISO8601DateFormatter().date(from: "2026-08-27T21:05:00Z")!

  @Test("Builds the source-confirmed array-wrapped workout dictionary")
  func completePayload() throws {
    let summary = WorkoutSummary(
      activityName: "Running",
      start: start,
      end: end,
      durationSeconds: 2_700,
      distanceMetres: 8_200,
      activeEnergyKilocalories: 510,
      averageHeartRateBPM: 154,
      maximumHeartRateBPM: 178
    )

    let payload = try WorkoutTransformer.transform(summary, lastSynced: synced)

    #expect(payload.fields["workout_type"] == .string("Running"))
    #expect(payload.fields["start_time"] == .string("2026-08-27T18:20:00Z"))
    #expect(payload.fields["end_time"] == .string("2026-08-27T19:05:00Z"))
    #expect(payload.fields["last_synced"] == .string("2026-08-27T21:05:00Z"))
    #expect(payload.fields["duration_min"] == .number(45))
    #expect(payload.fields["distance_km"] == .number(8.2))
    #expect(payload.fields["active_energy_kcal"] == .number(510))
    #expect(payload.fields["average_heart_rate_bpm"] == .number(154))
    #expect(payload.fields["max_heart_rate_bpm"] == .number(178))
    #expect(payload.liveValue == .array([.object(payload.fields)]))
  }

  @Test("Omits unavailable optional statistics")
  func minimalPayload() throws {
    let summary = WorkoutSummary(
      activityName: "Walking",
      start: start,
      end: end,
      durationSeconds: 2_700
    )

    let payload = try WorkoutTransformer.transform(summary, lastSynced: synced)

    #expect(payload.fields.count == 5)
    #expect(payload.fields["distance_km"] == nil)
    #expect(payload.fields["active_energy_kcal"] == nil)
    #expect(payload.fields["average_heart_rate_bpm"] == nil)
    #expect(payload.fields["max_heart_rate_bpm"] == nil)
  }

  @Test("Rejects blank names, invalid dates, and invalid numeric fields")
  func invalidPayloads() {
    let valid = WorkoutSummary(
      activityName: "Running",
      start: start,
      end: end,
      durationSeconds: 2_700
    )
    let invalid = [
      WorkoutSummary(
        activityName: " ", start: start, end: end, durationSeconds: 2_700),
      WorkoutSummary(
        activityName: "Running", start: end, end: start, durationSeconds: 2_700),
      WorkoutSummary(
        activityName: "Running", start: start, end: end, durationSeconds: -.infinity),
      WorkoutSummary(
        activityName: "Running", start: start, end: end, durationSeconds: 2_700,
        distanceMetres: -1),
      WorkoutSummary(
        activityName: "Running", start: start, end: end, durationSeconds: 2_700,
        activeEnergyKilocalories: .nan),
      WorkoutSummary(
        activityName: "Running", start: start, end: end, durationSeconds: 2_700,
        averageHeartRateBPM: -1),
      WorkoutSummary(
        activityName: "Running", start: start, end: end, durationSeconds: 2_700,
        maximumHeartRateBPM: .infinity),
    ]

    for summary in invalid {
      #expect(throws: WorkoutTransformationError.invalidWorkout) {
        try WorkoutTransformer.transform(summary, lastSynced: synced)
      }
    }
    #expect(throws: WorkoutTransformationError.invalidWorkout) {
      try WorkoutTransformer.transform(
        valid, lastSynced: .distantFuture.addingTimeInterval(.infinity))
    }
  }

  @Test("Live request encodes the workout as one top-level special metric")
  func liveRequestEncoding() throws {
    let summary = WorkoutSummary(
      activityName: "Running",
      start: start,
      end: end,
      durationSeconds: 2_700
    )
    let payload = try WorkoutTransformer.transform(summary, lastSynced: synced)
    let request = LiveRequest(
      token: "fixture-secret",
      userID: "example-user",
      requestID: "live.01234567",
      specialMetric: .lastAppleWorkout,
      value: payload.liveValue
    )

    let data = try JSONEncoder().encode(request)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let metrics = try #require(object["data"] as? [String: Any])
    #expect(Set(metrics.keys) == ["last_apple_workout"])
    let workouts = try #require(metrics["last_apple_workout"] as? [[String: Any]])
    #expect(workouts.count == 1)
    #expect(workouts[0]["workout_type"] as? String == "Running")
  }
}
