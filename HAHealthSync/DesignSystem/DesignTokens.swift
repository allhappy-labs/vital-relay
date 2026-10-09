import HealthSyncCore
import SwiftUI
import UIKit

enum DesignTokens {
  static let tileCornerRadius: CGFloat = 8
  static let cardCornerRadius: CGFloat = 20
  static let iconTileSize: CGFloat = 29

  /// Fill for prominent primary buttons. Links and plain buttons keep the blue app accent so
  /// they still read as tappable.
  static let primaryActionTint = Color(
    light: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1),
    dark: UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1))
}

extension Color {
  /// A colour with explicit light and dark values, resolved by the trait collection.
  init(light: UIColor, dark: UIColor) {
    self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
  }
}

extension MetricCategory {
  /// The single source for category colour, close to Apple Health's conventions.
  var tint: Color {
    switch self {
    case .activity:
      Color(
        light: UIColor(red: 1.00, green: 0.42, blue: 0.00, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.58, blue: 0.20, alpha: 1))
    case .vitals:
      Color(
        light: UIColor(red: 1.00, green: 0.18, blue: 0.33, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.38, blue: 0.48, alpha: 1))
    case .sleep:
      Color(
        light: UIColor(red: 0.37, green: 0.36, blue: 0.90, alpha: 1),
        dark: UIColor(red: 0.55, green: 0.54, blue: 1.00, alpha: 1))
    case .bodyMeasurements:
      Color(
        light: UIColor(red: 0.19, green: 0.69, blue: 0.78, alpha: 1),
        dark: UIColor(red: 0.39, green: 0.82, blue: 0.90, alpha: 1))
    case .other:
      Color(uiColor: .systemGray)
    }
  }

  var symbol: String {
    switch self {
    case .activity: "flame.fill"
    case .vitals: "heart.fill"
    case .sleep: "bed.double.fill"
    case .bodyMeasurements: "figure"
    case .other: "square.grid.2x2.fill"
    }
  }

  var title: String {
    switch self {
    case .activity: "Activity"
    case .bodyMeasurements: "Body Measurements"
    case .vitals: "Vitals"
    case .sleep: "Sleep"
    case .other: "Other"
    }
  }
}

/// Sync state styling. Always shown with its symbol and text, never colour alone.
enum StatusTone: CaseIterable {
  case synced, syncing, attention, failed

  var color: Color {
    switch self {
    case .synced: .green
    case .syncing: .blue
    case .attention: .orange
    case .failed: .red
    }
  }

  var symbol: String {
    switch self {
    case .synced: "checkmark.circle.fill"
    case .syncing: "arrow.triangle.2.circlepath.circle.fill"
    case .attention: "exclamationmark.triangle.fill"
    case .failed: "xmark.octagon.fill"
    }
  }
}
