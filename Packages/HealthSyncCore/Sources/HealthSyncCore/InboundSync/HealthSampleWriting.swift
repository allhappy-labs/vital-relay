import Foundation

public struct HealthSampleWrite: Sendable, Equatable {
  public let destination: HealthObjectTypeID
  public let value: Double
  public let date: Date
  public let syncIdentifier: String
  public let syncVersion: Int

  public init(
    destination: HealthObjectTypeID,
    value: Double,
    date: Date,
    syncIdentifier: String,
    syncVersion: Int
  ) {
    self.destination = destination
    self.value = value
    self.date = date
    self.syncIdentifier = syncIdentifier
    self.syncVersion = syncVersion
  }
}

public protocol HealthSampleWriting: Sendable {
  func requestWriteAuthorization(for destinations: Set<HealthObjectTypeID>) async throws
  func save(_ sample: HealthSampleWrite) async throws
}
