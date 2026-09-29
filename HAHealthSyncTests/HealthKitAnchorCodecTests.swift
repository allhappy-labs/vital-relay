import Foundation
import HealthKit
import XCTest

@testable import HAHealthSync

final class HealthKitAnchorCodecTests: XCTestCase {
  func testSecureCodingRoundTrip() throws {
    let anchor = HKQueryAnchor(fromValue: 42)

    let data = try HealthKitAnchorCodec.encode(anchor)
    let decoded = try HealthKitAnchorCodec.decode(data)
    let roundTripped = try HealthKitAnchorCodec.encode(decoded)

    XCTAssertFalse(data.isEmpty)
    XCTAssertFalse(roundTripped.isEmpty)
    XCTAssertNoThrow(try HealthKitAnchorCodec.decode(roundTripped))
  }

  func testInvalidAndEmptyArchivesFailClosed() {
    XCTAssertThrowsError(try HealthKitAnchorCodec.decode(Data())) { error in
      XCTAssertEqual(error as? HealthKitAnchorCodecError, .invalidArchive)
    }
    XCTAssertThrowsError(try HealthKitAnchorCodec.decode(Data("not-an-anchor".utf8))) { error in
      XCTAssertEqual(error as? HealthKitAnchorCodecError, .invalidArchive)
    }
  }
}
