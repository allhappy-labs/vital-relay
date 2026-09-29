import Foundation

public enum MetricID: String, Codable, CaseIterable, Sendable {
  case steps
  case distance
  case activeCalories = "active_calories"
  case basalEnergyBurned = "basal_energy_burned"
  case flightsClimbed = "flights_climbed"
  case exerciseTime = "exercise_time"
  case standTime = "stand_time"
  case timeInDaylight = "time_in_daylight"
  case walkingSpeed = "walking_speed"
  case walkingStepLength = "walking_step_length"
  case walkingAsymmetryPercentage = "walking_asymmetry_percentage"
  case walkingDoubleSupportPercentage = "walking_double_support_percentage"
  case swimmingDistance = "swimming_distance"
  case cyclingDistance = "cycling_distance"
  case runningPower = "running_power"
  case runningStrideLength = "running_stride_length"
  case runningGroundContactTime = "running_ground_contact_time"
  case runningVerticalOscillation = "running_vertical_oscillation"
  case cyclingPower = "cycling_power"
  case cyclingCadence = "cycling_cadence"
  case cyclingSpeed = "cycling_speed"
  case runningSpeed = "running_speed"
  case cyclingFunctionalThresholdPower = "cycling_functional_threshold_power"
  case swimmingStrokeCount = "swimming_stroke_count"
  case underwaterDepth = "underwater_depth"
  case waterTemperature = "water_temperature"
  case workoutEffortScore = "workout_effort_score"
  case estimatedWorkoutEffortScore = "estimated_workout_effort_score"
  case distanceRowing = "distance_rowing"
  case distancePaddleSports = "distance_paddle_sports"
  case distanceCrossCountrySkiing = "distance_cross_country_skiing"
  case distanceDownhillSnowSports = "distance_downhill_snow_sports"
  case distanceSkatingSports = "distance_skating_sports"
  case walkingSteadiness = "walking_steadiness"
  case cardioRecovery = "cardio_recovery"
  case physicalEffort = "physical_effort"
  case insulinDelivery = "insulin_delivery"
  case sixMinuteWalkTestDistance = "six_minute_walk_test_distance"
  case stairAscentSpeed = "stair_ascent_speed"
  case stairDescentSpeed = "stair_descent_speed"
  case bodyMass = "body_mass"
  case height
  case bodyFatPercentage = "body_fat_percentage"
  case leanBodyMass = "lean_body_mass"
  case waistCircumference = "waist_circumference"
  case bodyTemperature = "body_temperature"
  case heartRate = "heart_rate"
  case restingHeartRate = "resting_heart_rate"
  case walkingHeartRateAverage = "walking_heart_rate_average"
  case heartRateVariability = "heart_rate_variability"
  case oxygenSaturation = "oxygen_saturation"
  case respiratoryRate = "respiratory_rate"
  case vo2Max = "vo2_max"
  case wristTemperature = "wrist_temperature"
  case bloodPressureSystolic = "blood_pressure_systolic"
  case bloodPressureDiastolic = "blood_pressure_diastolic"
  case uvIndex = "uv_index"
  case uvExposureSED = "uv_exposure_sed"
  case netCalories = "net_calories"
  case headphoneAudioExposure = "headphone_audio_exposure"
  case environmentalAudioExposure = "environmental_audio_exposure"
  case sleepDuration = "sleep_duration"
  case sleepREM = "sleep_rem_hours"
  case sleepCore = "sleep_core_hours"
  case sleepDeep = "sleep_deep_hours"
  case sleepAwake = "sleep_awake_hours"
  case sleepUnspecified = "sleep_unspecified_hours"
  case asleepTime = "asleep_time"
  case wakeTime = "wake_time"
  case sleepDetails = "sleep_details"
  case mindfulMinutes = "mindful_minutes"
  case dietaryWater = "dietary_water"
  case dietaryEnergyConsumed = "dietary_energy_consumed"
  case bloodGlucose = "blood_glucose"
  case dietaryCarbohydrates = "dietary_carbohydrates"
  case dietaryFat = "dietary_fat"
  case dietaryProtein = "dietary_protein"
  case dietaryFiber = "dietary_fiber"
  case dietarySugar = "dietary_sugar"
  case dietaryCholesterol = "dietary_cholesterol"
  case dietaryCalcium = "dietary_calcium"
  case dietaryChloride = "dietary_chloride"
  case dietaryIron = "dietary_iron"
  case dietaryMagnesium = "dietary_magnesium"
  case dietaryManganese = "dietary_manganese"
  case dietaryPhosphorus = "dietary_phosphorus"
  case dietaryPotassium = "dietary_potassium"
  case dietarySodium = "dietary_sodium"
  case dietaryZinc = "dietary_zinc"
  case dietaryCaffeine = "dietary_caffeine"
  case dietaryCopper = "dietary_copper"
  case dietaryNiacin = "dietary_niacin"
  case dietaryPantothenicAcid = "dietary_pantothenic_acid"
  case dietaryRiboflavin = "dietary_riboflavin"
  case dietaryThiamin = "dietary_thiamin"
  case dietaryVitaminB6 = "dietary_vitamin_b6"
  case dietaryVitaminC = "dietary_vitamin_c"
  case dietaryVitaminE = "dietary_vitamin_e"
  case dietaryBiotin = "dietary_biotin"
  case dietaryChromium = "dietary_chromium"
  case dietaryFolate = "dietary_folate"
  case dietaryIodine = "dietary_iodine"
  case dietaryMolybdenum = "dietary_molybdenum"
  case dietarySelenium = "dietary_selenium"
  case dietaryVitaminA = "dietary_vitamin_a"
  case dietaryVitaminB12 = "dietary_vitamin_b12"
  case dietaryVitaminD = "dietary_vitamin_d"
  case dietaryVitaminK = "dietary_vitamin_k"
  case lastAppleWorkout = "last_apple_workout"
}

public enum HealthObjectTypeID: String, Codable, CaseIterable, Sendable {
  case stepCount = "HKQuantityTypeIdentifierStepCount"
  case distanceWalkingRunning = "HKQuantityTypeIdentifierDistanceWalkingRunning"
  case activeEnergyBurned = "HKQuantityTypeIdentifierActiveEnergyBurned"
  case basalEnergyBurned = "HKQuantityTypeIdentifierBasalEnergyBurned"
  case flightsClimbed = "HKQuantityTypeIdentifierFlightsClimbed"
  case appleExerciseTime = "HKQuantityTypeIdentifierAppleExerciseTime"
  case appleStandTime = "HKQuantityTypeIdentifierAppleStandTime"
  case timeInDaylight = "HKQuantityTypeIdentifierTimeInDaylight"
  case walkingSpeed = "HKQuantityTypeIdentifierWalkingSpeed"
  case walkingStepLength = "HKQuantityTypeIdentifierWalkingStepLength"
  case walkingAsymmetryPercentage = "HKQuantityTypeIdentifierWalkingAsymmetryPercentage"
  case walkingDoubleSupportPercentage =
    "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage"
  case distanceSwimming = "HKQuantityTypeIdentifierDistanceSwimming"
  case distanceCycling = "HKQuantityTypeIdentifierDistanceCycling"
  case runningPower = "HKQuantityTypeIdentifierRunningPower"
  case runningStrideLength = "HKQuantityTypeIdentifierRunningStrideLength"
  case runningGroundContactTime = "HKQuantityTypeIdentifierRunningGroundContactTime"
  case runningVerticalOscillation = "HKQuantityTypeIdentifierRunningVerticalOscillation"
  case cyclingPower = "HKQuantityTypeIdentifierCyclingPower"
  case cyclingCadence = "HKQuantityTypeIdentifierCyclingCadence"
  case cyclingSpeed = "HKQuantityTypeIdentifierCyclingSpeed"
  case runningSpeed = "HKQuantityTypeIdentifierRunningSpeed"
  case cyclingFunctionalThresholdPower = "HKQuantityTypeIdentifierCyclingFunctionalThresholdPower"
  case swimmingStrokeCount = "HKQuantityTypeIdentifierSwimmingStrokeCount"
  case underwaterDepth = "HKQuantityTypeIdentifierUnderwaterDepth"
  case waterTemperature = "HKQuantityTypeIdentifierWaterTemperature"
  case workoutEffortScore = "HKQuantityTypeIdentifierWorkoutEffortScore"
  case estimatedWorkoutEffortScore = "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore"
  case distanceRowing = "HKQuantityTypeIdentifierDistanceRowing"
  case distancePaddleSports = "HKQuantityTypeIdentifierDistancePaddleSports"
  case distanceCrossCountrySkiing = "HKQuantityTypeIdentifierDistanceCrossCountrySkiing"
  case distanceDownhillSnowSports = "HKQuantityTypeIdentifierDistanceDownhillSnowSports"
  case distanceSkatingSports = "HKQuantityTypeIdentifierDistanceSkatingSports"
  case appleWalkingSteadiness = "HKQuantityTypeIdentifierAppleWalkingSteadiness"
  case heartRateRecoveryOneMinute = "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
  case physicalEffort = "HKQuantityTypeIdentifierPhysicalEffort"
  case insulinDelivery = "HKQuantityTypeIdentifierInsulinDelivery"
  case sixMinuteWalkTestDistance = "HKQuantityTypeIdentifierSixMinuteWalkTestDistance"
  case stairAscentSpeed = "HKQuantityTypeIdentifierStairAscentSpeed"
  case stairDescentSpeed = "HKQuantityTypeIdentifierStairDescentSpeed"
  case bodyMass = "HKQuantityTypeIdentifierBodyMass"
  case height = "HKQuantityTypeIdentifierHeight"
  case bodyFatPercentage = "HKQuantityTypeIdentifierBodyFatPercentage"
  case leanBodyMass = "HKQuantityTypeIdentifierLeanBodyMass"
  case waistCircumference = "HKQuantityTypeIdentifierWaistCircumference"
  case bodyTemperature = "HKQuantityTypeIdentifierBodyTemperature"
  case heartRate = "HKQuantityTypeIdentifierHeartRate"
  case restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
  case walkingHeartRateAverage = "HKQuantityTypeIdentifierWalkingHeartRateAverage"
  case heartRateVariabilitySDNN = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
  case oxygenSaturation = "HKQuantityTypeIdentifierOxygenSaturation"
  case respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"
  case vo2Max = "HKQuantityTypeIdentifierVO2Max"
  case appleSleepingWristTemperature = "HKQuantityTypeIdentifierAppleSleepingWristTemperature"
  case sleepAnalysis = "HKCategoryTypeIdentifierSleepAnalysis"
  case mindfulSession = "HKCategoryTypeIdentifierMindfulSession"
  case dietaryWater = "HKQuantityTypeIdentifierDietaryWater"
  case dietaryEnergyConsumed = "HKQuantityTypeIdentifierDietaryEnergyConsumed"
  case bloodGlucose = "HKQuantityTypeIdentifierBloodGlucose"
  case dietaryCarbohydrates = "HKQuantityTypeIdentifierDietaryCarbohydrates"
  case dietaryFatTotal = "HKQuantityTypeIdentifierDietaryFatTotal"
  case dietaryProtein = "HKQuantityTypeIdentifierDietaryProtein"
  case bloodPressureSystolic = "HKQuantityTypeIdentifierBloodPressureSystolic"
  case bloodPressureDiastolic = "HKQuantityTypeIdentifierBloodPressureDiastolic"
  case uvExposure = "HKQuantityTypeIdentifierUVExposure"
  case headphoneAudioExposure = "HKQuantityTypeIdentifierHeadphoneAudioExposure"
  case environmentalAudioExposure = "HKQuantityTypeIdentifierEnvironmentalAudioExposure"
  case dietaryFiber = "HKQuantityTypeIdentifierDietaryFiber"
  case dietarySugar = "HKQuantityTypeIdentifierDietarySugar"
  case dietaryCholesterol = "HKQuantityTypeIdentifierDietaryCholesterol"
  case dietaryCalcium = "HKQuantityTypeIdentifierDietaryCalcium"
  case dietaryChloride = "HKQuantityTypeIdentifierDietaryChloride"
  case dietaryIron = "HKQuantityTypeIdentifierDietaryIron"
  case dietaryMagnesium = "HKQuantityTypeIdentifierDietaryMagnesium"
  case dietaryManganese = "HKQuantityTypeIdentifierDietaryManganese"
  case dietaryPhosphorus = "HKQuantityTypeIdentifierDietaryPhosphorus"
  case dietaryPotassium = "HKQuantityTypeIdentifierDietaryPotassium"
  case dietarySodium = "HKQuantityTypeIdentifierDietarySodium"
  case dietaryZinc = "HKQuantityTypeIdentifierDietaryZinc"
  case dietaryCaffeine = "HKQuantityTypeIdentifierDietaryCaffeine"
  case dietaryCopper = "HKQuantityTypeIdentifierDietaryCopper"
  case dietaryNiacin = "HKQuantityTypeIdentifierDietaryNiacin"
  case dietaryPantothenicAcid = "HKQuantityTypeIdentifierDietaryPantothenicAcid"
  case dietaryRiboflavin = "HKQuantityTypeIdentifierDietaryRiboflavin"
  case dietaryThiamin = "HKQuantityTypeIdentifierDietaryThiamin"
  case dietaryVitaminB6 = "HKQuantityTypeIdentifierDietaryVitaminB6"
  case dietaryVitaminC = "HKQuantityTypeIdentifierDietaryVitaminC"
  case dietaryVitaminE = "HKQuantityTypeIdentifierDietaryVitaminE"
  case dietaryBiotin = "HKQuantityTypeIdentifierDietaryBiotin"
  case dietaryChromium = "HKQuantityTypeIdentifierDietaryChromium"
  case dietaryFolate = "HKQuantityTypeIdentifierDietaryFolate"
  case dietaryIodine = "HKQuantityTypeIdentifierDietaryIodine"
  case dietaryMolybdenum = "HKQuantityTypeIdentifierDietaryMolybdenum"
  case dietarySelenium = "HKQuantityTypeIdentifierDietarySelenium"
  case dietaryVitaminA = "HKQuantityTypeIdentifierDietaryVitaminA"
  case dietaryVitaminB12 = "HKQuantityTypeIdentifierDietaryVitaminB12"
  case dietaryVitaminD = "HKQuantityTypeIdentifierDietaryVitaminD"
  case dietaryVitaminK = "HKQuantityTypeIdentifierDietaryVitaminK"
  case noDirectHealthKitType = "HAHealthSyncNoDirectHealthKitType"
  case workout = "HKWorkoutType"
}

public enum UnitSymbol: String, Codable, CaseIterable, Sendable {
  case count
  case metres = "m"
  case centimetres = "cm"
  case miles = "mi"
  case feet = "ft"
  case inches = "in"
  case kilograms = "kg"
  case pounds = "lb"
  case grams = "g"
  case milligrams = "mg"
  case micrograms = "µg"
  case kilocalories = "kcal"
  case kilojoules = "kJ"
  case minutes = "min"
  case seconds = "s"
  case milliseconds = "ms"
  case fraction
  case percent = "%"
  case beatsPerMinute = "count/min"
  case breathsPerMinute = "breaths/min"
  case millilitresPerKilogramMinute = "mL/kg/min"
  case degreesCelsius = "degC"
  case degreesFahrenheit = "degF"
  case millilitres = "mL"
  case litres = "L"
  case millimolesPerLitre = "mmol/L"
  case milligramsPerDecilitre = "mg/dL"
  case internationalUnits = "IU"
  case unixSeconds
  case stageCode
  case unitless
  case metresPerSecond = "m/s"
  case watts = "W"
  case revolutionsPerMinute = "rpm"
  case appleEffortScore = "appleEffortScore"
  case millimetresOfMercury = "mmHg"
  case metabolicEquivalent = "MET"
  case decibelsAWeighted = "dBA"
  case standardErythemaDose = "SED"
  case none
}

public enum MetricAvailability: String, Codable, Sendable, Equatable {
  case available
  case noHealthKitSource
}

public enum MetricCategory: String, Codable, CaseIterable, Sendable {
  case activity
  case bodyMeasurements
  case vitals
  case sleep
  case other
}

public enum AggregationStrategy: String, Codable, CaseIterable, Sendable {
  case latestSample
  case dailyCumulativeSum
  case dailyAverage
  case dailyMinimum
  case dailyMaximum
  case sleepStageDuration
  case latestWorkout
  case intervalDuration
  case categoryStateConversion
}

public enum SyncWindow: Sendable, Equatable {
  case currentDay
  case trailingDays(Int)
}

public enum MetricTransformation: String, Codable, CaseIterable, Sendable {
  case unitConversion
  case percentageFraction
  case sleepSeconds
  case timestamp
  case stageCode
  case workout
}

public struct MetricDefinition: Sendable, Equatable {
  public let id: MetricID
  public let healthObjectType: HealthObjectTypeID
  public let displayName: String
  public let category: MetricCategory
  public let healthKitUnit: UnitSymbol
  public let bridgeUnit: UnitSymbol
  public let aggregation: AggregationStrategy
  public let syncWindow: SyncWindow
  public let supportsBackgroundDelivery: Bool
  public let canWriteToHealthKit: Bool
  public let minimumIOSMajorVersion: Int
  public let transformation: MetricTransformation
  public let validation: ClosedRange<Double>
  public let availability: MetricAvailability

  public init(
    id: MetricID,
    healthObjectType: HealthObjectTypeID,
    displayName: String,
    category: MetricCategory,
    healthKitUnit: UnitSymbol,
    bridgeUnit: UnitSymbol,
    aggregation: AggregationStrategy,
    syncWindow: SyncWindow,
    supportsBackgroundDelivery: Bool,
    canWriteToHealthKit: Bool,
    minimumIOSMajorVersion: Int,
    transformation: MetricTransformation,
    validation: ClosedRange<Double>,
    availability: MetricAvailability = .available
  ) {
    self.id = id
    self.healthObjectType = healthObjectType
    self.displayName = displayName
    self.category = category
    self.healthKitUnit = healthKitUnit
    self.bridgeUnit = bridgeUnit
    self.aggregation = aggregation
    self.syncWindow = syncWindow
    self.supportsBackgroundDelivery = supportsBackgroundDelivery
    self.canWriteToHealthKit = canWriteToHealthKit
    self.minimumIOSMajorVersion = minimumIOSMajorVersion
    self.transformation = transformation
    self.validation = validation
    self.availability = availability
  }
}

public struct HealthSample: Sendable, Equatable {
  public let id: UUID
  public let startDate: Date
  public let endDate: Date
  public let timestamp: Date
  public let value: Double
  public let unit: UnitSymbol
  public let sourceBundleIdentifier: String
  public let isUserEntered: Bool
  public let isFromThisApplication: Bool
  public let isImportedFromHomeAssistant: Bool

  public init(
    id: UUID = UUID(),
    startDate: Date? = nil,
    endDate: Date? = nil,
    timestamp: Date,
    value: Double,
    unit: UnitSymbol,
    sourceBundleIdentifier: String = "",
    isUserEntered: Bool = false,
    isFromThisApplication: Bool = false,
    isImportedFromHomeAssistant: Bool = false
  ) {
    self.id = id
    self.startDate = startDate ?? timestamp
    self.endDate = endDate ?? timestamp
    self.timestamp = timestamp
    self.value = value
    self.unit = unit
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.isUserEntered = isUserEntered
    self.isFromThisApplication = isFromThisApplication
    self.isImportedFromHomeAssistant = isImportedFromHomeAssistant
  }

  public init(
    id: UUID = UUID(),
    startDate: Date,
    endDate: Date,
    value: Double,
    unit: UnitSymbol,
    sourceBundleIdentifier: String = "",
    isUserEntered: Bool = false,
    isFromThisApplication: Bool = false,
    isImportedFromHomeAssistant: Bool = false
  ) {
    self.init(
      id: id,
      startDate: startDate,
      endDate: endDate,
      timestamp: endDate,
      value: value,
      unit: unit,
      sourceBundleIdentifier: sourceBundleIdentifier,
      isUserEntered: isUserEntered,
      isFromThisApplication: isFromThisApplication,
      isImportedFromHomeAssistant: isImportedFromHomeAssistant
    )
  }
}

public struct MetricReading: Sendable, Equatable {
  public let metricID: MetricID
  public let timestamp: Date
  public let value: Double

  public init(metricID: MetricID, timestamp: Date, value: Double) {
    self.metricID = metricID
    self.timestamp = timestamp
    self.value = value
  }
}
