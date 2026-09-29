import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class CompleteHealthKitMappingTests: XCTestCase {
  func testEverySelectableDefinitionResolvesItsInstalledHealthKitTypeAndUnit() throws {
    for definition in MetricRegistry.selectable {
      _ = try HealthKitTypeResolver.objectType(for: definition.healthObjectType)
      if definition.id != .lastAppleWorkout,
        definition.healthObjectType != .sleepAnalysis,
        definition.healthObjectType != .mindfulSession
      {
        _ = try HealthKitTypeResolver.unit(for: definition.healthKitUnit)
      }
    }
  }

  func testMetricsWithoutDirectHealthKitSourcesFailClosed() throws {
    for id in [MetricID.uvExposureSED, .netCalories] {
      let definition = try XCTUnwrap(MetricRegistry[id])
      XCTAssertEqual(definition.availability, .noHealthKitSource)
      XCTAssertThrowsError(try HealthKitTypeResolver.objectType(for: definition.healthObjectType))
    }
  }

  func testHealthBridge21QuantitiesResolveToInstalledSDKIdentifiers() throws {
    let expected: [(MetricID, HKQuantityTypeIdentifier, HKUnit)] = [
      (.runningPower, .runningPower, .watt()),
      (.runningStrideLength, .runningStrideLength, .meter()),
      (.runningGroundContactTime, .runningGroundContactTime, .secondUnit(with: .milli)),
      (.runningVerticalOscillation, .runningVerticalOscillation, .meterUnit(with: .centi)),
      (.cyclingPower, .cyclingPower, .watt()),
      (.cyclingCadence, .cyclingCadence, .count().unitDivided(by: .minute())),
      (.cyclingSpeed, .cyclingSpeed, .meter().unitDivided(by: .second())),
      (.runningSpeed, .runningSpeed, .meter().unitDivided(by: .second())),
      (.cyclingFunctionalThresholdPower, .cyclingFunctionalThresholdPower, .watt()),
      (.swimmingStrokeCount, .swimmingStrokeCount, .count()),
      (.underwaterDepth, .underwaterDepth, .meter()),
      (.waterTemperature, .waterTemperature, .degreeCelsius()),
      (.workoutEffortScore, .workoutEffortScore, .appleEffortScore()),
      (.estimatedWorkoutEffortScore, .estimatedWorkoutEffortScore, .appleEffortScore()),
      (.distanceRowing, .distanceRowing, .meter()),
      (.distancePaddleSports, .distancePaddleSports, .meter()),
      (.distanceCrossCountrySkiing, .distanceCrossCountrySkiing, .meter()),
      (.distanceDownhillSnowSports, .distanceDownhillSnowSports, .meter()),
      (.distanceSkatingSports, .distanceSkatingSports, .meter()),
    ]

    XCTAssertEqual(expected.count, 19)
    for (id, identifier, unit) in expected {
      let definition = try XCTUnwrap(MetricRegistry[id])
      let type = try HealthKitTypeResolver.quantityType(for: definition.healthObjectType)
      XCTAssertEqual(type.identifier, identifier.rawValue)
      XCTAssertEqual(
        try HealthKitTypeResolver.unit(for: definition.healthKitUnit).unitString,
        unit.unitString
      )
    }
  }
}
