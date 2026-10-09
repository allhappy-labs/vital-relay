import HealthSyncCore
import SwiftUI
import XCTest

@testable import HAHealthSync

final class DesignTokensTests: XCTestCase {
  func testEveryCategoryHasDistinctTintAndSymbol() {
    let light = UITraitCollection(userInterfaceStyle: .light)
    let tints = MetricCategory.allCases.map { category -> String in
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0
      UIColor(category.tint).resolvedColor(with: light)
        .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      return String(format: "%.3f %.3f %.3f", red, green, blue)
    }
    let symbols = MetricCategory.allCases.map(\.symbol)
    XCTAssertEqual(Set(tints).count, MetricCategory.allCases.count)
    XCTAssertEqual(Set(symbols).count, MetricCategory.allCases.count)
  }

  func testCategoryTitlesMatchExistingSectionHeaders() {
    XCTAssertEqual(MetricCategory.activity.title, "Activity")
    XCTAssertEqual(MetricCategory.bodyMeasurements.title, "Body Measurements")
    XCTAssertEqual(MetricCategory.vitals.title, "Vitals")
    XCTAssertEqual(MetricCategory.sleep.title, "Sleep")
    XCTAssertEqual(MetricCategory.other.title, "Other")
  }

  func testStatusTonesNeverRelyOnColourAlone() {
    let symbols = StatusTone.allCases.map(\.symbol)
    XCTAssertFalse(symbols.contains(""))
    XCTAssertEqual(Set(symbols).count, StatusTone.allCases.count)
  }

  func testPrimaryActionTintIsNearBlackInLightAndNearWhiteInDark() {
    func brightness(_ style: UIUserInterfaceStyle) -> CGFloat {
      var white: CGFloat = 0
      var alpha: CGFloat = 0
      UIColor(DesignTokens.primaryActionTint)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        .getWhite(&white, alpha: &alpha)
      return white
    }
    XCTAssertLessThan(brightness(.light), 0.2)
    XCTAssertGreaterThan(brightness(.dark), 0.9)
  }
}
