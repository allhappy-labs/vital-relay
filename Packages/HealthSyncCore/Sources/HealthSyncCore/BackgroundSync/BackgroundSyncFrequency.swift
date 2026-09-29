import Foundation

public enum BackgroundSyncFrequency: String, Codable, CaseIterable, Sendable, Equatable {
  case responsive
  case balanced
  case batterySaver
  case daily

  public var displayName: String {
    switch self {
    case .responsive: "Responsive"
    case .balanced: "Balanced"
    case .batterySaver: "Battery Saver"
    case .daily: "Daily"
    }
  }

  public var selectionLabel: String {
    switch self {
    case .responsive: "Responsive — 5 min"
    case .balanced: "Balanced — 15 min"
    case .batterySaver: "Battery Saver — 1 hr"
    case .daily: "Daily"
    }
  }

  public var minimumInterval: TimeInterval {
    switch self {
    case .responsive: 5 * 60
    case .balanced: 15 * 60
    case .batterySaver: 60 * 60
    case .daily: 24 * 60 * 60
    }
  }
}
