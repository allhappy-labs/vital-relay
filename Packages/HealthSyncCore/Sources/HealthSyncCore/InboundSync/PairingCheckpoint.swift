import Foundation

public struct PairingCheckpoint: Codable, Sendable, Equatable {
  public let pairingID: UUID
  public let entityID: String
  public let homeAssistantUpdatedAt: Date
  public let normalizedValue: Double
  public let destination: HealthObjectTypeID
  public let syncIdentifier: String
  public let syncVersion: Int

  public init(
    pairingID: UUID,
    entityID: String,
    homeAssistantUpdatedAt: Date,
    normalizedValue: Double,
    destination: HealthObjectTypeID,
    syncIdentifier: String,
    syncVersion: Int
  ) {
    self.pairingID = pairingID
    self.entityID = entityID
    self.homeAssistantUpdatedAt = homeAssistantUpdatedAt
    self.normalizedValue = normalizedValue
    self.destination = destination
    self.syncIdentifier = syncIdentifier
    self.syncVersion = syncVersion
  }

  public func matches(_ state: NormalizedHomeAssistantState) -> Bool {
    entityID == state.entityID
      && homeAssistantUpdatedAt == state.lastUpdated
      && normalizedValue.bitPattern == state.normalizedValue.bitPattern
      && destination == state.destination
  }

  func validate() throws {
    guard normalizedValue.isFinite,
      WritableHealthRegistry[destination] != nil,
      syncVersion == 1
    else {
      throw PairingCheckpointStoreError.corruptedData
    }
    let expected = SyncIdentity.make(
      pairingID: pairingID,
      entityID: entityID,
      homeAssistantUpdatedAt: homeAssistantUpdatedAt,
      normalizedValue: normalizedValue,
      destination: destination
    )
    guard expected.identifier == syncIdentifier, expected.version == syncVersion else {
      throw PairingCheckpointStoreError.corruptedData
    }
  }
}
