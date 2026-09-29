import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitTypeResolverTests: XCTestCase {
  func testResolvesInitialQuantityTypes() throws {
    XCTAssertEqual(
      try HealthKitTypeResolver.quantityType(for: .stepCount).identifier,
      HKQuantityTypeIdentifier.stepCount.rawValue
    )
    XCTAssertEqual(
      try HealthKitTypeResolver.quantityType(for: .bodyMass).identifier,
      HKQuantityTypeIdentifier.bodyMass.rawValue
    )
    XCTAssertEqual(
      try HealthKitTypeResolver.quantityType(for: .restingHeartRate).identifier,
      HKQuantityTypeIdentifier.restingHeartRate.rawValue
    )
    for destination in WritableHealthRegistry.all {
      XCTAssertEqual(
        try HealthKitTypeResolver.quantityType(for: destination.id).identifier,
        destination.id.rawValue
      )
    }
  }

  func testResolvesExactHealthKitUnits() throws {
    XCTAssertEqual(try HealthKitTypeResolver.unit(for: .count), HKUnit.count())
    XCTAssertEqual(
      try HealthKitTypeResolver.unit(for: .kilograms),
      HKUnit.gramUnit(with: .kilo)
    )
    XCTAssertEqual(try HealthKitTypeResolver.unit(for: .pounds), HKUnit.pound())
    XCTAssertEqual(
      try HealthKitTypeResolver.unit(for: .beatsPerMinute),
      HKUnit.count().unitDivided(by: .minute())
    )
    XCTAssertEqual(try HealthKitTypeResolver.unit(for: .grams), HKUnit.gram())
    XCTAssertEqual(
      try HealthKitTypeResolver.unit(for: .internationalUnits), HKUnit.internationalUnit())
    XCTAssertEqual(try HealthKitTypeResolver.unit(for: .unitless), HKUnit.count())
  }

  func testUnavailableIdentifierFailsClosed() {
    XCTAssertThrowsError(
      try HealthKitTypeResolver.quantityType(identifier: "invalid.health.type")
    ) { error in
      XCTAssertEqual(error as? HealthKitTypeResolverError, .unavailableType)
    }
  }
}
