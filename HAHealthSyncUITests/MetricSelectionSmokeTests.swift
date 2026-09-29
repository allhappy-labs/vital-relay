import XCTest

@MainActor
final class MetricSelectionSmokeTests: XCTestCase {
  func testOnboardingShowsCategorizedInitialMetrics() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-onboarding"]
    app.launch()

    XCTAssertTrue(app.buttons["privacy-continue"].waitForExistence(timeout: UITestWait.standard))
    app.buttons["privacy-continue"].tap()

    let expected = [
      ("metric-category-activity", "metric-steps"),
      ("metric-category-bodyMeasurements", "metric-body_mass"),
      ("metric-category-vitals", "metric-resting_heart_rate"),
      ("metric-category-sleep", "metric-sleep_duration"),
      ("metric-category-other", "metric-last_apple_workout"),
    ]
    for (header, metric) in expected {
      XCTAssertTrue(scrollToExistence(app.staticTexts[header], in: app))
      XCTAssertTrue(scrollToExistence(app.switches[metric], in: app))
      XCTAssertEqual(app.switches.matching(identifier: metric).count, 1)
    }
    XCTAssertFalse(app.switches["metric-last_sync_time"].exists)
    XCTAssertFalse(app.switches["metric-test_connection"].exists)
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
