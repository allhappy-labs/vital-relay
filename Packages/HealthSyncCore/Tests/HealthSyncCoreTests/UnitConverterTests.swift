import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Typed unit conversion")
struct UnitConverterTests {
  @Test("Converts supported compatible dimensions")
  func convertsSupportedDimensions() throws {
    #expect(
      abs(try UnitConverter.convert(2.204_622_621_8, from: .pounds, to: .kilograms) - 1)
        < 0.000_001
    )
    #expect(try UnitConverter.convert(1, from: .metres, to: .centimetres) == 100)
    #expect(abs(try UnitConverter.convert(12, from: .inches, to: .feet) - 1) < 0.000_001)
    #expect(try UnitConverter.convert(32, from: .degreesFahrenheit, to: .degreesCelsius) == 0)
    #expect(try UnitConverter.convert(1, from: .kilocalories, to: .kilojoules) == 4.184)
    #expect(try UnitConverter.convert(1, from: .litres, to: .millilitres) == 1_000)
    #expect(
      abs(
        try UnitConverter.convert(180.182, from: .milligramsPerDecilitre, to: .millimolesPerLitre)
          - 10) < 0.000_001
    )
    #expect(try UnitConverter.convert(25, from: .percent, to: .fraction) == 0.25)
    #expect(
      abs(try UnitConverter.convert(1, from: .grams, to: .milligrams) - 1_000) < 0.000_001
    )
    #expect(
      abs(try UnitConverter.convert(1, from: .milligrams, to: .micrograms) - 1_000)
        < 0.000_001
    )
    #expect(try UnitConverter.convert(4, from: .internationalUnits, to: .internationalUnits) == 4)
    #expect(try UnitConverter.convert(60, from: .beatsPerMinute, to: .beatsPerMinute) == 60)
    #expect(try UnitConverter.convert(12, from: .breathsPerMinute, to: .breathsPerMinute) == 12)
  }

  @Test("Rejects incompatible dimensions and unsupported units")
  func rejectsIncompatibleDimensions() {
    #expect(throws: UnitConversionError.incompatibleUnits) {
      try UnitConverter.convert(1, from: .kilograms, to: .metres)
    }
    #expect(throws: UnitConversionError.unsupportedUnit) {
      try UnitConverter.convert(1, from: .stageCode, to: .stageCode)
    }
  }

  @Test("Rejects non-finite input and non-finite output")
  func rejectsNonFiniteValues() {
    #expect(throws: UnitConversionError.nonFiniteValue) {
      try UnitConverter.convert(.nan, from: .kilograms, to: .pounds)
    }
    #expect(throws: UnitConversionError.nonFiniteValue) {
      try UnitConverter.convert(.greatestFiniteMagnitude, from: .kilograms, to: .micrograms)
    }
  }
}
