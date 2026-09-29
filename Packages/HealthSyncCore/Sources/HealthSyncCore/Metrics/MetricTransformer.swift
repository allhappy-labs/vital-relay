public enum MetricTransformationError: Error, Equatable, Sendable {
  case nonFiniteValue
  case incompatibleUnit
  case outOfRange
}

public enum MetricTransformer: Sendable {
  public static func transform(
    _ sample: HealthSample,
    using definition: MetricDefinition
  ) throws -> MetricReading {
    guard sample.value.isFinite else {
      throw MetricTransformationError.nonFiniteValue
    }

    let transformedValue = try transformedValue(
      sample.value,
      from: sample.unit,
      to: definition.bridgeUnit,
      transformation: definition.transformation
    )

    guard transformedValue.isFinite else {
      throw MetricTransformationError.nonFiniteValue
    }
    guard definition.validation.contains(transformedValue) else {
      throw MetricTransformationError.outOfRange
    }

    return MetricReading(
      metricID: definition.id,
      timestamp: sample.timestamp,
      value: transformedValue
    )
  }

  private static func transformedValue(
    _ value: Double,
    from sourceUnit: UnitSymbol,
    to destinationUnit: UnitSymbol,
    transformation: MetricTransformation
  ) throws -> Double {
    switch transformation {
    case .unitConversion:
      return try convert(value, from: sourceUnit, to: destinationUnit)
    case .percentageFraction:
      switch (sourceUnit, destinationUnit) {
      case (.fraction, .fraction):
        return value
      case (.percent, .fraction):
        return value / 100
      default:
        throw MetricTransformationError.incompatibleUnit
      }
    case .sleepSeconds:
      guard sourceUnit == .seconds, destinationUnit == .seconds else {
        throw MetricTransformationError.incompatibleUnit
      }
      return value
    case .timestamp:
      guard sourceUnit == .unixSeconds, destinationUnit == .unixSeconds else {
        throw MetricTransformationError.incompatibleUnit
      }
      return value
    case .stageCode:
      guard sourceUnit == .stageCode, destinationUnit == .stageCode else {
        throw MetricTransformationError.incompatibleUnit
      }
      return value
    case .workout:
      throw MetricTransformationError.incompatibleUnit
    }
  }

  private static func convert(
    _ value: Double,
    from sourceUnit: UnitSymbol,
    to destinationUnit: UnitSymbol
  ) throws -> Double {
    if sourceUnit == destinationUnit {
      return value
    }

    switch (sourceUnit, destinationUnit) {
    case (.miles, .metres):
      return value * 1_609.344
    case (.feet, .metres):
      return value * 0.3048
    case (.pounds, .kilograms):
      return value * 0.453_592_37
    case (.kilograms, .pounds):
      return value / 0.453_592_37
    case (.kilojoules, .kilocalories):
      return value / 4.184
    case (.minutes, .seconds):
      return value * 60
    case (.seconds, .minutes):
      return value / 60
    case (.litres, .millilitres):
      return value * 1_000
    case (.milligramsPerDecilitre, .millimolesPerLitre):
      return value / 18.0182
    case (.degreesFahrenheit, .degreesCelsius):
      return (value - 32) * 5 / 9
    default:
      throw MetricTransformationError.incompatibleUnit
    }
  }
}
