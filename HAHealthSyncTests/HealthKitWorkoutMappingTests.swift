import HealthKit
import XCTest

@testable import HAHealthSync

final class HealthKitWorkoutMappingTests: XCTestCase {
  func testMapsCommonWorkoutTypesWithoutSendingAppleRawValues() {
    XCTAssertEqual(HealthKitWorkoutMapper.activityName(for: .running), "Running")
    XCTAssertEqual(HealthKitWorkoutMapper.activityName(for: .walking), "Walking")
    XCTAssertEqual(HealthKitWorkoutMapper.activityName(for: .cycling), "Cycling")
    XCTAssertEqual(HealthKitWorkoutMapper.activityName(for: .swimming), "Swimming")
    XCTAssertEqual(
      HealthKitWorkoutMapper.activityName(for: .traditionalStrengthTraining),
      "Traditional Strength Training"
    )
    XCTAssertEqual(HealthKitWorkoutMapper.activityName(for: .other), "Other")
  }
}
