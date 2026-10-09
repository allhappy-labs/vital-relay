import XCTest

@MainActor
final class LifetimeUnlockSmokeTests: XCTestCase {
  func testSettingsOffersDismissibleUnlockWhileSyncNowStaysFree() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["sync-now"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.buttons["sync-now"].isEnabled)
    app.buttons["Settings"].tap()
    let unlock = app.buttons["settings-lifetime-unlock"]
    XCTAssertTrue(unlock.waitForExistence(timeout: UITestWait.standard))
    unlock.tap()
    XCTAssertTrue(app.staticTexts["lifetime-unlock-free-features"].exists)
    XCTAssertEqual(app.buttons["lifetime-unlock-restore"].label, "Restore Purchases")
    XCTAssertFalse(app.staticTexts["fixture-secret"].exists)
    XCTAssertEqual(app.buttons["lifetime-unlock-done"].label, "Done")
    app.buttons["lifetime-unlock-done"].tap()
    XCTAssertTrue(unlock.exists)
  }

  func testLockedBackgroundAndHistoryRouteToUnlock() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-dashboard", "-ui-testing-purchase-locked"]
    app.launch()
    app.buttons["Settings"].tap()
    let export = app.buttons["settings-export-home-assistant"]
    XCTAssertTrue(export.waitForExistence(timeout: UITestWait.standard))
    export.tap()
    app.buttons["background-sync-settings"].tap()
    let backgroundUnlock = app.buttons["background-unlock"]
    XCTAssertTrue(backgroundUnlock.waitForExistence(timeout: UITestWait.standard))
    XCTAssertFalse(app.switches["background-sync-toggle"].isEnabled)
    backgroundUnlock.tap()
    XCTAssertTrue(app.buttons["lifetime-unlock-restore"].exists)
    app.buttons["lifetime-unlock-done"].tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["historical-import-settings"].tap()
    let historyUnlock = app.buttons["historical-import-unlock"]
    XCTAssertTrue(historyUnlock.waitForExistence(timeout: UITestWait.standard))
    XCTAssertFalse(app.switches["historical-import-toggle"].isEnabled)
    historyUnlock.tap()
    XCTAssertTrue(app.buttons["lifetime-unlock-restore"].exists)
  }

  func testUnavailableProductShowsNoBuyButtonOrPrice() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-dashboard", "-ui-testing-purchase-unavailable"]
    app.launch()
    app.buttons["Settings"].tap()
    app.buttons["settings-lifetime-unlock"].tap()
    let status = app.staticTexts["lifetime-unlock-status"]
    XCTAssertTrue(status.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(status.label.contains("unavailable"))
    XCTAssertFalse(app.buttons["lifetime-unlock-buy"].exists)
    XCTAssertTrue(app.buttons["lifetime-unlock-restore"].exists)
  }

  func testCancelledPurchaseAndRestoreActionsUpdateVisibleState() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-dashboard", "-ui-testing-purchase-interactions"]
    app.launch()
    app.buttons["Settings"].tap()
    app.buttons["settings-lifetime-unlock"].tap()

    let buy = app.buttons["lifetime-unlock-buy"]
    XCTAssertTrue(buy.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(buy.label.contains("$10.00"))
    buy.tap()
    let message = app.staticTexts["lifetime-unlock-message"]
    XCTAssertTrue(message.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(message.label.contains("cancelled"))
    XCTAssertTrue(app.staticTexts["lifetime-unlock-status"].label.contains("locked"))

    app.buttons["lifetime-unlock-restore"].tap()
    XCTAssertTrue(message.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(message.label.contains("restored"))
    XCTAssertTrue(app.staticTexts["lifetime-unlock-status"].label.contains("unlocked"))
    XCTAssertFalse(buy.exists)
  }
}
