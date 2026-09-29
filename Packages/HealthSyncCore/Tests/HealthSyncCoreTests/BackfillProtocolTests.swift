import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Health Bridge backfill protocol")
struct BackfillProtocolTests {
  private let now = Date(timeIntervalSince1970: 1_788_052_900)
  private let requestID = "backfill.01234567"

  @Test("Encodes protocol 1 with UTC points and integration wire units")
  func encodesRequest() throws {
    let request = try makeRequest(values: [7_000, 8_421])
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )

    #expect(json["request_type"] as? String == "backfill")
    #expect(json["protocol_version"] as? Int == 1)
    #expect(json["request_id"] as? String == requestID)
    #expect(json["user_id"] as? String == "fixture-user")
    let data = try #require(json["data"] as? [String: [[String: Any]]])
    #expect(data["steps"]?.count == 2)
    #expect(data["steps"]?.first?["timestamp"] as? String == "2026-08-30T01:18:20Z")
  }

  @Test("Enforces per-entity and total point limits")
  func pointLimits() throws {
    for count in [0, 1, 722] {
      #expect(throws: BackfillRequestValidationError.invalidPointCount) {
        try makeRequest(values: Array(repeating: 1, count: count))
      }
    }
    _ = try makeRequest(values: Array(repeating: 1, count: 721))

    let points = Array(repeating: point(value: 1), count: 721)
    let series = [
      BackfillSeries(metricID: .steps, points: points),
      BackfillSeries(metricID: .distance, points: points),
      BackfillSeries(metricID: .activeCalories, points: points),
      BackfillSeries(metricID: .flightsClimbed, points: points),
    ]
    #expect(throws: BackfillRequestValidationError.tooManyPoints) {
      try BackfillRequest(
        token: "fixture-secret",
        userID: "fixture-user",
        requestID: requestID,
        series: series,
        now: now
      )
    }
  }

  @Test("Rejects invalid identity metric values and time windows")
  func validation() {
    #expect(throws: BackfillRequestValidationError.invalidUserID) {
      try request(userID: String(repeating: "x", count: 129), series: validSeries())
    }
    #expect(throws: BackfillRequestValidationError.invalidRequestID) {
      try BackfillRequest(
        token: "fixture-secret",
        userID: "fixture-user",
        requestID: "bad id",
        series: validSeries(),
        now: now
      )
    }
    #expect(throws: BackfillRequestValidationError.ineligibleMetric) {
      try request(series: [BackfillSeries(metricID: .lastAppleWorkout, points: validPoints())])
    }
    #expect(throws: BackfillRequestValidationError.nonFiniteValue) {
      try makeRequest(values: [1, .infinity])
    }
    #expect(throws: BackfillRequestValidationError.futureTimestamp) {
      try request(
        series: [
          BackfillSeries(
            metricID: .steps,
            points: [point(value: 1), .init(timestamp: now.addingTimeInterval(301), value: 2)]
          )
        ]
      )
    }
    #expect(throws: BackfillRequestValidationError.invalidTimeWindow) {
      try request(
        series: [
          BackfillSeries(
            metricID: .steps,
            points: [
              .init(timestamp: now.addingTimeInterval(-BackfillRequest.maximumAge - 1), value: 1),
              point(value: 2),
            ]
          )
        ]
      )
    }
  }

  @Test("Validates committed and idempotent acknowledgements")
  func acknowledgement() throws {
    let committed = acknowledgement(inserted: 2, skipped: 0)
    try committed.validate(requestID: requestID)
    let idempotent = acknowledgement(inserted: 0, skipped: 2)
    try idempotent.validate(requestID: requestID)

    var invalid = acknowledgement(inserted: 1, skipped: 0)
    #expect(throws: BackfillAcknowledgementValidationError.invalidCounts) {
      try invalid.validate(requestID: requestID)
    }
    invalid = BackfillAcknowledgement(
      ok: true,
      committed: true,
      protocolVersion: 1,
      requestID: requestID,
      recorderSchema: 54,
      database: "sqlite",
      received: 2,
      inserted: 2,
      skipped: 0,
      entities: 1,
      statisticsPolicy: "history_only"
    )
    #expect(throws: BackfillAcknowledgementValidationError.unsupportedRecorder) {
      try invalid.validate(requestID: requestID)
    }
  }

  private func makeRequest(values: [Double]) throws -> BackfillRequest {
    try request(
      series: [
        BackfillSeries(
          metricID: .steps,
          points: values.enumerated().map { index, value in
            .init(
              timestamp: now.addingTimeInterval(Double(index - values.count) * 100), value: value)
          }
        )
      ]
    )
  }

  private func request(
    userID: String = "fixture-user",
    series: [BackfillSeries]
  ) throws -> BackfillRequest {
    try BackfillRequest(
      token: "fixture-secret",
      userID: userID,
      requestID: requestID,
      series: series,
      now: now
    )
  }

  private func validSeries() -> [BackfillSeries] {
    [BackfillSeries(metricID: .steps, points: validPoints())]
  }

  private func validPoints() -> [BackfillPoint] {
    [point(value: 1), .init(timestamp: now, value: 2)]
  }

  private func point(value: Double) -> BackfillPoint {
    BackfillPoint(timestamp: now.addingTimeInterval(-100), value: value)
  }

  private func acknowledgement(inserted: Int, skipped: Int) -> BackfillAcknowledgement {
    BackfillAcknowledgement(
      ok: true,
      committed: true,
      protocolVersion: 1,
      requestID: requestID,
      recorderSchema: 53,
      database: "sqlite",
      received: 2,
      inserted: inserted,
      skipped: skipped,
      entities: 1,
      statisticsPolicy: "history_only"
    )
  }
}
