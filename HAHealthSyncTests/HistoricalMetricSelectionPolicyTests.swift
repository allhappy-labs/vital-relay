import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HistoricalMetricSelectionPolicyTests: XCTestCase {
  func testEligibilityIsSelectedAndBackfillEligibleOnly() {
    let definitions = HistoricalMetricSelectionPolicy.eligibleDefinitions(
      selectedMetrics: [.steps, .sleepDuration, .lastAppleWorkout]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), [.steps, .sleepDuration])
  }

  func testArchiveSelectionIncludesSupportedWorkoutAndNewMetricOnly() throws {
    let json = """
      {"ok":true,"request_type":"archive_capability","protocol_version":2,
      "request_id":"test-request","archive_schema_version":1,"max_batch_bytes":1024,
      "max_samples_per_batch":10,"max_deletions_per_batch":10,
      "supported_sample_types":["HKWorkoutType","HKQuantityTypeIdentifierCyclingPower"],
      "supported_metrics":["last_apple_workout","cycling_power","steps"],
      "archive_available":true,"statistics_available":true}
      """
    let capability = try JSONDecoder().decode(ArchiveCapability.self, from: Data(json.utf8))
    let definitions = HistoricalMetricSelectionPolicy.archiveEligibleDefinitions(
      selectedMetrics: [.lastAppleWorkout, .cyclingPower, .steps, .netCalories],
      capability: capability)

    XCTAssertEqual(Set(definitions.map(\.id)), [.lastAppleWorkout, .cyclingPower])
  }
}
