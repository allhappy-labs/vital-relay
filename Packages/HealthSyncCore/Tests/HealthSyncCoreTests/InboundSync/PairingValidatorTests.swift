import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Inbound pairing validation")
struct PairingValidatorTests {
  private let id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

  @Test("Accepts a bounded transform and compatible native destination unit")
  func acceptsValidPairing() throws {
    let pairing = makePairing(transformation: .affine(scale: 0.5, offset: 1))

    try PairingValidator.validate(pairing, existing: [])
    #expect(try pairing.transformation.apply(to: 10) == 6)
  }

  @Test("Accepts unitless UV exposure pairings")
  func acceptsUVExposurePairing() throws {
    let pairing = makePairing(
      entityID: "sensor.uv_index",
      destination: .uvExposure,
      sourceUnit: .unitless,
      destinationUnit: .unitless
    )

    try PairingValidator.validate(pairing, existing: [])
  }

  @Test(
    "Rejects malformed entity IDs",
    arguments: [
      "", "Sensor.Weight", "sensor", "sensor.weight/value", "sensor.weight?x=1", "sensor.two words",
    ]
  )
  func rejectsMalformedEntityIDs(entityID: String) {
    #expect(throws: PairingValidationError.invalidEntityID) {
      try PairingValidator.validate(makePairing(entityID: entityID), existing: [])
    }
  }

  @Test("Rejects destinations outside the write allowlist")
  func rejectsNonWritableDestination() {
    #expect(throws: PairingValidationError.destinationNotWritable) {
      try PairingValidator.validate(makePairing(destination: .restingHeartRate), existing: [])
    }
  }

  @Test("Rejects incompatible or non-native destination units")
  func rejectsInvalidUnits() {
    #expect(throws: PairingValidationError.incompatibleUnits) {
      try PairingValidator.validate(makePairing(sourceUnit: .litres), existing: [])
    }
    #expect(throws: PairingValidationError.invalidDestinationUnit) {
      try PairingValidator.validate(makePairing(destinationUnit: .pounds), existing: [])
    }
  }

  @Test("Rejects non-finite transformation constants and results")
  func rejectsNonFiniteTransform() {
    #expect(throws: PairingValidationError.nonFiniteTransformation) {
      try PairingValidator.validate(makePairing(transformation: .multiply(.infinity)), existing: [])
    }
    #expect(throws: PairingValidationError.nonFiniteTransformation) {
      _ = try PairingTransformation.multiply(.greatestFiniteMagnitude).apply(to: 2)
    }
  }

  @Test("Rejects duplicate enabled entity and destination pairs")
  func rejectsDuplicateEnabledPair() throws {
    let existing = makePairing()
    let duplicate = Pairing(
      id: UUID(),
      entityID: existing.entityID,
      destination: existing.destination,
      sourceUnit: existing.sourceUnit,
      destinationUnit: existing.destinationUnit,
      transformation: .identity,
      isEnabled: true
    )

    #expect(throws: PairingValidationError.duplicateEnabledPairing) {
      try PairingValidator.validate(duplicate, existing: [existing])
    }

    var disabled = duplicate
    disabled.isEnabled = false
    try PairingValidator.validate(disabled, existing: [existing])
  }

  private func makePairing(
    entityID: String = "sensor.body_mass",
    destination: HealthObjectTypeID = .bodyMass,
    sourceUnit: UnitSymbol = .kilograms,
    destinationUnit: UnitSymbol = .kilograms,
    transformation: PairingTransformation = .identity
  ) -> Pairing {
    Pairing(
      id: id,
      entityID: entityID,
      destination: destination,
      sourceUnit: sourceUnit,
      destinationUnit: destinationUnit,
      transformation: transformation,
      isEnabled: true
    )
  }
}
