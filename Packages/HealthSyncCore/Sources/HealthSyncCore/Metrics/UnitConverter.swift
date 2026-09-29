public enum UnitConversionError: Error, Sendable, Equatable {
  case unsupportedUnit
  case incompatibleUnits
  case nonFiniteValue
}

public enum UnitConverter: Sendable {
  public static func convert(
    _ value: Double,
    from source: UnitSymbol,
    to destination: UnitSymbol
  ) throws -> Double {
    guard value.isFinite else { throw UnitConversionError.nonFiniteValue }
    guard let sourceDefinition = definition(for: source),
      let destinationDefinition = definition(for: destination)
    else {
      throw UnitConversionError.unsupportedUnit
    }
    guard sourceDefinition.dimension == destinationDefinition.dimension else {
      throw UnitConversionError.incompatibleUnits
    }

    let baseValue = sourceDefinition.toBase(value)
    let converted = destinationDefinition.fromBase(baseValue)
    guard baseValue.isFinite, converted.isFinite else {
      throw UnitConversionError.nonFiniteValue
    }
    return converted
  }

  private static func definition(for unit: UnitSymbol) -> Definition? {
    switch unit {
    case .count:
      Definition(dimension: .count)
    case .metres:
      Definition(dimension: .length)
    case .centimetres:
      Definition(dimension: .length, scale: 0.01)
    case .miles:
      Definition(dimension: .length, scale: 1_609.344)
    case .feet:
      Definition(dimension: .length, scale: 0.3048)
    case .inches:
      Definition(dimension: .length, scale: 0.0254)
    case .kilograms:
      Definition(dimension: .mass)
    case .pounds:
      Definition(dimension: .mass, scale: 0.453_592_37)
    case .grams:
      Definition(dimension: .mass, scale: 0.001)
    case .milligrams:
      Definition(dimension: .mass, scale: 0.000_001)
    case .micrograms:
      Definition(dimension: .mass, scale: 0.000_000_001)
    case .kilocalories:
      Definition(dimension: .energy)
    case .kilojoules:
      Definition(dimension: .energy, scale: 1 / 4.184)
    case .minutes:
      Definition(dimension: .time, scale: 60)
    case .seconds:
      Definition(dimension: .time)
    case .milliseconds:
      Definition(dimension: .time, scale: 0.001)
    case .fraction:
      Definition(dimension: .proportion)
    case .percent:
      Definition(dimension: .proportion, scale: 0.01)
    case .beatsPerMinute:
      Definition(dimension: .heartRate)
    case .breathsPerMinute:
      Definition(dimension: .respiratoryRate)
    case .degreesCelsius:
      Definition(dimension: .temperature)
    case .degreesFahrenheit:
      Definition(
        dimension: .temperature,
        toBase: { ($0 - 32) * 5 / 9 },
        fromBase: { ($0 * 9 / 5) + 32 }
      )
    case .millilitres:
      Definition(dimension: .volume)
    case .litres:
      Definition(dimension: .volume, scale: 1_000)
    case .millimolesPerLitre:
      Definition(dimension: .glucoseConcentration)
    case .milligramsPerDecilitre:
      Definition(dimension: .glucoseConcentration, scale: 1 / 18.0182)
    case .internationalUnits:
      Definition(dimension: .internationalUnits)
    case .unitless:
      Definition(dimension: .unitless)
    case .metresPerSecond:
      Definition(dimension: .speed)
    case .watts:
      Definition(dimension: .power)
    case .revolutionsPerMinute:
      Definition(dimension: .cadence)
    case .appleEffortScore:
      Definition(dimension: .effortScore)
    case .millimetresOfMercury:
      Definition(dimension: .pressure)
    case .metabolicEquivalent:
      Definition(dimension: .metabolicEquivalent)
    case .decibelsAWeighted:
      Definition(dimension: .soundExposure)
    case .standardErythemaDose:
      Definition(dimension: .erythemaDose)
    case .millilitresPerKilogramMinute:
      Definition(dimension: .oxygenConsumption)
    case .unixSeconds, .stageCode, .none:
      nil
    }
  }
}

extension UnitConverter {
  fileprivate enum Dimension: Sendable {
    case count
    case length
    case mass
    case energy
    case time
    case proportion
    case heartRate
    case respiratoryRate
    case temperature
    case volume
    case glucoseConcentration
    case internationalUnits
    case unitless
    case speed
    case power
    case cadence
    case effortScore
    case pressure
    case metabolicEquivalent
    case soundExposure
    case erythemaDose
    case oxygenConsumption
  }

  fileprivate struct Definition: Sendable {
    let dimension: Dimension
    let toBase: @Sendable (Double) -> Double
    let fromBase: @Sendable (Double) -> Double

    init(dimension: Dimension, scale: Double = 1) {
      self.dimension = dimension
      self.toBase = { $0 * scale }
      self.fromBase = { $0 / scale }
    }

    init(
      dimension: Dimension,
      toBase: @escaping @Sendable (Double) -> Double,
      fromBase: @escaping @Sendable (Double) -> Double
    ) {
      self.dimension = dimension
      self.toBase = toBase
      self.fromBase = fromBase
    }
  }
}
