import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Home Assistant state normalization")
struct HomeAssistantStateParserTests {
  private let timestamp = Date(timeIntervalSince1970: 1_788_052_801)

  @Test("Strictly parses transforms converts and bounds a state")
  func normalizesValidState() throws {
    let pairing = makePairing(sourceUnit: .pounds, transformation: .add(2))
    let state = makeState(value: "152.324", unit: "lb")

    let normalized = try HomeAssistantStateParser.normalize(state, for: pairing)

    #expect(normalized.entityID == pairing.entityID)
    #expect(normalized.lastUpdated == timestamp)
    #expect(abs(normalized.normalizedValue - 70) < 0.001)
    #expect(normalized.destination == .bodyMass)
  }

  @Test("Accepts a missing Home Assistant unit for unitless UV exposure")
  func normalizesUnitlessUVExposure() throws {
    let pairing = makePairing(
      sourceUnit: .unitless,
      destination: .uvExposure,
      destinationUnit: .unitless
    )

    let normalized = try HomeAssistantStateParser.normalize(
      makeState(entityID: pairing.entityID, value: "7.4", unit: nil),
      for: pairing
    )

    #expect(normalized.normalizedValue == 7.4)
    #expect(normalized.destination == .uvExposure)
  }

  @Test("Accepts Home Assistant's UV index unit for unitless UV exposure")
  func normalizesHomeAssistantUVIndexUnit() throws {
    let pairing = makePairing(
      sourceUnit: .unitless,
      destination: .uvExposure,
      destinationUnit: .unitless
    )

    let normalized = try HomeAssistantStateParser.normalize(
      makeState(entityID: pairing.entityID, value: "7.4", unit: "UV index"),
      for: pairing
    )

    #expect(normalized.normalizedValue == 7.4)
    #expect(normalized.destination == .uvExposure)
  }

  @Test(
    "Rejects unavailable empty and nonnumeric states",
    arguments: [
      "", " ", "unknown", "UNAVAILABLE", "None", "1,5", "12kg", "NaN", "+infinity", " 12",
    ]
  )
  func rejectsInvalidStates(value: String) {
    #expect(throws: HomeAssistantStateValidationError.invalidState) {
      try HomeAssistantStateParser.normalize(makeState(value: value), for: makePairing())
    }
  }

  @Test("Rejects missing mismatched and unsupported source units")
  func rejectsInvalidUnits() {
    #expect(throws: HomeAssistantStateValidationError.missingUnit) {
      try HomeAssistantStateParser.normalize(makeState(unit: nil), for: makePairing())
    }
    #expect(throws: HomeAssistantStateValidationError.unitMismatch) {
      try HomeAssistantStateParser.normalize(makeState(unit: "lb"), for: makePairing())
    }
    #expect(throws: HomeAssistantStateValidationError.unsupportedUnit) {
      try HomeAssistantStateParser.normalize(makeState(unit: "stones"), for: makePairing())
    }
  }

  @Test("Rejects entity mismatch and transformed values outside plausible bounds")
  func rejectsMismatchesAndBounds() {
    #expect(throws: HomeAssistantStateValidationError.entityMismatch) {
      try HomeAssistantStateParser.normalize(
        makeState(entityID: "sensor.other"),
        for: makePairing()
      )
    }
    #expect(throws: HomeAssistantStateValidationError.outOfBounds) {
      try HomeAssistantStateParser.normalize(makeState(value: "900"), for: makePairing())
    }
  }

  @Test("Recognizes supported Home Assistant unit aliases")
  func parsesUnitAliases() throws {
    #expect(try HomeAssistantUnitParser.parse("°C") == .degreesCelsius)
    #expect(try HomeAssistantUnitParser.parse("bpm") == .beatsPerMinute)
    #expect(try HomeAssistantUnitParser.parse("ug") == .micrograms)
    #expect(try HomeAssistantUnitParser.parse("ml") == .millilitres)
  }

  private func makePairing(
    sourceUnit: UnitSymbol = .kilograms,
    destination: HealthObjectTypeID = .bodyMass,
    destinationUnit: UnitSymbol = .kilograms,
    transformation: PairingTransformation = .identity
  ) -> Pairing {
    Pairing(
      entityID: "sensor.body_mass",
      destination: destination,
      sourceUnit: sourceUnit,
      destinationUnit: destinationUnit,
      transformation: transformation,
      isEnabled: true
    )
  }

  private func makeState(
    entityID: String = "sensor.body_mass",
    value: String = "70",
    unit: String? = "kg"
  ) -> HomeAssistantState {
    HomeAssistantState(
      entityID: entityID,
      state: value,
      lastChanged: timestamp,
      lastUpdated: timestamp,
      attributes: .init(unitOfMeasurement: unit)
    )
  }
}
