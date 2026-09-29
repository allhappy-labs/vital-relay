import CryptoKit
import Foundation

public struct SyncIdentity: Sendable, Equatable {
  public let identifier: String
  public let version: Int

  public static func make(
    pairingID: UUID,
    entityID: String,
    homeAssistantUpdatedAt: Date,
    normalizedValue: Double,
    destination: HealthObjectTypeID
  ) -> SyncIdentity {
    var canonical = Data()
    canonical.append(contentsOf: pairingID.uuidString.lowercased().utf8)
    canonical.append(0)
    canonical.append(contentsOf: entityID.utf8)
    canonical.append(0)

    let milliseconds = Int64(homeAssistantUpdatedAt.timeIntervalSince1970 * 1_000)
    append(milliseconds.bigEndian, to: &canonical)
    append(normalizedValue.bitPattern.bigEndian, to: &canonical)
    canonical.append(contentsOf: destination.rawValue.utf8)

    let digest = SHA256.hash(data: canonical)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return SyncIdentity(identifier: "ha-health-sync.\(hex)", version: 1)
  }

  private static func append<T>(_ value: T, to data: inout Data) {
    withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
  }
}
