public enum WritableHealthRegistry: Sendable {
  public static let all: [WritableHealthType] = [
    destination(.bodyMass, "Body Mass", .bodyMeasurements, .kilograms, 0.5...700),
    destination(.height, "Height", .bodyMeasurements, .metres, 0.2...3),
    destination(
      .bodyFatPercentage,
      "Body Fat Percentage",
      .bodyMeasurements,
      .fraction,
      0...1
    ),
    destination(
      .leanBodyMass,
      "Lean Body Mass",
      .bodyMeasurements,
      .kilograms,
      0.1...500
    ),
    destination(.bodyTemperature, "Body Temperature", .vitals, .degreesCelsius, 20...50),
    destination(.heartRate, "Heart Rate", .vitals, .beatsPerMinute, 10...350),
    destination(.oxygenSaturation, "Blood Oxygen", .vitals, .fraction, 0...1),
    destination(
      .respiratoryRate,
      "Respiratory Rate",
      .vitals,
      .breathsPerMinute,
      1...100
    ),
    destination(.uvExposure, "UV Exposure", .vitals, .unitless, 0...50, ios: 9),
    destination(.dietaryWater, "Dietary Water", .other, .millilitres, 0...100_000, ios: 9),
    destination(
      .dietaryEnergyConsumed,
      "Dietary Energy",
      .other,
      .kilocalories,
      0...100_000
    ),
    destination(
      .bloodGlucose,
      "Blood Glucose",
      .other,
      .millimolesPerLitre,
      0.1...100
    ),
    destination(.dietaryCarbohydrates, "Dietary Carbohydrates", .other, .grams, 0...10_000),
    destination(.dietaryFatTotal, "Dietary Fat", .other, .grams, 0...10_000),
    destination(.dietaryProtein, "Dietary Protein", .other, .grams, 0...10_000),
    destination(
      .insulinDelivery,
      "Insulin Delivery",
      .other,
      .internationalUnits,
      0...10_000,
      ios: 11
    ),
  ]

  private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

  public static subscript(id: HealthObjectTypeID) -> WritableHealthType? {
    byID[id]
  }
}

private func destination(
  _ id: HealthObjectTypeID,
  _ displayName: String,
  _ category: MetricCategory,
  _ unit: UnitSymbol,
  _ bounds: ClosedRange<Double>,
  ios: Int = 8
) -> WritableHealthType {
  WritableHealthType(
    id: id,
    displayName: displayName,
    category: category,
    nativeUnit: unit,
    plausibleBounds: bounds,
    minimumIOSMajorVersion: ios
  )
}
