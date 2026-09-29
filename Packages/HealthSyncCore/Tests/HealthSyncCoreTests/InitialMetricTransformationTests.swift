import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Initial metric transformations")
struct InitialMetricTransformationTests {
  private let timestamp = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Converts supported HealthKit dimensions into bridge inputs")
  func conversions() throws {
    try expect(.distance, value: 1, unit: .miles, equals: 1_609.344)
    try expect(.height, value: 6, unit: .feet, equals: 1.8288)
    try expect(.bodyMass, value: 180, unit: .pounds, equals: 81.646_626_6)
    try expect(.activeCalories, value: 418.4, unit: .kilojoules, equals: 100)
    try expect(.timeInDaylight, value: 30, unit: .minutes, equals: 1_800)
    try expect(.dietaryWater, value: 2.5, unit: .litres, equals: 2_500)
    try expect(.bloodGlucose, value: 180.182, unit: .milligramsPerDecilitre, equals: 10)
    try expect(.wristTemperature, value: 98.6, unit: .degreesFahrenheit, equals: 37)
  }

  @Test("Preserves HealthKit percentage fractions for integration normalization")
  func percentageFractions() throws {
    try expect(.oxygenSaturation, value: 0.975, unit: .fraction, equals: 0.975)
    try expect(.bodyFatPercentage, value: 25, unit: .percent, equals: 0.25)
  }

  @Test("Sleep durations remain seconds on the wire")
  func sleepSeconds() throws {
    try expect(.sleepDuration, value: 28_800, unit: .seconds, equals: 28_800)
  }

  @Test("Workout definitions reject scalar transformation")
  func workoutIsSpecialPayload() throws {
    let definition = try #require(MetricRegistry[.lastAppleWorkout])
    let sample = HealthSample(timestamp: timestamp, value: 0, unit: .none)
    #expect(throws: MetricTransformationError.incompatibleUnit) {
      try MetricTransformer.transform(sample, using: definition)
    }
  }

  private func expect(
    _ id: MetricID,
    value: Double,
    unit: UnitSymbol,
    equals expected: Double
  ) throws {
    let definition = try #require(MetricRegistry[id])
    let sample = HealthSample(timestamp: timestamp, value: value, unit: unit)
    let reading = try MetricTransformer.transform(sample, using: definition)
    #expect(abs(reading.value - expected) < 0.000_001)
  }
}
