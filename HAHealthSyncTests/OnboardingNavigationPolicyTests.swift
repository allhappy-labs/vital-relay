import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class OnboardingNavigationPolicyTests: XCTestCase {
  func testStepNumbersAreStable() {
    XCTAssertEqual(OnboardingNavigationPolicy.step(for: nil), 1)
    XCTAssertEqual(OnboardingNavigationPolicy.step(for: .metrics), 2)
    XCTAssertEqual(OnboardingNavigationPolicy.step(for: .connect([.steps])), 3)
  }

  func testConnectBackDestinationIsMetrics() {
    XCTAssertEqual(
      OnboardingNavigationPolicy.previousRoute(from: .connect([.steps])),
      .metrics
    )
  }

  func testConnectRouteCarriesTheAuthorizedMetricSelection() {
    let selection: Set<MetricID> = [.steps, .bodyMass]

    guard case .connect(let routedSelection) = OnboardingRoute.connect(selection) else {
      return XCTFail("Expected the connection route")
    }

    XCTAssertEqual(routedSelection, selection)
  }
}
