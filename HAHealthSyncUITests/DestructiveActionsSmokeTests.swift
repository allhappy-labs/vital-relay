import XCTest

@MainActor
final class DestructiveActionsSmokeTests: XCTestCase {
  func testConnectionSettingsPrefillNonSecretConfiguration() {
    let app = launchMaintenanceApp()
    openSettings(in: app)

    app.buttons["settings-home-assistant-connection"].tap()
    app.buttons["edit-home-assistant-connection"].tap()

    XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertEqual(app.textFields["base-url-field"].value as? String, "https://example.invalid")
    XCTAssertEqual(app.textFields["user-id-field"].value as? String, "example-user")
    XCTAssertTrue(app.secureTextFields["webhook-secret-field"].value as? String != "fixture-secret")
    XCTAssertTrue(app.secureTextFields["access-token-field"].value as? String != "fixture-token")
    XCTAssertTrue(app.buttons["save-connection"].isEnabled)
    app.buttons["save-connection"].tap()

    XCTAssertTrue(
      app.navigationBars["Home Assistant Connection"].waitForExistence(timeout: UITestWait.standard)
    )
    app.navigationBars["Home Assistant Connection"].buttons.element(boundBy: 0).tap()
    app.buttons["settings-export-home-assistant"].tap()
    app.buttons["background-sync-settings"].tap()
    XCTAssertEqual(app.switches["background-sync-toggle"].value as? String, "1")
    XCTAssertTrue(app.buttons["background-sync-frequency-picker"].label.contains("Battery Saver"))

    app.navigationBars["Background Sync"].buttons.element(boundBy: 0).tap()
    app.navigationBars["Export to Home Assistant"].buttons.element(boundBy: 0).tap()
    app.buttons["settings-home-assistant-connection"].tap()
    app.buttons["edit-home-assistant-connection"].tap()
    XCTAssertFalse(app.staticTexts["Connection succeeded"].exists)
    XCTAssertTrue(app.secureTextFields["webhook-secret-field"].value as? String != "fixture-secret")
    XCTAssertTrue(app.secureTextFields["access-token-field"].value as? String != "fixture-token")
  }

  func testDiagnosticsAreExplicitlyValueFreeAndExportable() {
    let app = launchMaintenanceApp()
    openSettings(in: app)

    app.buttons["settings-app-privacy"].tap()
    let diagnostics = app.buttons["diagnostics-settings"]
    XCTAssertTrue(scrollToExistence(diagnostics, in: app))
    diagnostics.tap()

    XCTAssertTrue(scrollToExistence(app.staticTexts["diagnostics-privacy-scope"], in: app))
    XCTAssertTrue(scrollToExistence(app.buttons["diagnostics-export"], in: app))
    XCTAssertFalse(app.staticTexts["8421"].exists)
    XCTAssertFalse(app.staticTexts["fixture-secret"].exists)
  }

  func testResetRequiresTwoConfirmationsAndPreservesConfiguredApp() {
    let app = launchMaintenanceApp()
    openDataManagement(in: app)

    app.buttons["reset-sync-state-destination"].tap()
    XCTAssertTrue(app.staticTexts["reset-scope-description"].exists)
    XCTAssertTrue(scrollToExistence(app.buttons["reset-sync-state"], in: app))
    app.buttons["reset-sync-state"].tap()
    XCTAssertTrue(app.buttons["Review Reset"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Review Reset"].firstMatch.tap()
    XCTAssertTrue(
      app.alerts.buttons["Reset Synchronization State"].waitForExistence(
        timeout: UITestWait.standard))
    app.alerts.buttons["Reset Synchronization State"].tap()

    let maintenanceResult = app.staticTexts["maintenance-result"]
    XCTAssertTrue(
      maintenanceResult.waitForExistence(timeout: UITestWait.standard)
        || scrollToExistence(maintenanceResult, in: app)
    )
    XCTAssertTrue(app.navigationBars["Reset Synchronization State"].exists)
  }

  func testDeleteAllRequiresTwoConfirmationsAndReturnsToOnboarding() {
    let app = launchMaintenanceApp()
    openDataManagement(in: app)

    app.buttons["delete-all-data-destination"].tap()
    XCTAssertTrue(app.staticTexts["delete-all-scope-description"].exists)
    let delete = app.buttons["delete-all-data"]
    XCTAssertTrue(scrollToExistence(delete, in: app))
    delete.tap()
    XCTAssertTrue(app.buttons["Review Delete"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Review Delete"].firstMatch.tap()
    XCTAssertTrue(
      app.alerts.buttons["Delete All Local App Data"].waitForExistence(timeout: UITestWait.standard)
    )
    app.alerts.buttons["Delete All Local App Data"].tap()

    XCTAssertTrue(
      app.staticTexts["Your health data stays under your control"]
        .waitForExistence(timeout: UITestWait.standard)
    )
    XCTAssertFalse(app.staticTexts["8421"].exists)
  }

  private func launchMaintenanceApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-maintenance"]
    app.launch()
    return app
  }

  private func openSettings(in app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()
  }

  private func openDataManagement(in app: XCUIApplication) {
    openSettings(in: app)
    app.buttons["settings-app-privacy"].tap()
    let management = app.buttons["data-management-settings"]
    XCTAssertTrue(scrollToExistence(management, in: app))
    management.tap()
  }

  private func scrollToExistence(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 10
  ) -> Bool {
    for _ in 0..<maxSwipes where !element.exists {
      app.swipeUp()
    }
    return element.exists
  }
}
