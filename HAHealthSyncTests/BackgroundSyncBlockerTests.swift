import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class BackgroundSyncBlockerTests: XCTestCase {
  func testNoBlockerWhenRefreshIsOnAndLowPowerIsOff() {
    XCTAssertNil(BackgroundSyncBlocker.current(refresh: .available, isLowPowerModeEnabled: false))
  }

  func testRefreshOffOffersSettings() {
    let blocker = BackgroundSyncBlocker.current(refresh: .denied, isLowPowerModeEnabled: false)
    XCTAssertEqual(blocker?.message, "Background App Refresh is off for Vital Relay.")
    XCTAssertEqual(blocker?.offersSettings, true)
  }

  func testRestrictedRefreshCannotBeChangedFromSettings() {
    let blocker = BackgroundSyncBlocker.current(refresh: .restricted, isLowPowerModeEnabled: false)
    XCTAssertEqual(blocker?.message, "Background App Refresh is restricted on this iPhone.")
    XCTAssertEqual(blocker?.offersSettings, false)
  }

  func testLowPowerModeKeepsItsExistingWording() {
    let blocker = BackgroundSyncBlocker.current(refresh: .available, isLowPowerModeEnabled: true)
    XCTAssertEqual(blocker?.message, "iOS pauses background refresh in Low Power Mode.")
    XCTAssertEqual(blocker?.offersSettings, false)
  }

  func testRefreshOffOutranksLowPowerMode() {
    let blocker = BackgroundSyncBlocker.current(refresh: .denied, isLowPowerModeEnabled: true)
    XCTAssertEqual(blocker?.offersSettings, true)
  }
}
