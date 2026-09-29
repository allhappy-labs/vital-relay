import Foundation

public struct HomeAssistantState: Decodable, Sendable, Equatable {
  public struct Attributes: Decodable, Sendable, Equatable {
    public let unitOfMeasurement: String?
    public let friendlyName: String?

    public init(unitOfMeasurement: String?, friendlyName: String? = nil) {
      self.unitOfMeasurement = unitOfMeasurement
      self.friendlyName = friendlyName
    }

    private enum CodingKeys: String, CodingKey {
      case unitOfMeasurement = "unit_of_measurement"
      case friendlyName = "friendly_name"
    }
  }

  public let entityID: String
  public let state: String
  public let lastChanged: Date
  public let lastUpdated: Date
  public let attributes: Attributes

  public init(
    entityID: String,
    state: String,
    lastChanged: Date,
    lastUpdated: Date,
    attributes: Attributes
  ) {
    self.entityID = entityID
    self.state = state
    self.lastChanged = lastChanged
    self.lastUpdated = lastUpdated
    self.attributes = attributes
  }

  private enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case state
    case lastChanged = "last_changed"
    case lastUpdated = "last_updated"
    case attributes
  }
}

public struct NormalizedHomeAssistantState: Sendable, Equatable {
  public let entityID: String
  public let lastUpdated: Date
  public let normalizedValue: Double
  public let destination: HealthObjectTypeID

  public init(
    entityID: String,
    lastUpdated: Date,
    normalizedValue: Double,
    destination: HealthObjectTypeID
  ) {
    self.entityID = entityID
    self.lastUpdated = lastUpdated
    self.normalizedValue = normalizedValue
    self.destination = destination
  }
}
