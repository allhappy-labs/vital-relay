import HealthKit
import XCTest

@testable import HAHealthSync

final class HealthKitSleepMappingTests: XCTestCase {
  func testMapsAppleCasesWithoutUsingRawValuesAcrossTheSeam() {
    XCTAssertEqual(HealthKitSleepMapper.stage(for: .inBed), .inBed)
    XCTAssertEqual(HealthKitSleepMapper.stage(for: .awake), .awake)
    XCTAssertEqual(HealthKitSleepMapper.stage(for: .asleepUnspecified), .asleepUnspecified)
    XCTAssertEqual(HealthKitSleepMapper.stage(for: .asleepCore), .core)
    XCTAssertEqual(HealthKitSleepMapper.stage(for: .asleepDeep), .deep)
    XCTAssertEqual(HealthKitSleepMapper.stage(for: .asleepREM), .rem)
  }
}
