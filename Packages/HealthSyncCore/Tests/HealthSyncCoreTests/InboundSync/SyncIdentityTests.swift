import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Stable HealthKit import identity")
struct SyncIdentityTests {
  private let pairingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  private let timestamp = Date(timeIntervalSince1970: 1_788_052_801.1234)

  @Test("Identical canonical state creates one bounded opaque identifier")
  func identityIsDeterministicAndOpaque() {
    let first = identity()
    let second = identity()

    #expect(first == second)
    #expect(first.version == 1)
    #expect(first.identifier.hasPrefix("ha-health-sync."))
    #expect(first.identifier.count == 79)
    #expect(first.identifier == first.identifier.lowercased())
    #expect(!first.identifier.contains("sensor.body_mass"))
    #expect(!first.identifier.contains("70.5"))
    #expect(!first.identifier.contains(pairingID.uuidString.lowercased()))
  }

  @Test("Every duplicate-relevant field changes the identifier")
  func relevantFieldsChangeIdentity() {
    let original = identity()

    #expect(identity(pairingID: UUID()) != original)
    #expect(identity(entityID: "sensor.other") != original)
    #expect(identity(timestamp: timestamp.addingTimeInterval(0.001)) != original)
    #expect(identity(value: 70.6) != original)
    #expect(identity(destination: .leanBodyMass) != original)
  }

  @Test("Timestamp canonicalization uses UTC milliseconds")
  func timestampUsesMilliseconds() {
    let withinSameMillisecond = identity(
      timestamp: Date(timeIntervalSince1970: 1_788_052_801.1239)
    )
    #expect(withinSameMillisecond == identity())
  }

  private func identity(
    pairingID: UUID? = nil,
    entityID: String = "sensor.body_mass",
    timestamp: Date? = nil,
    value: Double = 70.5,
    destination: HealthObjectTypeID = .bodyMass
  ) -> SyncIdentity {
    SyncIdentity.make(
      pairingID: pairingID ?? self.pairingID,
      entityID: entityID,
      homeAssistantUpdatedAt: timestamp ?? self.timestamp,
      normalizedValue: value,
      destination: destination
    )
  }
}
