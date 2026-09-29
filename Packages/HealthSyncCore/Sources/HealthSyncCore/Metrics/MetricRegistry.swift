public enum MetricRegistry: Sendable {
  public static let all: [MetricDefinition] = [
    metric(
      .steps, .stepCount, "Steps", .activity, .count, .count, .dailyCumulativeSum,
      canWrite: true, bounds: 0...250_000),
    metric(
      .distance, .distanceWalkingRunning, "Walking + Running Distance", .activity,
      .metres, .metres, .dailyCumulativeSum, canWrite: true, bounds: 0...500_000),
    metric(
      .activeCalories, .activeEnergyBurned, "Active Calories", .activity,
      .kilocalories, .kilocalories, .dailyCumulativeSum, canWrite: true, bounds: 0...30_000),
    metric(
      .basalEnergyBurned, .basalEnergyBurned, "Basal Calories", .activity,
      .kilocalories, .kilocalories, .dailyCumulativeSum, canWrite: true, bounds: 0...30_000),
    metric(
      .flightsClimbed, .flightsClimbed, "Flights Climbed", .activity, .count, .count,
      .dailyCumulativeSum, canWrite: true, bounds: 0...5_000),
    metric(
      .exerciseTime, .appleExerciseTime, "Exercise Time", .activity, .minutes, .minutes,
      .dailyCumulativeSum, bounds: 0...1_440),
    metric(
      .standTime, .appleStandTime, "Stand Time", .activity, .minutes, .minutes,
      .dailyCumulativeSum, bounds: 0...1_440),
    metric(
      .timeInDaylight, .timeInDaylight, "Time in Daylight", .activity, .minutes, .seconds,
      .dailyCumulativeSum, bounds: 0...86_400),
    metric(
      .walkingSpeed, .walkingSpeed, "Walking Speed", .activity, .metresPerSecond,
      .metresPerSecond, .latestSample, bounds: 0...15),
    metric(
      .walkingStepLength, .walkingStepLength, "Walking Step Length", .activity, .metres,
      .metres, .latestSample, bounds: 0...5),
    percentageMetric(
      .walkingAsymmetryPercentage, .walkingAsymmetryPercentage, "Walking Asymmetry",
      .activity),
    percentageMetric(
      .walkingDoubleSupportPercentage, .walkingDoubleSupportPercentage,
      "Walking Double Support", .activity),
    metric(
      .swimmingDistance, .distanceSwimming, "Swimming Distance", .activity, .metres,
      .metres, .dailyCumulativeSum, bounds: 0...500_000),
    metric(
      .cyclingDistance, .distanceCycling, "Cycling Distance", .activity, .metres,
      .metres, .dailyCumulativeSum, bounds: 0...1_000_000),
    metric(
      .runningPower, .runningPower, "Running Power", .activity, .watts,
      .watts, .latestSample, bounds: 0...3_000),
    metric(
      .runningStrideLength, .runningStrideLength, "Running Stride Length", .activity,
      .metres, .metres, .latestSample, bounds: 0...10),
    metric(
      .runningGroundContactTime, .runningGroundContactTime, "Running Ground Contact Time",
      .activity, .milliseconds, .milliseconds, .latestSample, bounds: 0...10_000),
    metric(
      .runningVerticalOscillation, .runningVerticalOscillation, "Running Vertical Oscillation",
      .activity, .centimetres, .centimetres, .latestSample, bounds: 0...100),
    metric(
      .cyclingPower, .cyclingPower, "Cycling Power", .activity, .watts,
      .watts, .latestSample, bounds: 0...3_000),
    metric(
      .cyclingCadence, .cyclingCadence, "Cycling Cadence", .activity,
      .revolutionsPerMinute, .revolutionsPerMinute, .latestSample, bounds: 0...300),
    metric(
      .cyclingSpeed, .cyclingSpeed, "Cycling Speed", .activity, .metresPerSecond,
      .metresPerSecond, .latestSample, bounds: 0...50),
    metric(
      .runningSpeed, .runningSpeed, "Running Speed", .activity, .metresPerSecond,
      .metresPerSecond, .latestSample, bounds: 0...20),
    metric(
      .cyclingFunctionalThresholdPower, .cyclingFunctionalThresholdPower,
      "Cycling Functional Threshold Power", .activity, .watts, .watts,
      .latestSample, bounds: 0...3_000),
    metric(
      .swimmingStrokeCount, .swimmingStrokeCount, "Swimming Stroke Count", .activity,
      .count, .count, .dailyCumulativeSum, bounds: 0...100_000),
    metric(
      .underwaterDepth, .underwaterDepth, "Underwater Depth", .activity, .metres,
      .metres, .latestSample, bounds: 0...500),
    metric(
      .waterTemperature, .waterTemperature, "Water Temperature", .activity,
      .degreesCelsius, .degreesCelsius, .latestSample, bounds: -10...100),
    metric(
      .workoutEffortScore, .workoutEffortScore, "Workout Effort Score", .activity,
      .appleEffortScore, .appleEffortScore, .latestSample, bounds: 0...10),
    metric(
      .estimatedWorkoutEffortScore, .estimatedWorkoutEffortScore,
      "Estimated Workout Effort Score", .activity, .appleEffortScore, .appleEffortScore,
      .latestSample, bounds: 0...10),
    metric(
      .distanceRowing, .distanceRowing, "Rowing Distance", .activity, .metres,
      .metres, .dailyCumulativeSum, bounds: 0...1_000_000),
    metric(
      .distancePaddleSports, .distancePaddleSports, "Paddle Sports Distance", .activity,
      .metres, .metres, .dailyCumulativeSum, bounds: 0...1_000_000),
    metric(
      .distanceCrossCountrySkiing, .distanceCrossCountrySkiing,
      "Cross Country Skiing Distance", .activity, .metres, .metres,
      .dailyCumulativeSum, bounds: 0...1_000_000),
    metric(
      .distanceDownhillSnowSports, .distanceDownhillSnowSports,
      "Downhill Snow Sports Distance", .activity, .metres, .metres,
      .dailyCumulativeSum, bounds: 0...1_000_000),
    metric(
      .distanceSkatingSports, .distanceSkatingSports, "Skating Sports Distance", .activity,
      .metres, .metres, .dailyCumulativeSum, bounds: 0...1_000_000),
    percentageMetric(
      .walkingSteadiness, .appleWalkingSteadiness, "Walking Steadiness", .activity),
    metric(
      .cardioRecovery, .heartRateRecoveryOneMinute, "Cardio Recovery", .activity,
      .beatsPerMinute, .beatsPerMinute, .latestSample, bounds: 0...300),
    metric(
      .physicalEffort, .physicalEffort, "Physical Effort", .activity,
      .metabolicEquivalent, .metabolicEquivalent, .latestSample, bounds: 0...50),
    metric(
      .insulinDelivery, .insulinDelivery, "Insulin Delivery", .activity,
      .internationalUnits, .internationalUnits, .dailyCumulativeSum, canWrite: true,
      bounds: 0...10_000),
    metric(
      .sixMinuteWalkTestDistance, .sixMinuteWalkTestDistance,
      "Six-Minute Walk Test Distance", .activity, .metres, .metres, .latestSample,
      bounds: 0...5_000),
    metric(
      .stairAscentSpeed, .stairAscentSpeed, "Stair Ascent Speed", .activity,
      .metresPerSecond, .metresPerSecond, .latestSample, bounds: 0...15),
    metric(
      .stairDescentSpeed, .stairDescentSpeed, "Stair Descent Speed", .activity,
      .metresPerSecond, .metresPerSecond, .latestSample, bounds: 0...15),

    metric(
      .bodyMass, .bodyMass, "Body Mass", .bodyMeasurements, .kilograms, .kilograms,
      .latestSample, canWrite: true, bounds: 1...700),
    metric(
      .height, .height, "Height", .bodyMeasurements, .metres, .metres, .latestSample,
      canWrite: true, bounds: 0.2...3),
    metric(
      .bodyFatPercentage, .bodyFatPercentage, "Body Fat Percentage", .bodyMeasurements,
      .fraction, .fraction, .latestSample, transformation: .percentageFraction, canWrite: true,
      bounds: 0...1),
    metric(
      .leanBodyMass, .leanBodyMass, "Lean Body Mass", .bodyMeasurements, .kilograms,
      .kilograms, .latestSample, canWrite: true, bounds: 1...500),
    metric(
      .waistCircumference, .waistCircumference, "Waist Circumference", .bodyMeasurements,
      .metres, .metres, .latestSample, bounds: 0.2...3),

    metric(
      .bodyTemperature, .bodyTemperature, "Body Temperature", .vitals, .degreesCelsius,
      .degreesCelsius, .latestSample, canWrite: true, bounds: 20...50),
    metric(
      .heartRate, .heartRate, "Heart Rate", .vitals, .beatsPerMinute, .beatsPerMinute,
      .latestSample, canWrite: true, bounds: 20...300),
    metric(
      .restingHeartRate, .restingHeartRate, "Resting Heart Rate", .vitals, .beatsPerMinute,
      .beatsPerMinute, .latestSample, bounds: 20...300),
    metric(
      .walkingHeartRateAverage, .walkingHeartRateAverage, "Walking Heart Rate Average",
      .vitals, .beatsPerMinute, .beatsPerMinute, .latestSample, bounds: 20...300),
    metric(
      .heartRateVariability, .heartRateVariabilitySDNN, "Heart Rate Variability", .vitals,
      .milliseconds, .milliseconds, .latestSample, bounds: 0...1_000),
    metric(
      .oxygenSaturation, .oxygenSaturation, "Blood Oxygen", .vitals, .fraction, .fraction,
      .latestSample, transformation: .percentageFraction, canWrite: true, bounds: 0...1),
    metric(
      .respiratoryRate, .respiratoryRate, "Respiratory Rate", .vitals,
      .breathsPerMinute, .breathsPerMinute, .latestSample, canWrite: true, bounds: 1...100),
    metric(
      .vo2Max, .vo2Max, "VO2 Max", .vitals, .millilitresPerKilogramMinute,
      .millilitresPerKilogramMinute, .latestSample, bounds: 1...100),
    metric(
      .wristTemperature, .appleSleepingWristTemperature, "Wrist Temperature", .vitals,
      .degreesCelsius, .degreesCelsius, .latestSample, bounds: 25...45),
    metric(
      .bloodPressureSystolic, .bloodPressureSystolic, "Blood Pressure Systolic", .vitals,
      .millimetresOfMercury, .millimetresOfMercury, .latestSample, bounds: 20...400),
    metric(
      .bloodPressureDiastolic, .bloodPressureDiastolic, "Blood Pressure Diastolic", .vitals,
      .millimetresOfMercury, .millimetresOfMercury, .latestSample, bounds: 10...300),
    metric(
      .uvIndex, .uvExposure, "UV Index", .vitals, .unitless, .unitless, .latestSample,
      bounds: 0...50),
    metric(
      .uvExposureSED, .noDirectHealthKitType, "UV Exposure SED", .vitals, .none,
      .standardErythemaDose, .latestSample, background: false, bounds: 0...1_000,
      availability: .noHealthKitSource),
    metric(
      .netCalories, .noDirectHealthKitType, "Net Calories", .vitals, .none, .kilocalories,
      .latestSample, background: false, bounds: -30_000...30_000,
      availability: .noHealthKitSource),
    metric(
      .headphoneAudioExposure, .headphoneAudioExposure, "Headphone Audio Exposure", .vitals,
      .decibelsAWeighted, .decibelsAWeighted, .latestSample, bounds: 0...200),
    metric(
      .environmentalAudioExposure, .environmentalAudioExposure,
      "Environmental Audio Exposure", .vitals, .decibelsAWeighted, .decibelsAWeighted,
      .latestSample, bounds: 0...200),

    sleepMetric(.sleepDuration, "Total Sleep Duration", 0...172_800),
    sleepMetric(.sleepREM, "REM Sleep", 0...172_800),
    sleepMetric(.sleepCore, "Core Sleep", 0...172_800),
    sleepMetric(.sleepDeep, "Deep Sleep", 0...172_800),
    sleepMetric(.sleepAwake, "Awake Duration", 0...172_800),
    sleepMetric(.sleepUnspecified, "Unspecified Sleep", 0...172_800),
    metric(
      .asleepTime, .sleepAnalysis, "Sleep Start", .sleep, .unixSeconds, .unixSeconds,
      .categoryStateConversion, window: .trailingDays(2), transformation: .timestamp,
      bounds: 0...4_102_444_800),
    metric(
      .wakeTime, .sleepAnalysis, "Wake Time", .sleep, .unixSeconds, .unixSeconds,
      .categoryStateConversion, window: .trailingDays(2), transformation: .timestamp,
      bounds: 0...4_102_444_800),
    metric(
      .sleepDetails, .sleepAnalysis, "Sleep Details", .sleep, .stageCode, .stageCode,
      .categoryStateConversion, window: .trailingDays(2), transformation: .stageCode,
      bounds: -1...3),

    metric(
      .mindfulMinutes, .mindfulSession, "Mindful Minutes", .other, .seconds, .seconds,
      .intervalDuration, canWrite: true, bounds: 0...86_400),
    metric(
      .dietaryWater, .dietaryWater, "Dietary Water", .other, .millilitres, .millilitres,
      .dailyCumulativeSum, canWrite: true, bounds: 0...30_000),
    metric(
      .dietaryEnergyConsumed, .dietaryEnergyConsumed, "Dietary Energy", .other,
      .kilocalories, .kilocalories, .dailyCumulativeSum, canWrite: true, bounds: 0...30_000),
    metric(
      .bloodGlucose, .bloodGlucose, "Blood Glucose", .other, .millimolesPerLitre,
      .millimolesPerLitre, .latestSample, canWrite: true, bounds: 0...100),
    nutritionMetric(
      .dietaryCarbohydrates, .dietaryCarbohydrates, "Dietary Carbohydrates", .grams,
      canWrite: true),
    nutritionMetric(.dietaryFat, .dietaryFatTotal, "Dietary Fat", .grams, canWrite: true),
    nutritionMetric(
      .dietaryProtein, .dietaryProtein, "Dietary Protein", .grams, canWrite: true),
    nutritionMetric(.dietaryFiber, .dietaryFiber, "Dietary Fiber", .grams),
    nutritionMetric(.dietarySugar, .dietarySugar, "Dietary Sugar", .grams),
    nutritionMetric(
      .dietaryCholesterol, .dietaryCholesterol, "Dietary Cholesterol", .milligrams),
    nutritionMetric(.dietaryCalcium, .dietaryCalcium, "Dietary Calcium", .milligrams),
    nutritionMetric(.dietaryChloride, .dietaryChloride, "Dietary Chloride", .milligrams),
    nutritionMetric(.dietaryIron, .dietaryIron, "Dietary Iron", .milligrams),
    nutritionMetric(.dietaryMagnesium, .dietaryMagnesium, "Dietary Magnesium", .milligrams),
    nutritionMetric(.dietaryManganese, .dietaryManganese, "Dietary Manganese", .milligrams),
    nutritionMetric(.dietaryPhosphorus, .dietaryPhosphorus, "Dietary Phosphorus", .milligrams),
    nutritionMetric(.dietaryPotassium, .dietaryPotassium, "Dietary Potassium", .milligrams),
    nutritionMetric(.dietarySodium, .dietarySodium, "Dietary Sodium", .milligrams),
    nutritionMetric(.dietaryZinc, .dietaryZinc, "Dietary Zinc", .milligrams),
    nutritionMetric(.dietaryCaffeine, .dietaryCaffeine, "Dietary Caffeine", .milligrams),
    nutritionMetric(.dietaryCopper, .dietaryCopper, "Dietary Copper", .milligrams),
    nutritionMetric(.dietaryNiacin, .dietaryNiacin, "Dietary Niacin", .milligrams),
    nutritionMetric(
      .dietaryPantothenicAcid, .dietaryPantothenicAcid, "Dietary Pantothenic Acid",
      .milligrams),
    nutritionMetric(
      .dietaryRiboflavin, .dietaryRiboflavin, "Dietary Riboflavin", .milligrams),
    nutritionMetric(.dietaryThiamin, .dietaryThiamin, "Dietary Thiamin", .milligrams),
    nutritionMetric(.dietaryVitaminB6, .dietaryVitaminB6, "Dietary Vitamin B6", .milligrams),
    nutritionMetric(.dietaryVitaminC, .dietaryVitaminC, "Dietary Vitamin C", .milligrams),
    nutritionMetric(.dietaryVitaminE, .dietaryVitaminE, "Dietary Vitamin E", .milligrams),
    nutritionMetric(.dietaryBiotin, .dietaryBiotin, "Dietary Biotin", .micrograms),
    nutritionMetric(.dietaryChromium, .dietaryChromium, "Dietary Chromium", .micrograms),
    nutritionMetric(.dietaryFolate, .dietaryFolate, "Dietary Folate", .micrograms),
    nutritionMetric(.dietaryIodine, .dietaryIodine, "Dietary Iodine", .micrograms),
    nutritionMetric(
      .dietaryMolybdenum, .dietaryMolybdenum, "Dietary Molybdenum", .micrograms),
    nutritionMetric(.dietarySelenium, .dietarySelenium, "Dietary Selenium", .micrograms),
    nutritionMetric(.dietaryVitaminA, .dietaryVitaminA, "Dietary Vitamin A", .micrograms),
    nutritionMetric(
      .dietaryVitaminB12, .dietaryVitaminB12, "Dietary Vitamin B12", .micrograms),
    nutritionMetric(.dietaryVitaminD, .dietaryVitaminD, "Dietary Vitamin D", .micrograms),
    nutritionMetric(.dietaryVitaminK, .dietaryVitaminK, "Dietary Vitamin K", .micrograms),
    metric(
      .lastAppleWorkout, .workout, "Last Apple Workout", .other, .none, .none,
      .latestWorkout, window: .trailingDays(30), background: true, transformation: .workout,
      bounds: 0...1),
  ]

  public static let selectable = all.filter { $0.availability == .available }

  public static let backfillEligible = selectable.filter {
    $0.bridgeUnit != .none
      && $0.bridgeUnit != .unixSeconds
      && $0.aggregation != .latestWorkout
  }

  public static let canonicalHealthBridgeIdentifiers = Set(
    all.map(\.id.rawValue) + ["last_sync_time", "test_connection"]
  )

  private static let definitionsByID = Dictionary(
    uniqueKeysWithValues: all.map { ($0.id, $0) }
  )

  public static subscript(id: MetricID) -> MetricDefinition? {
    definitionsByID[id]
  }
}

private func percentageMetric(
  _ id: MetricID,
  _ healthObjectType: HealthObjectTypeID,
  _ displayName: String,
  _ category: MetricCategory
) -> MetricDefinition {
  metric(
    id, healthObjectType, displayName, category, .fraction, .fraction, .latestSample,
    transformation: .percentageFraction, bounds: 0...1
  )
}

private func nutritionMetric(
  _ id: MetricID,
  _ healthObjectType: HealthObjectTypeID,
  _ displayName: String,
  _ unit: UnitSymbol,
  canWrite: Bool = false
) -> MetricDefinition {
  metric(
    id, healthObjectType, displayName, .other, unit, unit, .dailyCumulativeSum,
    canWrite: canWrite, bounds: 0...1_000_000
  )
}

private func sleepMetric(
  _ id: MetricID,
  _ displayName: String,
  _ bounds: ClosedRange<Double>
) -> MetricDefinition {
  metric(
    id,
    .sleepAnalysis,
    displayName,
    .sleep,
    .seconds,
    .seconds,
    .sleepStageDuration,
    window: .trailingDays(2),
    transformation: .sleepSeconds,
    bounds: bounds
  )
}

private func metric(
  _ id: MetricID,
  _ healthObjectType: HealthObjectTypeID,
  _ displayName: String,
  _ category: MetricCategory,
  _ healthKitUnit: UnitSymbol,
  _ bridgeUnit: UnitSymbol,
  _ aggregation: AggregationStrategy,
  window: SyncWindow = .currentDay,
  background: Bool = true,
  transformation: MetricTransformation = .unitConversion,
  canWrite: Bool = false,
  bounds: ClosedRange<Double>,
  availability: MetricAvailability = .available
) -> MetricDefinition {
  MetricDefinition(
    id: id,
    healthObjectType: healthObjectType,
    displayName: displayName,
    category: category,
    healthKitUnit: healthKitUnit,
    bridgeUnit: bridgeUnit,
    aggregation: aggregation,
    syncWindow: window,
    supportsBackgroundDelivery: background,
    canWriteToHealthKit: canWrite,
    minimumIOSMajorVersion: 18,
    transformation: transformation,
    validation: bounds,
    availability: availability
  )
}
