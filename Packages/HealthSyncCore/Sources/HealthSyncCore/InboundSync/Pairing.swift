import Foundation

public struct Pairing: Codable, Sendable, Equatable, Identifiable {
  public let id: UUID
  public var entityID: String
  public var destination: HealthObjectTypeID
  public var sourceUnit: UnitSymbol
  public var destinationUnit: UnitSymbol
  public var transformation: PairingTransformation
  public var isEnabled: Bool

  public init(
    id: UUID = UUID(),
    entityID: String,
    destination: HealthObjectTypeID,
    sourceUnit: UnitSymbol,
    destinationUnit: UnitSymbol,
    transformation: PairingTransformation,
    isEnabled: Bool
  ) {
    self.id = id
    self.entityID = entityID
    self.destination = destination
    self.sourceUnit = sourceUnit
    self.destinationUnit = destinationUnit
    self.transformation = transformation
    self.isEnabled = isEnabled
  }
}

public enum PairingTransformation: Codable, Sendable, Equatable {
  case identity
  case multiply(Double)
  case add(Double)
  case affine(scale: Double, offset: Double)

  public func apply(to value: Double) throws -> Double {
    guard value.isFinite else { throw PairingValidationError.nonFiniteTransformation }
    let transformed: Double
    switch self {
    case .identity:
      transformed = value
    case .multiply(let multiplier):
      transformed = value * multiplier
    case .add(let amount):
      transformed = value + amount
    case .affine(let scale, let offset):
      transformed = (value * scale) + offset
    }
    guard transformed.isFinite else {
      throw PairingValidationError.nonFiniteTransformation
    }
    return transformed
  }

  var constantsAreFinite: Bool {
    switch self {
    case .identity:
      true
    case .multiply(let multiplier), .add(let multiplier):
      multiplier.isFinite
    case .affine(let scale, let offset):
      scale.isFinite && offset.isFinite
    }
  }
}
