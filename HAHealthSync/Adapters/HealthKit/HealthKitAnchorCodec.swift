import Foundation
import HealthKit

enum HealthKitAnchorCodecError: Error, Equatable, Sendable {
  case invalidArchive
}

enum HealthKitAnchorCodec {
  static func encode(_ anchor: HKQueryAnchor) throws -> Data {
    do {
      return try NSKeyedArchiver.archivedData(
        withRootObject: anchor,
        requiringSecureCoding: true
      )
    } catch {
      throw HealthKitAnchorCodecError.invalidArchive
    }
  }

  static func decode(_ data: Data) throws -> HKQueryAnchor {
    guard !data.isEmpty else {
      throw HealthKitAnchorCodecError.invalidArchive
    }
    do {
      guard
        let anchor = try NSKeyedUnarchiver.unarchivedObject(
          ofClass: HKQueryAnchor.self,
          from: data
        )
      else {
        throw HealthKitAnchorCodecError.invalidArchive
      }
      return anchor
    } catch {
      throw HealthKitAnchorCodecError.invalidArchive
    }
  }
}
