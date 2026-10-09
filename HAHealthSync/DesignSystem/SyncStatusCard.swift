import HealthSyncCore
import SwiftUI

struct SyncStatusSummary: Equatable {
  let tone: StatusTone
  let title: String
  let detail: String

  /// Syncing, then a current error, then history decides the headline. An error after an
  /// earlier success must not read as "All synced".
  static func make(
    isSyncing: Bool,
    currentError: SyncFailureCategory?,
    lastSuccessfulSync: Date?,
    formatLastSync: (Date) -> String = { DashboardMetricFormatter.lastSync($0) }
  ) -> SyncStatusSummary {
    let detail = "Last sync: \(lastSuccessfulSync.map(formatLastSync) ?? "Never")"
    if isSyncing { return .init(tone: .syncing, title: "Syncing…", detail: detail) }
    if let currentError {
      return .init(tone: .attention, title: "Sync issue: \(currentError.rawValue)", detail: detail)
    }
    if lastSuccessfulSync == nil {
      return .init(tone: .attention, title: "Not synced yet", detail: detail)
    }
    return .init(tone: .synced, title: "All synced", detail: detail)
  }
}

struct SyncStatusCard<Action: View>: View {
  let summary: SyncStatusSummary
  private let actionView: Action

  init(summary: SyncStatusSummary, @ViewBuilder action: () -> Action) {
    self.summary = summary
    self.actionView = action()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Group {
          if summary.tone == .syncing {
            ProgressView()
          } else {
            Image(systemName: summary.tone.symbol)
              .font(.title)
              .foregroundStyle(summary.tone.color)
          }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(summary.title)
            .font(.headline)
          Text(summary.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("last-sync")
        }
      }
      actionView
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(uiColor: .secondarySystemGroupedBackground),
      in: .rect(cornerRadius: DesignTokens.cardCornerRadius))
  }
}
