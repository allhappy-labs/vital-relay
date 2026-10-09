import XCTest

@testable import HAHealthSync

final class DashboardLayoutTests: XCTestCase {
  func testAccessibilitySizesUseOneColumn() {
    XCTAssertEqual(DashboardLayout.columnCount(isAccessibilitySize: false), 2)
    XCTAssertEqual(DashboardLayout.columnCount(isAccessibilitySize: true), 1)
  }
}
