import XCTest

@testable import HAHealthSync

final class StepGoalTests: XCTestCase {
  func testProgressIsClampedToUnitRange() {
    XCTAssertEqual(StepGoal.progress(-50), 0)
    XCTAssertEqual(StepGoal.progress(5_000), 0.5)
    XCTAssertEqual(StepGoal.progress(25_000), 1)
  }

  func testPercentTextNeverExceedsOneHundred() {
    XCTAssertEqual(StepGoal.percentText(8_412), "84% of 10,000")
    XCTAssertEqual(StepGoal.percentText(25_000), "100% of 10,000")
  }
}
