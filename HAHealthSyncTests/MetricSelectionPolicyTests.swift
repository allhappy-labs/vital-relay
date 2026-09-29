import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class MetricSelectionPolicyTests: XCTestCase {
  func testTurnAllOnSelectsEveryMetricAvailableOnCurrentOS() {
    let available = MetricSelectionPolicy.availableMetricIDs(osMajorVersion: 18)
    var selection: Set<MetricID> = [.steps]

    MetricSelectionPolicy.turnAllOn(
      selection: &selection,
      osMajorVersion: 18
    )

    XCTAssertEqual(selection, available)
    XCTAssertTrue(selection.contains(.bodyMass))
    XCTAssertFalse(
      selection.contains { metricID in
        MetricRegistry[metricID]?.minimumIOSMajorVersion ?? 18 > 18
      }
    )
  }

  func testTurnAllOffClearsPartialOrCompleteSelection() {
    var selection: Set<MetricID> = [.steps, .bodyMass]

    MetricSelectionPolicy.turnAllOff(selection: &selection)

    XCTAssertTrue(selection.isEmpty)
  }

  func testSearchMatchesDisplayNameCaseInsensitively() {
    let results = MetricSelectionPolicy.filteredDefinitions(
      query: "heart rate",
      osMajorVersion: 26
    )

    XCTAssertTrue(results.contains { $0.id == .heartRate })
    XCTAssertTrue(results.contains { $0.id == .restingHeartRate })
    XCTAssertFalse(results.contains { $0.id == .steps })
  }

  func testBlankSearchReturnsAllAvailableDefinitions() {
    XCTAssertEqual(
      Set(
        MetricSelectionPolicy.filteredDefinitions(query: "", osMajorVersion: 18)
          .map(\.id)
      ),
      MetricSelectionPolicy.availableMetricIDs(osMajorVersion: 18)
    )
  }

  func testRuntimeUnavailableTypeIsOmittedFromSelection() {
    let available = MetricSelectionPolicy.availableMetricIDs(
      osMajorVersion: 18,
      isTypeAvailable: { $0 != .runningPower }
    )
    let definitions = MetricSelectionPolicy.filteredDefinitions(
      query: "",
      osMajorVersion: 18,
      isTypeAvailable: { $0 != .runningPower }
    )

    XCTAssertFalse(available.contains(.runningPower))
    XCTAssertFalse(definitions.contains { $0.id == .runningPower })
    XCTAssertTrue(available.contains(.steps))
  }

  func testSelectAllPreservesPreviouslyConfiguredUnavailableMetric() {
    var selection: Set<MetricID> = [.runningPower]

    MetricSelectionPolicy.turnAllOn(
      selection: &selection,
      osMajorVersion: 18,
      isTypeAvailable: { $0 != .runningPower }
    )

    XCTAssertTrue(selection.contains(.runningPower))
    XCTAssertTrue(selection.contains(.steps))
  }

  func testOnboardingDefinitionsOmitRuntimeUnavailableMetric() {
    let definitions = MetricSelectionPolicy.onboardingDefinitions(
      osMajorVersion: 18,
      isTypeAvailable: { $0 != .runningPower }
    )

    XCTAssertFalse(definitions.contains { $0.id == .runningPower })
    XCTAssertTrue(definitions.contains { $0.id == .steps })
  }
}
