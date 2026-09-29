import Foundation
import HealthSyncCore

enum DashboardMetricFormatter {
  static func iPhoneDailyReadings(in state: DashboardPreviewState) -> [MetricReading] {
    [.steps, .distance, .flightsClimbed]
      .compactMap { state.readings[$0] }
  }

  static func value(
    _ value: Double,
    unit: UnitSymbol,
    locale: Locale = .current
  ) -> String {
    let number: String
    if unit == .count {
      number = value.formatted(
        .number.locale(locale).precision(.fractionLength(0))
      )
    } else {
      number = value.formatted(
        .number.locale(locale).precision(.fractionLength(0...2))
      )
    }

    return switch unit {
    case .count:
      number
    case .beatsPerMinute:
      "\(number) bpm"
    case .seconds:
      sleepDuration(value)
    default:
      "\(number) \(unit.rawValue)"
    }
  }

  static func sleepDuration(_ seconds: Double) -> String {
    let totalMinutes = max(0, Int(seconds.rounded()) / 60)
    return "\(totalMinutes / 60) hr \(totalMinutes % 60) min"
  }

  static func lastSync(
    _ date: Date,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
