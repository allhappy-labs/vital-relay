import AppIntents
import XCTest

@MainActor
final class BackgroundSettingsSmokeTests: XCTestCase {
  func testBackgroundStatusIsExplicitBestEffortAndValueFree() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-background"]
    app.launch()

    openBackgroundSettings(in: app)

    XCTAssertTrue(
      app.switches["background-sync-toggle"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertEqual(app.switches["background-sync-toggle"].value as? String, "1")
    XCTAssertTrue(app.switches["background-sync-toggle"].isEnabled)
    let picker = app.buttons["background-sync-frequency-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(picker.label.contains("Balanced"))
    picker.tap()
    XCTAssertTrue(app.buttons["Daily"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Daily"].tap()
    XCTAssertTrue(picker.label.contains("Daily"))
    XCTAssertTrue(app.staticTexts["background-frequency-explanation"].exists)

    let registrations = app.buttons["background-metric-registrations"]
    XCTAssertTrue(scrollToExistence(registrations, in: app))
    registrations.tap()
    let stepsRegistration = app.descendants(matching: .any)["background-registration-steps"]
    XCTAssertTrue(scrollToExistence(stepsRegistration, in: app))
    XCTAssertTrue(stepsRegistration.label.contains("Registered"))
    let restingRegistration =
      app.descendants(matching: .any)["background-registration-resting_heart_rate"]
    XCTAssertTrue(scrollToExistence(restingRegistration, in: app))
    XCTAssertTrue(restingRegistration.label.contains("Failed: healthKit"))
    XCTAssertFalse(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "30 minutes")).firstMatch
        .exists)
    XCTAssertFalse(app.staticTexts["8421"].exists)

  }

  func testDisabledBackgroundKeepsConfiguredPickerVisibleAndDisabled() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-background-disabled"]
    app.launch()

    openBackgroundSettings(in: app)

    let picker = app.buttons["background-sync-frequency-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(picker.label.contains("Battery Saver"))
    XCTAssertFalse(picker.isEnabled)
  }

  func testRecentEventsShowCountsAndCategoriesWithoutValues() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing-background",
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_GB",
      "-AppleTimeZone", "Europe/Zurich",
    ]
    app.launch()

    openBackgroundSettings(in: app)
    let recentEvents = app.buttons["background-recent-events"]
    XCTAssertTrue(scrollToExistence(recentEvents, in: app))
    recentEvents.tap()

    XCTAssertTrue(
      app.navigationBars["Recent Sync Events"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.staticTexts["Background"].exists)
    XCTAssertTrue(
      app.staticTexts[
        "Exported 2 · 0 unchanged · Imported 1 · 0 unchanged · Issues: HealthKit"
      ].exists
    )
    XCTAssertTrue(
      app.staticTexts["Exported 3 · 0 unchanged · Imported 1 · 0 unchanged"].exists
    )
    XCTAssertTrue(app.staticTexts["Full sweep · 3 metrics checked · 2 starved"].exists)
    XCTAssertTrue(app.staticTexts["29 Aug 2026 at 22:30:00"].exists)
    XCTAssertTrue(app.staticTexts["29 Aug 2026 at 22:30:01"].exists)
    XCTAssertFalse(app.staticTexts["8421"].exists)
    XCTAssertFalse(app.staticTexts["fixture-secret"].exists)
  }

  func testSystemStatusRowsAndShortcutsGuide() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing-background",
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_GB",
      "-AppleTimeZone", "Europe/Zurich",
    ]
    app.launch()

    openBackgroundSettings(in: app)

    let refresh = app.descendants(matching: .any)["background-system-refresh"]
    XCTAssertTrue(scrollToExistence(refresh, in: app))
    XCTAssertTrue(app.descendants(matching: .any)["background-system-low-power"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["background-system-earliest-next"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["background-system-last-automatic"].exists)
    let lastSweep = app.descendants(matching: .any)["background-system-last-sweep"]
    XCTAssertTrue(scrollToExistence(lastSweep, in: app))
    XCTAssertTrue(lastSweep.label.contains("Last full sweep"))
    // The rendered date, not just the row: a broken store read would render "Never" here.
    XCTAssertTrue(lastSweep.label.contains("29 Aug 2026"))
    // The starved count is diagnostics, not a status row: this fixture's newest sweep reports 2,
    // and the Recent Sync Events log is the only place that says so.
    XCTAssertFalse(app.descendants(matching: .any)["background-system-starved"].exists)
    XCTAssertFalse(
      app.descendants(matching: .any)["background-system-starved-explanation"].exists
    )
    let toggle = app.switches["background-publish-attempts-toggle"]
    XCTAssertTrue(scrollToExistence(toggle, in: app))
    XCTAssertEqual(toggle.value as? String, "0")

    let guide = app.buttons["background-shortcuts-guide"]
    XCTAssertTrue(scrollToExistence(guide, in: app))
    guide.tap()
    XCTAssertTrue(
      app.navigationBars["Sync with Shortcuts"].waitForExistence(timeout: UITestWait.standard))
    XCTAssertTrue(app.buttons["shortcuts-guide-open"].exists)
  }

  private func openBackgroundSettings(in app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["Settings"].tap()
    let export = app.buttons["settings-export-home-assistant"]
    XCTAssertTrue(export.waitForExistence(timeout: UITestWait.standard))
    export.tap()
    let background = app.buttons["background-sync-settings"]
    XCTAssertTrue(background.waitForExistence(timeout: UITestWait.standard))
    background.tap()
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
