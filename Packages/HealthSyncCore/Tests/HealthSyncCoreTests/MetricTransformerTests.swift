import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Metric transformer")
struct MetricTransformerTests {
  private let timestamp = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Identity units preserve value and timestamp")
  func identityUnits() throws {
    let definition = try #require(MetricRegistry[.steps])
    let sample = HealthSample(timestamp: timestamp, value: 8_421, unit: .count)

    let reading = try MetricTransformer.transform(sample, using: definition)

    #expect(reading == MetricReading(metricID: .steps, timestamp: timestamp, value: 8_421))
  }

  @Test("Body mass converts pounds to kilograms")
  func poundsToKilograms() throws {
    let definition = try #require(MetricRegistry[.bodyMass])
    let sample = HealthSample(timestamp: timestamp, value: 180, unit: .pounds)

    let reading = try MetricTransformer.transform(sample, using: definition)

    #expect(abs(reading.value - 81.646_626_6) < 1e-9)
  }

  @Test(arguments: [Double.nan, .infinity, -.infinity])
  func rejectsNonFiniteValues(value: Double) throws {
    let definition = try #require(MetricRegistry[.restingHeartRate])
    let sample = HealthSample(timestamp: timestamp, value: value, unit: .beatsPerMinute)

    #expect(throws: MetricTransformationError.nonFiniteValue) {
      try MetricTransformer.transform(sample, using: definition)
    }
  }

  @Test(arguments: [-1.0, 250_001.0])
  func rejectsValuesOutsideInclusiveBounds(value: Double) throws {
    let definition = try #require(MetricRegistry[.steps])
    let sample = HealthSample(timestamp: timestamp, value: value, unit: .count)

    #expect(throws: MetricTransformationError.outOfRange) {
      try MetricTransformer.transform(sample, using: definition)
    }
  }

  @Test(arguments: [0.0, 250_000.0])
  func acceptsInclusiveBounds(value: Double) throws {
    let definition = try #require(MetricRegistry[.steps])
    let sample = HealthSample(timestamp: timestamp, value: value, unit: .count)

    let reading = try MetricTransformer.transform(sample, using: definition)

    #expect(reading.value == value)
  }

  @Test("Rejects dimensions that cannot be converted")
  func rejectsIncompatibleUnits() throws {
    let definition = try #require(MetricRegistry[.bodyMass])
    let sample = HealthSample(timestamp: timestamp, value: 80, unit: .beatsPerMinute)

    #expect(throws: MetricTransformationError.incompatibleUnit) {
      try MetricTransformer.transform(sample, using: definition)
    }
  }
}
