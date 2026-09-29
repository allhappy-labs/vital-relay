import Foundation

public enum HomeAssistantStateValidationError: Error, Sendable, Equatable {
  case invalidState
  case entityMismatch
  case missingUnit
  case unsupportedUnit
  case unitMismatch
  case outOfBounds
}

public enum HomeAssistantStateParser: Sendable {
  public static func normalize(
    _ state: HomeAssistantState,
    for pairing: Pairing
  ) throws -> NormalizedHomeAssistantState {
    guard state.entityID == pairing.entityID else {
      throw HomeAssistantStateValidationError.entityMismatch
    }
    guard isStrictNumber(state.state), let rawValue = Double(state.state), rawValue.isFinite else {
      throw HomeAssistantStateValidationError.invalidState
    }
    let stateUnit: UnitSymbol
    if let unitText = state.attributes.unitOfMeasurement, !unitText.isEmpty {
      do {
        stateUnit = try HomeAssistantUnitParser.parse(unitText)
      } catch {
        throw HomeAssistantStateValidationError.unsupportedUnit
      }
    } else if pairing.sourceUnit == .unitless {
      stateUnit = .unitless
    } else {
      throw HomeAssistantStateValidationError.missingUnit
    }
    guard stateUnit == pairing.sourceUnit else {
      throw HomeAssistantStateValidationError.unitMismatch
    }
    guard let destination = WritableHealthRegistry[pairing.destination] else {
      throw HomeAssistantStateValidationError.outOfBounds
    }

    let transformed: Double
    let normalized: Double
    do {
      transformed = try pairing.transformation.apply(to: rawValue)
      normalized = try UnitConverter.convert(
        transformed,
        from: pairing.sourceUnit,
        to: pairing.destinationUnit
      )
    } catch {
      throw HomeAssistantStateValidationError.invalidState
    }
    guard normalized.isFinite, destination.plausibleBounds.contains(normalized) else {
      throw HomeAssistantStateValidationError.outOfBounds
    }

    return NormalizedHomeAssistantState(
      entityID: state.entityID,
      lastUpdated: state.lastUpdated,
      normalizedValue: normalized,
      destination: pairing.destination
    )
  }

  private static func isStrictNumber(_ value: String) -> Bool {
    value.range(
      of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
      options: .regularExpression
    ) != nil
  }
}

public enum HomeAssistantUnitParser: Sendable {
  public static func parse(_ value: String) throws -> UnitSymbol {
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
      throw HomeAssistantStateValidationError.unsupportedUnit
    }
    if let exact = UnitSymbol(rawValue: value) {
      return exact
    }

    switch value.lowercased() {
    case "lbs": return .pounds
    case "c", "°c": return .degreesCelsius
    case "f", "°f": return .degreesFahrenheit
    case "ml": return .millilitres
    case "l": return .litres
    case "kj": return .kilojoules
    case "ug", "mcg": return .micrograms
    case "bpm": return .beatsPerMinute
    case "iu": return .internationalUnits
    case "uv index": return .unitless
    default: throw HomeAssistantStateValidationError.unsupportedUnit
    }
  }
}
