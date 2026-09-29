import XCTest

@MainActor
final class PairingFlowSmokeTests: XCTestCase {
  func testUVExposurePresetEnablesFromOneToggle() {
    let app = launchPairingsApp()
    openPairingList(in: app)

    let toggle = app.switches["uv-exposure-import-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: UITestWait.standard))
    XCTAssertEqual(toggle.value as? String, "0")

    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

    XCTAssertTrue(
      app.buttons["pairing-sensor.home_current_uv_index"].waitForExistence(
        timeout: UITestWait.standard)
    )
    XCTAssertEqual(toggle.value as? String, "1")
  }

  func testEditorShowsOnlyWritableDestinationsAndValidatesEntity() {
    let app = launchPairingsApp()
    openPairingList(in: app)
    app.buttons["add-pairing"].tap()

    XCTAssertTrue(app.navigationBars["New Pairing"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.textFields["pairing-entity-id"].exists)
    XCTAssertEqual(app.switches["pairing-enabled"].value as? String, "1")
    XCTAssertTrue(app.buttons["request-health-write-access"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["pairing-destination-unit"].exists)

    let destination = app.buttons["pairing-destination"]
    XCTAssertTrue(destination.exists)
    XCTAssertTrue(destination.label.contains("Body Mass"))
    XCTAssertFalse(app.staticTexts["Resting Heart Rate"].exists)
    XCTAssertFalse(app.staticTexts["VO2 Max"].exists)

    let entity = app.textFields["pairing-entity-id"]
    entity.tap()
    entity.typeText("Sensor.Bad")
    app.buttons["save-pairing"].tap()
    XCTAssertTrue(app.staticTexts["pairing-validation-error"].exists)
  }

  func testCreatesRejectsDuplicateAndConfirmsDeletion() {
    let app = launchPairingsApp()
    openPairingList(in: app)
    createBodyMassPairing(in: app)

    let row = app.buttons["pairing-sensor.body_mass"]
    XCTAssertTrue(row.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.buttons["review-health-write-permissions"].isEnabled)

    app.buttons["add-pairing"].tap()
    let duplicateEntity = app.textFields["pairing-entity-id"]
    XCTAssertTrue(duplicateEntity.waitForExistence(timeout: UITestWait.standard))
    duplicateEntity.tap()
    duplicateEntity.typeText("sensor.body_mass")
    app.buttons["save-pairing"].tap()
    let validationError = app.staticTexts["pairing-validation-error"]
    XCTAssertTrue(validationError.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(validationError.label.contains("already uses"))

    app.navigationBars["Edit Pairing"].buttons.firstMatch.tap()
    XCTAssertTrue(row.waitForExistence(timeout: UITestWait.standard))
    row.swipeLeft()
    app.buttons["Delete"].tap()
    XCTAssertTrue(app.buttons["Delete Pairing"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Delete Pairing"].tap()
    XCTAssertFalse(row.waitForExistence(timeout: 1))
  }

  private func launchPairingsApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-pairings"]
    app.launch()
    return app
  }

  private func openPairingList(in app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()
    let importSettings = app.buttons["settings-import-apple-health"]
    XCTAssertTrue(importSettings.waitForExistence(timeout: UITestWait.standard))
    importSettings.tap()
    let pairings = app.buttons["health-import-pairings"]
    XCTAssertTrue(scrollToExistence(pairings, in: app))
    pairings.tap()
    XCTAssertTrue(
      app.navigationBars["Entity Pairings"].waitForExistence(timeout: UITestWait.standard))
  }

  private func createBodyMassPairing(in app: XCUIApplication) {
    app.buttons["add-pairing"].tap()
    let entity = app.textFields["pairing-entity-id"]
    XCTAssertTrue(entity.waitForExistence(timeout: UITestWait.standard))
    entity.tap()
    entity.typeText("sensor.body_mass")
    XCTAssertEqual(app.switches["pairing-enabled"].value as? String, "1")
    app.buttons["request-health-write-access"].tap()
    app.buttons["save-pairing"].tap()
  }

  private func scrollToExistence(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 8
  ) -> Bool {
    for _ in 0..<maxSwipes where !element.exists {
      app.swipeUp()
    }
    return element.exists
  }
}
