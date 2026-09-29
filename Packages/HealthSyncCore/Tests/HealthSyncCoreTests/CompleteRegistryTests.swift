import Testing

@testable import HealthSyncCore

@Suite("Complete Health Bridge registry")
struct CompleteRegistryTests {
  @Test("Matches all 111 canonical integration identifiers")
  func canonicalParity() {
    let expected: Set<String> = [
      "last_sync_time", "last_apple_workout", "steps", "distance", "active_calories",
      "flights_climbed", "walking_speed", "walking_step_length",
      "walking_asymmetry_percentage", "walking_double_support_percentage",
      "swimming_distance", "cycling_distance", "wrist_temperature", "walking_steadiness",
      "cardio_recovery", "physical_effort", "insulin_delivery",
      "six_minute_walk_test_distance", "stair_ascent_speed", "stair_descent_speed",
      "body_mass", "height", "body_fat_percentage", "lean_body_mass",
      "waist_circumference", "body_temperature", "heart_rate", "resting_heart_rate",
      "walking_heart_rate_average", "heart_rate_variability", "vo2_max",
      "blood_pressure_systolic", "blood_pressure_diastolic", "oxygen_saturation", "uv_index",
      "uv_exposure_sed", "net_calories", "dietary_carbohydrates", "dietary_fat",
      "dietary_protein", "dietary_water", "blood_glucose", "basal_energy_burned",
      "sleep_duration", "sleep_rem_hours", "sleep_core_hours", "sleep_deep_hours",
      "sleep_awake_hours", "sleep_unspecified_hours", "sleep_details", "respiratory_rate",
      "mindful_minutes", "time_in_daylight", "asleep_time", "wake_time",
      "headphone_audio_exposure", "environmental_audio_exposure", "stand_time",
      "exercise_time", "dietary_energy_consumed", "dietary_fiber", "dietary_sugar",
      "dietary_cholesterol", "dietary_calcium", "dietary_chloride", "dietary_iron",
      "dietary_magnesium", "dietary_manganese", "dietary_phosphorus", "dietary_potassium",
      "dietary_sodium", "dietary_zinc", "dietary_caffeine", "dietary_copper",
      "dietary_niacin", "dietary_pantothenic_acid", "dietary_riboflavin",
      "dietary_thiamin", "dietary_vitamin_b6", "dietary_vitamin_c", "dietary_vitamin_e",
      "dietary_biotin", "dietary_chromium", "dietary_folate", "dietary_iodine",
      "dietary_molybdenum", "dietary_selenium", "dietary_vitamin_a",
      "dietary_vitamin_b12", "dietary_vitamin_d", "dietary_vitamin_k", "test_connection",
      "running_power", "running_stride_length", "running_ground_contact_time",
      "running_vertical_oscillation", "cycling_power", "cycling_cadence",
      "cycling_speed", "running_speed", "cycling_functional_threshold_power",
      "swimming_stroke_count", "underwater_depth", "water_temperature",
      "workout_effort_score", "estimated_workout_effort_score", "distance_rowing",
      "distance_paddle_sports", "distance_cross_country_skiing",
      "distance_downhill_snow_sports", "distance_skating_sports",
    ]

    #expect(expected.count == 111)
    #expect(MetricRegistry.canonicalHealthBridgeIdentifiers == expected)
    #expect(Set(MetricRegistry.all.map(\.id)) == Set(MetricID.allCases))
    #expect(MetricRegistry.all.count == MetricID.allCases.count)
  }

  @Test("New workout metrics retain their direct source, canonical unit, and aggregation")
  func newWorkoutMappings() throws {
    let expected: [(String, String, String, AggregationStrategy)] = [
      ("running_power", "HKQuantityTypeIdentifierRunningPower", "W", .latestSample),
      ("running_stride_length", "HKQuantityTypeIdentifierRunningStrideLength", "m", .latestSample),
      (
        "running_ground_contact_time", "HKQuantityTypeIdentifierRunningGroundContactTime", "ms",
        .latestSample
      ),
      (
        "running_vertical_oscillation", "HKQuantityTypeIdentifierRunningVerticalOscillation", "cm",
        .latestSample
      ),
      ("cycling_power", "HKQuantityTypeIdentifierCyclingPower", "W", .latestSample),
      ("cycling_cadence", "HKQuantityTypeIdentifierCyclingCadence", "rpm", .latestSample),
      ("cycling_speed", "HKQuantityTypeIdentifierCyclingSpeed", "m/s", .latestSample),
      ("running_speed", "HKQuantityTypeIdentifierRunningSpeed", "m/s", .latestSample),
      (
        "cycling_functional_threshold_power",
        "HKQuantityTypeIdentifierCyclingFunctionalThresholdPower", "W", .latestSample
      ),
      (
        "swimming_stroke_count", "HKQuantityTypeIdentifierSwimmingStrokeCount", "count",
        .dailyCumulativeSum
      ),
      ("underwater_depth", "HKQuantityTypeIdentifierUnderwaterDepth", "m", .latestSample),
      ("water_temperature", "HKQuantityTypeIdentifierWaterTemperature", "degC", .latestSample),
      (
        "workout_effort_score", "HKQuantityTypeIdentifierWorkoutEffortScore", "appleEffortScore",
        .latestSample
      ),
      (
        "estimated_workout_effort_score", "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore",
        "appleEffortScore", .latestSample
      ),
      ("distance_rowing", "HKQuantityTypeIdentifierDistanceRowing", "m", .dailyCumulativeSum),
      (
        "distance_paddle_sports", "HKQuantityTypeIdentifierDistancePaddleSports", "m",
        .dailyCumulativeSum
      ),
      (
        "distance_cross_country_skiing", "HKQuantityTypeIdentifierDistanceCrossCountrySkiing", "m",
        .dailyCumulativeSum
      ),
      (
        "distance_downhill_snow_sports", "HKQuantityTypeIdentifierDistanceDownhillSnowSports", "m",
        .dailyCumulativeSum
      ),
      (
        "distance_skating_sports", "HKQuantityTypeIdentifierDistanceSkatingSports", "m",
        .dailyCumulativeSum
      ),
    ]

    #expect(expected.count == 19)
    for (key, type, unit, aggregation) in expected {
      let definition = try #require(MetricRegistry.all.first { $0.id.rawValue == key })
      #expect(definition.healthObjectType.rawValue == type)
      #expect(definition.healthKitUnit.rawValue == unit)
      #expect(definition.bridgeUnit.rawValue == unit)
      #expect(definition.aggregation == aggregation)
      #expect(definition.transformation == .unitConversion)
      #expect(definition.availability == .available)
    }
    #expect(Set(expected.map(\.0)).count == 19)
    #expect(Set(MetricRegistry.all.map(\.id.rawValue)).count == MetricRegistry.all.count)
  }

  @Test("Only metrics with a direct public HealthKit source are selectable")
  func selectability() throws {
    #expect(try #require(MetricRegistry[.uvExposureSED]).availability == .noHealthKitSource)
    #expect(try #require(MetricRegistry[.netCalories]).availability == .noHealthKitSource)
    #expect(MetricRegistry.selectable.contains { $0.id == .uvExposureSED } == false)
    #expect(MetricRegistry.selectable.contains { $0.id == .netCalories } == false)
    #expect(MetricRegistry.selectable.allSatisfy { $0.availability == .available })
  }

  @Test("All source-backed percentage metrics preserve HealthKit fractions")
  func percentages() throws {
    for id in [
      MetricID.bodyFatPercentage, .walkingAsymmetryPercentage,
      .walkingDoubleSupportPercentage, .oxygenSaturation, .walkingSteadiness,
    ] {
      let definition = try #require(MetricRegistry[id])
      #expect(definition.healthKitUnit == .fraction)
      #expect(definition.bridgeUnit == .fraction)
      #expect(definition.transformation == .percentageFraction)
      #expect(definition.validation == 0...1)
    }
  }

  @Test("Every selectable numeric metric has complete synchronization policy")
  func completePolicies() throws {
    for definition in MetricRegistry.selectable where definition.id != .lastAppleWorkout {
      #expect(definition.healthObjectType != .noDirectHealthKitType)
      #expect(definition.healthKitUnit != .none)
      #expect(definition.bridgeUnit != .none)
      #expect(definition.minimumIOSMajorVersion >= 18)
      #expect(definition.supportsBackgroundDelivery)
      #expect(definition.validation.lowerBound <= definition.validation.upperBound)

      if definition.healthObjectType != .sleepAnalysis,
        definition.healthObjectType != .mindfulSession
      {
        let value = min(
          definition.validation.upperBound,
          max(definition.validation.lowerBound, definition.healthKitUnit == .fraction ? 0.5 : 1)
        )
        let reading = try MetricTransformer.transform(
          HealthSample(timestamp: .now, value: value, unit: definition.healthKitUnit),
          using: definition
        )
        #expect(reading.metricID == definition.id)
        #expect(reading.value.isFinite)
      }
    }
  }

  @Test("Historical import eligibility is centralized and excludes special values")
  func backfillEligibility() {
    #expect(MetricRegistry.backfillEligible.contains { $0.id == .steps })
    #expect(MetricRegistry.backfillEligible.contains { $0.id == .sleepDuration })
    #expect(MetricRegistry.backfillEligible.contains { $0.id == .asleepTime } == false)
    #expect(MetricRegistry.backfillEligible.contains { $0.id == .wakeTime } == false)
    #expect(MetricRegistry.backfillEligible.contains { $0.id == .lastAppleWorkout } == false)
    #expect(MetricRegistry.backfillEligible.allSatisfy { $0.availability == .available })
  }
}
