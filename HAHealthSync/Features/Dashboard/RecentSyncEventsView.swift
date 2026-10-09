import HealthSyncCore
import SwiftUI

struct RecentSyncEventsView: View {
  let events: [SyncStatusEvent]

  var body: some View {
    List {
      if events.isEmpty {
        ContentUnavailableView(
          "No Sync Events",
          systemImage: "clock",
          description: Text("A privacy-safe summary appears after synchronization.")
        )
      } else {
        ForEach(Array(events.reversed().enumerated()), id: \.offset) { _, event in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Image(systemName: tone(for: event).symbol)
                .foregroundStyle(tone(for: event).color)
                .accessibilityHidden(true)
              Text(
                event.outcome == .interrupted
                  ? "\(RecentSyncEventFormatter.triggerTitle(event.trigger)) · Interrupted"
                  : RecentSyncEventFormatter.triggerTitle(event.trigger)
              )
              Spacer()
              Text(event.finishedAt.formatted(date: .abbreviated, time: .standard))
                .foregroundStyle(.secondary)
            }
            Text(RecentSyncEventFormatter.summary(event))
              .font(.footnote)
              .foregroundStyle(.secondary)
            if let scope = RecentSyncEventFormatter.scopeSummary(event) {
              Text(scope)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
    .navigationTitle("Recent Sync Events")
    .accessibilityIdentifier("recent-sync-events-list")
  }

  private func tone(for event: SyncStatusEvent) -> StatusTone {
    if event.outcome == .interrupted { return .attention }
    if event.failureCategories.contains(.deviceLocked) { return .attention }
    return event.failureCategories.isEmpty ? .synced : .failed
  }
}

enum RecentSyncEventFormatter {
  static func triggerTitle(_ trigger: SyncTrigger) -> String {
    switch trigger {
    case .manual: "Sync now"
    case .pullToRefresh: "Pull to refresh"
    case .background: "Background"
    case .shortcut: "Shortcut"
    case .healthKitObserver: "Health update"
    case .appRefresh: "Background refresh"
    }
  }

  static func summary(_ event: SyncStatusEvent) -> String {
    if event.outcome == .interrupted {
      return (["Interrupted before finishing"] + details(event)).joined(separator: " · ")
    }

    let importSummary =
      "Imported \(event.savedPairings) · \(event.skippedPairings) unchanged"

    if event.failureCategories.contains(.deviceLocked) {
      return (["Export deferred — iPhone locked", importSummary] + details(event))
        .joined(separator: " · ")
    }

    var components = [
      "Exported \(event.synchronizedMetrics)",
      "\(event.skippedMetrics) unchanged",
      importSummary,
    ]
    let issues = issueSummary(event.failureCategories)
    if !issues.isEmpty {
      components.append("Issues: \(issues)")
    }
    return (components + details(event)).joined(separator: " · ")
  }

  /// What the run set out to cover and how much of it it reached, or `nil` for an event no
  /// scope was resolved for — every run recorded before scoping existed, and interrupted ones.
  static func scopeSummary(_ event: SyncStatusEvent) -> String? {
    guard let reason = event.scopeReason.flatMap(SyncScopeReason.init(rawValue:)) else {
      return nil
    }
    var components = [isFullSweep(reason) ? "Full sweep" : "Health update"]
    // A missing collected count is omitted rather than assumed to match what was requested:
    // claiming full coverage on a diagnostics surface is the one reading that cannot be checked.
    if let requested = event.requestedMetrics, let collected = event.collectedMetrics {
      components.append(
        collected == requested
          ? "\(requested) metrics checked"
          : "\(collected) of \(requested) metrics checked"
      )
    }
    // Truncation reads differently from failure: these metrics kept their anchors and lead the
    // next run, so a non-zero count is the budget talking, not an error.
    if let deferred = event.deferredMetrics, deferred > 0 {
      components.append("\(deferred) deferred")
    }
    if let starved = event.starvedMetrics, starved > 0 {
      components.append("\(starved) starved")
    }
    return components.joined(separator: " · ")
  }

  /// Whether the reason names a run over the whole selection. Listed rather than derived so a
  /// new reason has to say which side it falls on.
  private static func isFullSweep(_ reason: SyncScopeReason) -> Bool {
    switch reason {
    case .trigger, .firstRunAfterLaunch, .sweepDue, .dayRollover, .unknownChange: true
    case .changedTypes, .staleMetrics: false
    }
  }

  static func outcomeLabel(_ event: SyncStatusEvent) -> String {
    if event.outcome == .interrupted { return "Interrupted" }
    if event.failureCategories.contains(.deviceLocked) { return "iPhone locked" }
    if !event.failureCategories.isEmpty { return "Issues" }
    if event.synchronizedMetrics > 0 { return "Exported \(event.synchronizedMetrics)" }
    if event.savedPairings > 0 { return "Imported \(event.savedPairings)" }
    return "Nothing new"
  }

  private static func details(_ event: SyncStatusEvent) -> [String] {
    var details: [String] = []
    if let duration = event.duration, duration >= 1 {
      details.append("\(Int(duration.rounded())) s")
    }
    if let requests = event.requestCount, requests > 0 {
      details.append(requests == 1 ? "1 request" : "\(requests) requests")
    }
    if event.throttledWakesBefore > 0 {
      details.append(
        event.throttledWakesBefore == 1
          ? "1 skipped wake-up" : "\(event.throttledWakesBefore) skipped wake-ups"
      )
    }
    return details
  }

  private static func issueSummary(_ categories: [SyncFailureCategory]) -> String {
    var order: [SyncFailureCategory] = []
    var counts: [SyncFailureCategory: Int] = [:]
    for category in categories {
      if counts[category] == nil {
        order.append(category)
      }
      counts[category, default: 0] += 1
    }
    return order.map { category in
      let count = counts[category, default: 0]
      return count == 1 ? issueLabel(category) : "\(count) \(issueLabel(category))"
    }.joined(separator: ", ")
  }

  private static func issueLabel(_ category: SyncFailureCategory) -> String {
    switch category {
    case .healthKit: "HealthKit"
    case .deviceLocked: "iPhone locked"
    case .deadlineExceeded: "out of background time"
    default: category.rawValue
    }
  }
}
