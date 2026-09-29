import HealthSyncCore
import os

enum BackgroundLog {
  static let logger = Logger(subsystem: "com.olhapi.HAHealthSync", category: "background")

  /// One line per scope decision, or `nil` for a run no scope was resolved for. Counts,
  /// categories and dates only — never a metric's value.
  static func scopeMessage(for report: BidirectionalSyncReport) -> String? {
    guard let reason = report.scopeReason else { return nil }
    var parts = ["Scope \(report.trigger.rawValue)", "reason=\(reason.rawValue)"]
    if let requested = report.requestedMetrics { parts.append("requested=\(requested)") }
    if let collected = report.outbound?.collectedMetrics { parts.append("collected=\(collected)") }
    // A truncated run and a quiet one report the same collected count; only this tells them apart.
    if let deferred = report.outbound?.deferredMetrics, deferred > 0 {
      parts.append("deferred=\(deferred)")
    }
    if let changed = report.changedTypes { parts.append("changed=\(changed)") }
    if let starved = report.starvedMetrics { parts.append("starved=\(starved)") }
    return parts.joined(separator: " ")
  }
}
