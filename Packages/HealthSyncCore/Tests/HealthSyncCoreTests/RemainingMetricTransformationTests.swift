import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Remaining metric transformations")
struct RemainingMetricTransformationTests {
  @Test("Mass-scale nutrition metrics preserve exact bridge units")
  func nutritionScales() throws {
    let expected: [MetricID: UnitSymbol] = [
      .dietaryCarbohydrates: .grams,
      .dietaryFat: .grams,
      .dietaryProtein: .grams,
      .dietaryFiber: .grams,
      .dietaryCalcium: .milligrams,
      .dietarySodium: .milligrams,
      .dietaryVitaminB12: .micrograms,
      .dietaryVitaminD: .micrograms,
    ]

    for (id, unit) in expected {
      let definition = try #require(MetricRegistry[id])
      let reading = try MetricTransformer.transform(
        HealthSample(timestamp: .now, value: 1.25, unit: unit),
        using: definition
      )
      #expect(definition.healthKitUnit == unit)
      #expect(definition.bridgeUnit == unit)
      #expect(reading.value == 1.25)
    }
  }

  @Test("Mobility vitals effort and audio use source-confirmed units")
  func exactUnits() throws {
    let expected: [MetricID: UnitSymbol] = [
      .walkingSpeed: .metresPerSecond,
      .walkingStepLength: .metres,
      .cardioRecovery: .beatsPerMinute,
      .physicalEffort: .metabolicEquivalent,
      .bloodPressureSystolic: .millimetresOfMercury,
      .bloodPressureDiastolic: .millimetresOfMercury,
      .headphoneAudioExposure: .decibelsAWeighted,
      .environmentalAudioExposure: .decibelsAWeighted,
      .insulinDelivery: .internationalUnits,
    ]

    for (id, unit) in expected {
      let definition = try #require(MetricRegistry[id])
      #expect(definition.healthKitUnit == unit)
      #expect(definition.bridgeUnit == unit)
      let reading = try MetricTransformer.transform(
        HealthSample(timestamp: .now, value: definition.validation.lowerBound, unit: unit),
        using: definition
      )
      #expect(reading.metricID == id)
    }
  }
}
