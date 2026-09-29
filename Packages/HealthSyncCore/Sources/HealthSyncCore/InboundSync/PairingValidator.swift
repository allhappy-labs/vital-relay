import Foundation

public enum PairingValidationError: Error, Codable, Sendable, Equatable {
  case invalidEntityID
  case destinationNotWritable
  case incompatibleUnits
  case invalidDestinationUnit
  case nonFiniteTransformation
  case duplicateEnabledPairing
}

public enum PairingValidator: Sendable {
  public static func validate(_ pairing: Pairing, existing: [Pairing]) throws {
    guard isValidEntityID(pairing.entityID) else {
      throw PairingValidationError.invalidEntityID
    }
    guard let destination = WritableHealthRegistry[pairing.destination] else {
      throw PairingValidationError.destinationNotWritable
    }
    guard pairing.destinationUnit == destination.nativeUnit else {
      throw PairingValidationError.invalidDestinationUnit
    }
    guard pairing.transformation.constantsAreFinite else {
      throw PairingValidationError.nonFiniteTransformation
    }
    do {
      _ = try UnitConverter.convert(1, from: pairing.sourceUnit, to: pairing.destinationUnit)
    } catch {
      throw PairingValidationError.incompatibleUnits
    }
    guard
      !pairing.isEnabled
        || !existing.contains(where: {
          $0.id != pairing.id && $0.isEnabled && $0.entityID == pairing.entityID
            && $0.destination == pairing.destination
        })
    else {
      throw PairingValidationError.duplicateEnabledPairing
    }
  }

  private static func isValidEntityID(_ entityID: String) -> Bool {
    entityID.range(
      of: #"^[a-z0-9_]+\.[a-z0-9_]+$"#,
      options: .regularExpression
    ) != nil
  }
}
