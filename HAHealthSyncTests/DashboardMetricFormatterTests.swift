import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class DashboardMetricFormatterTests: XCTestCase {
  func testStepsUseWholeNumberFormatting() {
    XCTAssertEqual(
      DashboardMetricFormatter.value(
        246,
        unit: .count,
        locale: Locale(identifier: "en_GB")
      ),
      "246"
    )
  }

  func testHeartRateUsesFriendlyUnit() {
    XCTAssertEqual(
      DashboardMetricFormatter.value(
        72,
        unit: .beatsPerMinute,
        locale: Locale(identifier: "en_GB")
      ),
      "72 bpm"
    )
  }

  func testSleepDurationUsesHoursAndMinutes() {
    XCTAssertEqual(DashboardMetricFormatter.sleepDuration(27_900), "7 hr 45 min")
  }

  func testPreferredHeroReadingsUseOnlyDailyIPhoneMetrics() {
    let state = DashboardPreviewState(readings: [
      .steps: .init(metricID: .steps, timestamp: .distantPast, value: 246),
      .distance: .init(
        metricID: .distance,
        timestamp: .distantPast,
        value: 1_234
      ),
      .flightsClimbed: .init(
        metricID: .flightsClimbed,
        timestamp: .distantPast,
        value: 8
      ),
      .heartRate: .init(metricID: .heartRate, timestamp: .distantPast, value: 72),
      .sleepDuration: .init(metricID: .sleepDuration, timestamp: .distantPast, value: 27_900),
    ])

    XCTAssertEqual(
      DashboardMetricFormatter.iPhoneDailyReadings(in: state).map(\.metricID),
      [.steps, .distance, .flightsClimbed]
    )
  }

  func testLastSyncUsesAbsoluteDateAndTime() {
    let date = Date(timeIntervalSince1970: 1_788_035_400)

    XCTAssertEqual(
      DashboardMetricFormatter.lastSync(
        date,
        locale: Locale(identifier: "en_GB"),
        timeZone: TimeZone(secondsFromGMT: 0)!
      ),
      "29 Aug 2026 at 20:30"
    )
  }
}
