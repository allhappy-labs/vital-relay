import XCTest

@MainActor
final class OnboardingSmokeTests: XCTestCase {
  func testOnboardingGatesEachNativeStep() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-onboarding"]
    app.launch()

    XCTAssertTrue(
      app.staticTexts["Your health data stays under your control"]
        .waitForExistence(timeout: UITestWait.standard)
    )
    XCTAssertTrue(app.staticTexts["Step 1 of 3"].exists)
    app.buttons["privacy-continue"].tap()

    XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertFalse(app.buttons["request-health-access"].isEnabled)
    let steps = app.switches["metric-steps"]
    XCTAssertTrue(steps.waitForExistence(timeout: UITestWait.standard))
    XCTAssertEqual(app.switches.matching(identifier: "metric-steps").count, 1)
    steps
      .coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
      .tap()
    XCTAssertEqual(steps.value as? String, "1")

    XCTAssertTrue(scrollToExistence(app.switches["metric-body_mass"], in: app))
    XCTAssertEqual(app.switches.matching(identifier: "metric-body_mass").count, 1)
    XCTAssertTrue(scrollToExistence(app.switches["metric-resting_heart_rate"], in: app))
    XCTAssertEqual(app.switches.matching(identifier: "metric-resting_heart_rate").count, 1)

    let requestAccess = app.buttons["request-health-access"]
    XCTAssertTrue(scrollToExistence(requestAccess, in: app))
    XCTAssertTrue(requestAccess.isEnabled)
    requestAccess.tap()

    XCTAssertTrue(app.navigationBars["Connect"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.staticTexts["Step 3 of 3"].exists)
    XCTAssertFalse(app.buttons["save-connection"].isEnabled)
    fillNonSecretConnectionFields(in: app)
    let webhookField = app.secureTextFields["webhook-secret-field"]
    let tokenField = app.secureTextFields["access-token-field"]
    for _ in 0..<3 where !webhookField.exists {
      app.swipeUp()
    }
    XCTAssertTrue(webhookField.exists)
    XCTAssertTrue(app.buttons["test-webhook"].exists)
    for _ in 0..<3 where !tokenField.exists {
      app.swipeUp()
    }
    XCTAssertTrue(tokenField.exists)
    XCTAssertTrue(app.buttons["test-authenticated-api"].exists)

    webhookField.tap()
    webhookField.typeText("fixture-private-webhook")
    app.buttons["test-webhook"].tap()
    XCTAssertTrue(
      app.staticTexts["Connection succeeded"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertFalse(app.buttons["save-connection"].isEnabled)

    tokenField.tap()
    tokenField.typeText("fixture-private-token")
    XCTAssertFalse(app.staticTexts["fixture-private-token"].exists)
    XCTAssertNotEqual(tokenField.value as? String, "fixture-private-token")
    app.buttons["test-authenticated-api"].tap()
    XCTAssertTrue(app.buttons["save-connection"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.buttons["save-connection"].isEnabled)

    app.buttons["save-connection"].tap()
    XCTAssertTrue(app.buttons["sync-now"].waitForExistence(timeout: UITestWait.standard))
  }

  func testBackingOutOfConnectClearsSecretsAndTests() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-onboarding"]
    app.launch()
    app.buttons["privacy-continue"].tap()
    let steps = app.switches["metric-steps"]
    XCTAssertTrue(steps.waitForExistence(timeout: UITestWait.standard))
    steps.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    app.buttons["request-health-access"].tap()
    XCTAssertTrue(app.navigationBars["Connect"].waitForExistence(timeout: UITestWait.standard))
    fillNonSecretConnectionFields(in: app)

    let webhookField = app.secureTextFields["webhook-secret-field"]
    let tokenField = app.secureTextFields["access-token-field"]
    XCTAssertTrue(scrollToExistence(webhookField, in: app))
    webhookField.tap()
    webhookField.typeText("fixture-private-webhook")
    app.buttons["test-webhook"].tap()
    XCTAssertTrue(scrollToExistence(tokenField, in: app))
    tokenField.tap()
    tokenField.typeText("fixture-private-token")
    app.buttons["test-authenticated-api"].tap()
    XCTAssertTrue(
      app.staticTexts["Connection succeeded"].waitForExistence(timeout: UITestWait.standard))

    app.navigationBars["Connect"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(
      app.navigationBars["Choose Metrics"].waitForExistence(timeout: UITestWait.standard))
    let requestAccess = app.buttons["request-health-access"]
    XCTAssertTrue(scrollToExistence(requestAccess, in: app))
    requestAccess.tap()

    XCTAssertTrue(app.navigationBars["Connect"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(scrollToExistence(app.secureTextFields["webhook-secret-field"], in: app))
    XCTAssertNotEqual(
      app.secureTextFields["webhook-secret-field"].value as? String,
      "fixture-private-webhook"
    )
    XCTAssertTrue(scrollToExistence(app.secureTextFields["access-token-field"], in: app))
    XCTAssertNotEqual(
      app.secureTextFields["access-token-field"].value as? String,
      "fixture-private-token"
    )
    XCTAssertFalse(app.staticTexts["Connection succeeded"].exists)
  }

  func testDashboardSyncReportsCountsWithoutHealthValues() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-dashboard"]
    app.launch()

    let syncButton = app.buttons["sync-now"]
    XCTAssertTrue(syncButton.waitForExistence(timeout: UITestWait.standard))
    let syncTitle = app.staticTexts["sync-now-title"]
    XCTAssertTrue(syncTitle.waitForExistence(timeout: UITestWait.standard))
    XCTAssertEqual(syncTitle.frame.midX, syncButton.frame.midX, accuracy: 1)
    XCTAssertTrue(app.staticTexts["Daily Steps"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.staticTexts["246"].exists)
    XCTAssertTrue(app.staticTexts["Walking + Running Distance"].exists)
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "234 m"))
        .firstMatch.exists
    )
    XCTAssertTrue(app.staticTexts["Flights Climbed"].exists)
    XCTAssertTrue(app.staticTexts["8"].exists)
    XCTAssertFalse(app.staticTexts["Heart Rate"].exists)
    syncButton.tap()
    XCTAssertFalse(app.descendants(matching: .any)["sync-direction"].exists)
    let lastSync = app.descendants(matching: .any)["last-sync"]
    XCTAssertTrue(scrollToExistence(lastSync, in: app))
    XCTAssertFalse(lastSync.label.contains("ago"))
    XCTAssertTrue(lastSync.label.contains("2026"))
    XCTAssertTrue(lastSync.label.contains(":"))
    XCTAssertFalse(app.staticTexts["8421"].exists)
    XCTAssertFalse(app.staticTexts["fixture-private-secret"].exists)
  }

  private func fillNonSecretConnectionFields(in app: XCUIApplication) {
    let baseURL = app.textFields["base-url-field"]
    XCTAssertTrue(baseURL.waitForExistence(timeout: UITestWait.standard))
    baseURL.tap()
    baseURL.typeText("https://ha.example.test")
    let userID = app.textFields["user-id-field"]
    userID.tap()
    userID.typeText("example-user")
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
