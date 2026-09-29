import HealthKit
import HealthSyncCore

enum HealthKitTypeResolverError: Error, Equatable, Sendable {
  case unavailableType
  case unsupportedUnit
}

enum HealthKitTypeResolver {
  static func objectType(for identifier: HealthObjectTypeID) throws -> HKObjectType {
    switch identifier {
    case .sleepAnalysis:
      guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
        throw HealthKitTypeResolverError.unavailableType
      }
      return type
    case .mindfulSession:
      guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
        throw HealthKitTypeResolverError.unavailableType
      }
      return type
    case .workout:
      return HKObjectType.workoutType()
    case .noDirectHealthKitType:
      throw HealthKitTypeResolverError.unavailableType
    default:
      return try quantityType(for: identifier)
    }
  }

  static func quantityType(for identifier: HealthObjectTypeID) throws -> HKQuantityType {
    try quantityType(identifier: identifier.rawValue)
  }

  static func quantityType(identifier: String) throws -> HKQuantityType {
    let healthKitIdentifier = HKQuantityTypeIdentifier(rawValue: identifier)
    guard let type = HKObjectType.quantityType(forIdentifier: healthKitIdentifier) else {
      throw HealthKitTypeResolverError.unavailableType
    }
    return type
  }

  static func unit(for symbol: UnitSymbol) throws -> HKUnit {
    switch symbol {
    case .count:
      return .count()
    case .metres:
      return .meter()
    case .centimetres:
      return .meterUnit(with: .centi)
    case .miles:
      return .mile()
    case .feet:
      return .foot()
    case .inches:
      return .inch()
    case .kilograms:
      return .gramUnit(with: .kilo)
    case .pounds:
      return .pound()
    case .grams:
      return .gram()
    case .milligrams:
      return .gramUnit(with: .milli)
    case .micrograms:
      return .gramUnit(with: .micro)
    case .kilocalories:
      return .kilocalorie()
    case .kilojoules:
      return .jouleUnit(with: .kilo)
    case .minutes:
      return .minute()
    case .seconds:
      return .second()
    case .milliseconds:
      return .secondUnit(with: .milli)
    case .fraction, .percent:
      return .percent()
    case .beatsPerMinute:
      return .count().unitDivided(by: .minute())
    case .breathsPerMinute:
      return .count().unitDivided(by: .minute())
    case .millilitresPerKilogramMinute:
      return .literUnit(with: .milli)
        .unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))
    case .degreesCelsius:
      return .degreeCelsius()
    case .degreesFahrenheit:
      return .degreeFahrenheit()
    case .millilitres:
      return .literUnit(with: .milli)
    case .litres:
      return .liter()
    case .millimolesPerLitre:
      return .moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose)
        .unitDivided(by: .liter())
    case .milligramsPerDecilitre:
      return .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    case .internationalUnits:
      return .internationalUnit()
    case .unitless:
      return .count()
    case .metresPerSecond:
      return .meter().unitDivided(by: .second())
    case .watts:
      return .watt()
    case .revolutionsPerMinute:
      return .count().unitDivided(by: .minute())
    case .appleEffortScore:
      return .appleEffortScore()
    case .millimetresOfMercury:
      return .millimeterOfMercury()
    case .metabolicEquivalent:
      return .kilocalorie().unitDivided(
        by: .gramUnit(with: .kilo).unitMultiplied(by: .hour())
      )
    case .decibelsAWeighted:
      return .decibelAWeightedSoundPressureLevel()
    case .standardErythemaDose:
      throw HealthKitTypeResolverError.unsupportedUnit
    case .unixSeconds, .stageCode, .none:
      throw HealthKitTypeResolverError.unsupportedUnit
    }
  }
}
