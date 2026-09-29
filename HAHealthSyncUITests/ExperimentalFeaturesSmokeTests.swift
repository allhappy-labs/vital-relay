import XCTest

@MainActor
final class ExperimentalFeaturesSmokeTests: XCTestCase {
  func testArchiveRecoveryBlockersExposeAffectedTypeAndSafeGuidance() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-archive", "-ui-testing-archive-recovery"]
    app.launch()
    app.buttons["Settings"].tap()
    openExportSettings(in: app)
    let settings = app.buttons["historical-import-settings"]
    XCTAssertTrue(scrollToExistence(settings, in: app))
    settings.tap()
    let start = app.buttons["historical-import-start"]
    XCTAssertTrue(scrollToExistence(start, in: app))
    start.tap()
    for (issue, guidance) in [
      ("authorizationUnproven", "Health access"),
      ("inventoryTooDense", "administrator"),
      ("inventoryUnstable", "Resume Import"),
    ] {
      let warning = app.staticTexts["historical-import-recovery-\(issue)"]
      XCTAssertTrue(scrollToExistence(warning, in: app))
      XCTAssertTrue(warning.label.contains("Steps"))
      XCTAssertTrue(warning.label.contains(guidance))
      XCTAssertFalse(warning.label.lowercased().contains("denied"))
    }
  }

  func testArchiveModeShowsReadableDatesProgressAndPrivacyIdentifiers() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-archive"]
    app.launch()

    app.buttons["Settings"].tap()
    openExportSettings(in: app)
    let settings = app.buttons["historical-import-settings"]
    XCTAssertTrue(scrollToExistence(settings, in: app))
    settings.tap()

    let owner = app.staticTexts["historical-import-owner-state"]
    XCTAssertTrue(scrollToExistence(owner, in: app))
    XCTAssertTrue(owner.label.contains("approved archive uploader"))
    XCTAssertFalse(owner.label.contains("fixture-secret"))
    let allHistory = app.switches["historical-import-all-readable"]
    XCTAssertTrue(scrollToExistence(allHistory, in: app))
    XCTAssertEqual(allHistory.value as? String, "1")
    let capability = app.staticTexts["historical-import-capability"]
    XCTAssertTrue(capability.label.contains("Archive protocol 2"))
    let metrics = app.buttons["historical-eligible-metrics"]
    XCTAssertTrue(scrollToExistence(metrics, in: app))
    metrics.tap()
    XCTAssertTrue(
      scrollToExistence(
        app.staticTexts["historical-import-earliest-steps"], in: app))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    let privacy = app.staticTexts["historical-import-privacy"]
    XCTAssertTrue(scrollToExistence(privacy, in: app))
    XCTAssertTrue(privacy.label.contains("long-lived copy"))
    let start = app.buttons["historical-import-start"]
    XCTAssertTrue(scrollToExistence(start, in: app))
    start.tap()
    let archived = app.descendants(matching: .any)["historical-import-archived-samples"]
    XCTAssertTrue(scrollToExistence(archived, in: app))
    XCTAssertTrue(archived.label.contains("12"))
    let statistics = app.descendants(matching: .any)["historical-import-statistics-steps"]
    XCTAssertTrue(scrollToExistence(statistics, in: app))
    XCTAssertTrue(statistics.label.contains("Failed"))
  }

  func testNoHistoryMetricsAreShownAsSkippedInsteadOfFailures() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-backfill-skips"]
    app.launch()

    app.buttons["Settings"].tap()
    openExportSettings(in: app)
    let historicalImportSettings = app.buttons["historical-import-settings"]
    XCTAssertTrue(scrollToExistence(historicalImportSettings, in: app))
    historicalImportSettings.tap()

    let toggle = app.switches["historical-import-toggle"]
    tapSwitch(toggle)
    app.alerts.buttons["Enable Experimental Import"].tap()

    let start = app.buttons["historical-import-start"]
    XCTAssertTrue(scrollToExistence(start, in: app))
    start.tap()

    let skipped = app.descendants(matching: .any)["historical-import-skipped"]
    XCTAssertTrue(scrollToExistence(skipped, in: app))
    XCTAssertTrue(skipped.label.contains("69"))
    let failures = app.descendants(matching: .any)["historical-import-failures"]
    XCTAssertTrue(scrollToExistence(failures, in: app))
    XCTAssertTrue(failures.label.contains("0"))
  }

  func testBackfillRequiresConfirmationAndIncompatibilityDoesNotDisableLiveSync() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-experimental"]
    app.launch()

    XCTAssertTrue(app.buttons["sync-now"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()
    openExportSettings(in: app)
    let historicalImportSettings = app.buttons["historical-import-settings"]
    XCTAssertTrue(scrollToExistence(historicalImportSettings, in: app))
    historicalImportSettings.tap()

    let warning = app.staticTexts["historical-import-warning"]
    XCTAssertTrue(warning.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(warning.label.contains("SQLite recorder schema 53"))
    XCTAssertTrue(warning.label.contains("history-only"))
    XCTAssertTrue(warning.label.contains("14 days"))

    let toggle = app.switches["historical-import-toggle"]
    XCTAssertEqual(toggle.value as? String, "0")
    tapSwitch(toggle)
    XCTAssertTrue(app.alerts.buttons["Cancel"].waitForExistence(timeout: UITestWait.standard))
    app.alerts.buttons["Cancel"].tap()
    XCTAssertEqual(toggle.value as? String, "0")

    tapSwitch(toggle)
    app.alerts.buttons["Enable Experimental Import"].tap()
    XCTAssertTrue(waitForValue("1", in: toggle))
    let eligibleMetrics = app.buttons["historical-eligible-metrics"]
    XCTAssertTrue(eligibleMetrics.exists)
    XCTAssertTrue(eligibleMetrics.label.contains("3 of 3"))

    let start = app.buttons["historical-import-start"]
    XCTAssertTrue(scrollToExistence(start, in: app))
    XCTAssertTrue(start.isEnabled)
    start.tap()
    let capability = app.staticTexts["historical-import-capability"]
    XCTAssertTrue(capability.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(capability.label.contains("Incompatible"))
    XCTAssertFalse(start.isEnabled)

    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["sync-now"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.buttons["sync-now"].isEnabled)
  }

  func testMedicationNamesAppearOnlyAfterPerMedicationAuthorization() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-experimental"]
    app.launch()

    XCTAssertFalse(app.staticTexts["Example medication"].exists)
    app.buttons["Settings"].tap()
    openExportSettings(in: app)
    let medicationSettings = app.buttons["medication-sync-settings"]
    XCTAssertTrue(medicationSettings.waitForExistence(timeout: UITestWait.standard))
    XCTAssertFalse(app.staticTexts["Example medication"].exists)
    medicationSettings.tap()

    XCTAssertTrue(app.staticTexts["medication-read-only-explanation"].exists)
    XCTAssertFalse(app.staticTexts["Example medication"].exists)
    app.buttons["request-medication-access"].tap()
    XCTAssertTrue(
      app.staticTexts["Example medication"].waitForExistence(timeout: UITestWait.standard))

    let toggle = app.switches["medication-sync-toggle"]
    XCTAssertTrue(toggle.isEnabled)
    tapSwitch(toggle)
    XCTAssertTrue(waitForValue("1", in: toggle))
  }

  func testMedicationSettingsAreHiddenWhenAPIsAreUnavailable() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-experimental-no-medications"]
    app.launch()

    app.buttons["Settings"].tap()
    openExportSettings(in: app)
    XCTAssertFalse(app.buttons["medication-sync-settings"].exists)
  }

  private func openExportSettings(in app: XCUIApplication) {
    let export = app.buttons["settings-export-home-assistant"]
    XCTAssertTrue(export.waitForExistence(timeout: UITestWait.standard))
    export.tap()
  }

  private func waitForValue(
    _ value: String,
    in element: XCUIElement,
    timeout: TimeInterval = 3
  ) -> Bool {
    let predicate = NSPredicate(format: "value == %@", value)
    return XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
      timeout: timeout
    ) == .completed
  }

  private func tapSwitch(_ element: XCUIElement) {
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
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
