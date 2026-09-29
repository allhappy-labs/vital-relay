import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Live batch protocol")
struct LiveBatchTests {
  private let timestamp = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("A batch request carries one top-level key per entry")
  func request() throws {
    let request = LiveRequest(
      token: "fixture-secret",
      userID: "oleh",
      requestID: "live.batch",
      entries: [
        .reading(MetricReading(metricID: .steps, timestamp: timestamp, value: 8_421)),
        .workout(WorkoutPayload(fields: ["activity": .string("Running")])),
      ]
    )

    #expect(
      Set(request.data.keys) == [MetricID.steps.rawValue, MetricID.lastAppleWorkout.rawValue])
    #expect(
      request.data[MetricID.steps.rawValue]
        == .array([
          HealthBridgeDataPoint(timestamp: timestamp, value: .number(8_421)).liveValue
        ])
    )
    #expect(
      request.data[MetricID.lastAppleWorkout.rawValue]
        == WorkoutPayload(fields: ["activity": .string("Running")]).liveValue
    )
  }

  @Test("Exact counts are applied; skipped or missing counts are partial")
  func results() throws {
    #expect(
      try ack(received: 3, updated: 3, skipped: 0).batchResult(
        requestID: "live.batch", entryCount: 3) == .applied)
    #expect(
      try ack(received: 3, updated: 2, skipped: 1).batchResult(
        requestID: "live.batch", entryCount: 3) == .partial)
    #expect(
      try ack(received: 2, updated: 2, skipped: 0).batchResult(
        requestID: "live.batch", entryCount: 3) == .partial)
  }

  @Test("Identity mismatches still throw")
  func identity() {
    #expect(throws: LiveAcknowledgementValidationError.requestIDMismatch) {
      try ack(received: 1, updated: 1, skipped: 0).batchResult(
        requestID: "live.other", entryCount: 1)
    }
    #expect(throws: LiveAcknowledgementValidationError.notApplied) {
      try ack(received: 1, updated: 0, skipped: 1, applied: false)
        .batchResult(requestID: "live.batch", entryCount: 1)
    }
  }

  private func ack(
    received: Int,
    updated: Int,
    skipped: Int,
    applied: Bool = true
  ) -> LiveAcknowledgement {
    LiveAcknowledgement(
      ok: true,
      applied: applied,
      integrationVersion: "1.2.1",
      requestType: "live",
      protocolVersion: 1,
      requestID: "live.batch",
      receivedEntities: received,
      updatedEntities: updated,
      skippedEntities: skipped,
      lastSyncUpdated: true,
      error: nil
    )
  }
}
