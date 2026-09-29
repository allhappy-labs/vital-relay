import XCTest

@MainActor
final class SettingsNavigationSmokeTests: XCTestCase {
  func testSettingsTitlesAndDescriptionsShareOneTextColumn() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-background"]
    app.launch()

    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()

    assertTextColumn("settings-home-assistant-connection", in: app)
    assertTextColumn("settings-export-home-assistant", in: app)
    assertTextColumn("settings-import-apple-health", in: app)
    assertTextColumn("settings-app-privacy", in: app)
  }

  func testSettingsRootGroupsRelatedConfigurationScreens() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-background"]
    app.launch()

    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()

    assertDestination(
      "settings-home-assistant-connection",
      navigationTitle: "Home Assistant Connection",
      child: "edit-home-assistant-connection",
      in: app
    )
    assertDestination(
      "settings-export-home-assistant",
      navigationTitle: "Export to Home Assistant",
      child: "choose-health-metrics",
      in: app
    )
    assertDestination(
      "settings-import-apple-health",
      navigationTitle: "Import to Apple Health",
      child: "health-import-pairings",
      in: app
    )
    assertDestination(
      "settings-app-privacy",
      navigationTitle: "App & Privacy",
      child: "diagnostics-settings",
      in: app
    )
  }

  func testAppPrivacyProvidesPublicPrivacyPolicy() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-background"]
    app.launch()

    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()

    let appPrivacy = app.buttons["settings-app-privacy"]
    XCTAssertTrue(appPrivacy.waitForExistence(timeout: UITestWait.standard))
    appPrivacy.tap()

    let privacyPolicy = app.buttons["privacy-policy-link"]
    XCTAssertTrue(privacyPolicy.waitForExistence(timeout: UITestWait.standard))
    XCTAssertEqual(privacyPolicy.label, "Privacy Policy")
  }

  private func assertDestination(
    _ identifier: String,
    navigationTitle: String,
    child: String,
    in app: XCUIApplication
  ) {
    let destination = app.buttons[identifier]
    XCTAssertTrue(destination.waitForExistence(timeout: UITestWait.standard))
    destination.tap()
    XCTAssertTrue(
      app.navigationBars[navigationTitle].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.buttons[child].exists)
    app.navigationBars[navigationTitle].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: UITestWait.standard))
  }

  private func assertTextColumn(_ identifier: String, in app: XCUIApplication) {
    let title = app.staticTexts["\(identifier)-title"]
    let subtitle = app.staticTexts["\(identifier)-subtitle"]
    XCTAssertTrue(title.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(subtitle.exists)
    XCTAssertEqual(title.frame.minX, subtitle.frame.minX, accuracy: 1)
  }
}
