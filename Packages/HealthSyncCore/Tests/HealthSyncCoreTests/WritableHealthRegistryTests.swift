import Testing

@testable import HealthSyncCore

@Suite("Writable HealthKit registry")
struct WritableHealthRegistryTests {
  @Test("Contains only the source-backed numeric allowlist")
  func containsOnlyAllowlistedDestinations() {
    let expected: Set<HealthObjectTypeID> = [
      .bodyMass, .height, .bodyFatPercentage, .leanBodyMass, .bodyTemperature,
      .heartRate, .oxygenSaturation, .respiratoryRate, .dietaryWater,
      .dietaryEnergyConsumed, .bloodGlucose, .dietaryCarbohydrates,
      .dietaryFatTotal, .dietaryProtein, .insulinDelivery, .uvExposure,
    ]

    #expect(Set(WritableHealthRegistry.all.map(\.id)) == expected)
    #expect(WritableHealthRegistry.all.count == expected.count)
    #expect(WritableHealthRegistry.all.allSatisfy { $0.minimumIOSMajorVersion <= 18 })
  }

  @Test("UV exposure uses HealthKit's unitless UV index representation")
  func definesUVExposure() throws {
    let destination = try #require(WritableHealthRegistry[.uvExposure])

    #expect(destination.displayName == "UV Exposure")
    #expect(destination.category == .vitals)
    #expect(destination.nativeUnit == .unitless)
    #expect(destination.plausibleBounds == 0...50)
    #expect(destination.minimumIOSMajorVersion == 9)
  }

  @Test("Read-only computed and specialized types are absent")
  func excludesUnsafeDestinations() {
    let denied: Set<HealthObjectTypeID> = [
      .appleExerciseTime, .appleStandTime, .restingHeartRate,
      .walkingHeartRateAverage, .vo2Max, .appleSleepingWristTemperature,
      .sleepAnalysis, .workout,
    ]

    for type in denied {
      #expect(WritableHealthRegistry[type] == nil)
    }
  }

  @Test("Every destination declares a native unit and finite ordered bounds")
  func definitionsAreComplete() {
    for destination in WritableHealthRegistry.all {
      #expect(destination.nativeUnit != .none)
      #expect(destination.plausibleBounds.lowerBound.isFinite)
      #expect(destination.plausibleBounds.upperBound.isFinite)
      #expect(destination.plausibleBounds.lowerBound < destination.plausibleBounds.upperBound)
      #expect(!destination.displayName.isEmpty)
    }
  }
}
