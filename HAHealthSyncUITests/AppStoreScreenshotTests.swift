import XCTest

/// Captures App Store screenshots from the synthetic UI-testing fixtures.
///
/// Skipped unless `SCREENSHOT_DIR` is set, so it never runs in the normal suite:
///
///     TEST_RUNNER_SCREENSHOT_DIR=/tmp/vital-relay-screenshots xcodebuild test \
///       -only-testing:HAHealthSyncUITests/AppStoreScreenshotTests ...
///
/// Every fixture uses in-memory stores and fake Home Assistant responses, so the
/// captures contain no personal readings, server URLs, or credentials.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty else {
      throw XCTSkip("Set SCREENSHOT_DIR to capture App Store screenshots.")
    }
    directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    continueAfterFailure = false
  }

  func testDashboard() throws {
    let app = launch(["-ui-testing-dashboard"])
    let syncNow = app.buttons["sync-now"]
    XCTAssertTrue(syncNow.waitForExistence(timeout: UITestWait.standard))
    syncNow.tap()
    XCTAssertTrue(app.staticTexts["All synced"].waitForExistence(timeout: UITestWait.standard))
    // Wait out the transient "Sync successful" toast so it is not caught mid-fade.
    Thread.sleep(forTimeInterval: 5)
    try capture("01-dashboard")
  }

  func testPrivacy() throws {
    let app = launch(["-ui-testing-onboarding"])
    XCTAssertTrue(app.buttons["privacy-continue"].waitForExistence(timeout: UITestWait.standard))
    try capture("02-privacy")
  }

  func testMetricSelection() throws {
    let app = launch(["-ui-testing-onboarding"])
    XCTAssertTrue(app.buttons["privacy-continue"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["privacy-continue"].tap()
    for label in ["Steps", "Walking + Running Distance", "Active Calories", "Flights Climbed"] {
      let toggle = app.switches[label]
      guard toggle.waitForExistence(timeout: UITestWait.standard), toggle.isHittable else {
        continue
      }
      if toggle.value as? String != "1" {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      }
    }
    try capture("03-metric-selection")
  }

  func testBackgroundSync() throws {
    let app = launch(["-ui-testing-background"])
    openExportSettings(in: app)
    let background = app.buttons["background-sync-settings"]
    XCTAssertTrue(background.waitForExistence(timeout: UITestWait.standard))
    background.tap()
    XCTAssertTrue(
      app.switches["background-sync-toggle"].waitForExistence(timeout: UITestWait.standard))
    try capture("04-background-sync")
  }

  func testHistoricalImport() throws {
    let app = launch(["-ui-testing-archive"])
    openExportSettings(in: app)
    let settings = app.buttons["historical-import-settings"]
    XCTAssertTrue(scrollToExistence(settings, in: app))
    settings.tap()
    XCTAssertTrue(
      app.staticTexts["historical-import-progress-headline"].waitForExistence(
        timeout: UITestWait.standard))
    try capture("05-historical-import")
  }

  func testLifetimeUnlock() throws {
    let app = launch(["-ui-testing-dashboard", "-ui-testing-purchase-interactions"])
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()
    let unlock = app.buttons["settings-lifetime-unlock"]
    XCTAssertTrue(unlock.waitForExistence(timeout: UITestWait.standard))
    unlock.tap()
    XCTAssertTrue(app.buttons["lifetime-unlock-buy"].waitForExistence(timeout: UITestWait.standard))
    try capture("06-lifetime-unlock")
  }

  private func launch(_ arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    // US locale so times, units, and the price read naturally on the US product page.
    app.launchArguments = arguments + ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
    app.launch()
    return app
  }

  private func openExportSettings(in app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()
    let export = app.buttons["settings-export-home-assistant"]
    XCTAssertTrue(export.waitForExistence(timeout: UITestWait.standard))
    export.tap()
  }

  private func capture(_ name: String) throws {
    // Let navigation transitions and scroll indicators settle before capturing.
    Thread.sleep(forTimeInterval: 1.5)
    let png = XCUIScreen.main.screenshot().pngRepresentation
    try png.write(to: directory.appendingPathComponent("\(name).png"))
  }

  private func scrollToExistence(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 12
  ) -> Bool {
    for _ in 0..<maxSwipes where !element.exists {
      app.swipeUp()
    }
    return element.exists
  }
}
