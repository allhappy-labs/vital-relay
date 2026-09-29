import Testing

@testable import HealthSyncCore

@Suite("Initial metric registry completeness")
struct InitialMetricRegistryTests {
  @Test("Contains every requested Health Bridge identifier exactly once")
  func completeIdentifiers() {
    let expected: Set<String> = [
      "steps", "distance", "active_calories", "basal_energy_burned", "flights_climbed",
      "exercise_time", "stand_time", "time_in_daylight", "body_mass", "height",
      "body_fat_percentage", "lean_body_mass", "heart_rate", "resting_heart_rate",
      "walking_heart_rate_average", "heart_rate_variability", "oxygen_saturation",
      "respiratory_rate", "vo2_max", "wrist_temperature", "sleep_duration",
      "sleep_rem_hours", "sleep_core_hours", "sleep_deep_hours", "sleep_awake_hours",
      "sleep_unspecified_hours", "asleep_time", "wake_time", "sleep_details",
      "mindful_minutes", "dietary_water", "dietary_energy_consumed", "blood_glucose",
      "last_apple_workout",
    ]

    #expect(expected.isSubset(of: Set(MetricRegistry.selectable.map(\.id.rawValue))))
    #expect(Set(MetricRegistry.selectable.map(\.id)).count == MetricRegistry.selectable.count)
  }

  @Test("Protocol-sensitive units and strategies are exact")
  func exactProtocolPolicies() throws {
    let expected: [MetricID: (UnitSymbol, AggregationStrategy)] = [
      .steps: (.count, .dailyCumulativeSum),
      .distance: (.metres, .dailyCumulativeSum),
      .activeCalories: (.kilocalories, .dailyCumulativeSum),
      .basalEnergyBurned: (.kilocalories, .dailyCumulativeSum),
      .flightsClimbed: (.count, .dailyCumulativeSum),
      .exerciseTime: (.minutes, .dailyCumulativeSum),
      .standTime: (.minutes, .dailyCumulativeSum),
      .timeInDaylight: (.seconds, .dailyCumulativeSum),
      .bodyMass: (.kilograms, .latestSample),
      .height: (.metres, .latestSample),
      .bodyFatPercentage: (.fraction, .latestSample),
      .leanBodyMass: (.kilograms, .latestSample),
      .heartRate: (.beatsPerMinute, .latestSample),
      .restingHeartRate: (.beatsPerMinute, .latestSample),
      .walkingHeartRateAverage: (.beatsPerMinute, .latestSample),
      .heartRateVariability: (.milliseconds, .latestSample),
      .oxygenSaturation: (.fraction, .latestSample),
      .respiratoryRate: (.breathsPerMinute, .latestSample),
      .vo2Max: (.millilitresPerKilogramMinute, .latestSample),
      .wristTemperature: (.degreesCelsius, .latestSample),
      .sleepDuration: (.seconds, .sleepStageDuration),
      .sleepREM: (.seconds, .sleepStageDuration),
      .sleepCore: (.seconds, .sleepStageDuration),
      .sleepDeep: (.seconds, .sleepStageDuration),
      .sleepAwake: (.seconds, .sleepStageDuration),
      .sleepUnspecified: (.seconds, .sleepStageDuration),
      .asleepTime: (.unixSeconds, .categoryStateConversion),
      .wakeTime: (.unixSeconds, .categoryStateConversion),
      .sleepDetails: (.stageCode, .categoryStateConversion),
      .mindfulMinutes: (.seconds, .intervalDuration),
      .dietaryWater: (.millilitres, .dailyCumulativeSum),
      .dietaryEnergyConsumed: (.kilocalories, .dailyCumulativeSum),
      .bloodGlucose: (.millimolesPerLitre, .latestSample),
      .lastAppleWorkout: (.none, .latestWorkout),
    ]

    for (id, policy) in expected {
      let definition = try #require(MetricRegistry[id])
      #expect(definition.bridgeUnit == policy.0)
      #expect(definition.aggregation == policy.1)
      #expect(definition.minimumIOSMajorVersion == 18)
      #expect(definition.supportsBackgroundDelivery)
    }
  }

  @Test("Percent and sleep normalization remain integration inputs")
  func normalizationPolicies() throws {
    for id in [MetricID.bodyFatPercentage, .oxygenSaturation] {
      let definition = try #require(MetricRegistry[id])
      #expect(definition.healthKitUnit == .fraction)
      #expect(definition.bridgeUnit == .fraction)
      #expect(definition.transformation == .percentageFraction)
    }
    for id in [
      MetricID.sleepDuration, .sleepREM, .sleepCore, .sleepDeep, .sleepAwake,
      .sleepUnspecified,
    ] {
      let definition = try #require(MetricRegistry[id])
      #expect(definition.bridgeUnit == .seconds)
      #expect(definition.transformation == .sleepSeconds)
      #expect(definition.syncWindow == .trailingDays(2))
    }
  }
}
