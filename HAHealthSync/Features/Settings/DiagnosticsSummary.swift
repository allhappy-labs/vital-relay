import Foundation
import HealthSyncCore

struct DiagnosticsSummaryRow: Equatable {
  let label: String
  let value: String
}

struct DiagnosticsSummaryInput {
  let appVersion: String
  let buildVersion: String
  let osVersion: String
  let integrationVersion: String?
  let backgroundSyncEnabled: Bool
  let backgroundSyncFrequency: BackgroundSyncFrequency
  let historicalImportEnabled: Bool
  let medicationSyncEnabled: Bool
  let selectedMetricCount: Int
  let pairingCount: Int
  let registrationCount: Int
  let recentEventCount: Int
  let lastAttemptedAt: Date?
  let lastSuccessfulAt: Date?
  let failureCategories: [SyncFailureCategory]
}

enum DiagnosticsSummary {
  static func included(_ input: DiagnosticsSummaryInput) -> [DiagnosticsSummaryRow] {
    var rows = [
      DiagnosticsSummaryRow(label: "App version", value: input.appVersion),
      DiagnosticsSummaryRow(label: "Build", value: input.buildVersion),
      DiagnosticsSummaryRow(label: "iOS", value: input.osVersion),
      DiagnosticsSummaryRow(
        label: "Health Bridge integration",
        value: input.integrationVersion ?? "Not detected"
      ),
      DiagnosticsSummaryRow(label: "Live protocol", value: String(LiveRequest.protocolVersion)),
      DiagnosticsSummaryRow(
        label: "Historical protocol",
        value: String(BackfillRequest.protocolVersion)
      ),
      DiagnosticsSummaryRow(
        label: "Background sync",
        value: input.backgroundSyncEnabled ? "Enabled" : "Disabled"
      ),
      DiagnosticsSummaryRow(
        label: "Background interval",
        value: input.backgroundSyncFrequency.displayName
      ),
      DiagnosticsSummaryRow(
        label: "Historical import",
        value: input.historicalImportEnabled ? "Enabled" : "Disabled"
      ),
      DiagnosticsSummaryRow(
        label: "Medication sync",
        value: input.medicationSyncEnabled ? "Enabled" : "Disabled"
      ),
      DiagnosticsSummaryRow(label: "Selected metrics", value: String(input.selectedMetricCount)),
      DiagnosticsSummaryRow(label: "Entity pairings", value: String(input.pairingCount)),
      DiagnosticsSummaryRow(
        label: "Background registrations",
        value: String(input.registrationCount)
      ),
      DiagnosticsSummaryRow(label: "Recent events", value: String(input.recentEventCount)),
      DiagnosticsSummaryRow(
        label: "Last attempted sync",
        value: dateDescription(input.lastAttemptedAt)
      ),
      DiagnosticsSummaryRow(
        label: "Last successful sync",
        value: dateDescription(input.lastSuccessfulAt)
      ),
    ]

    let categories = Set(input.failureCategories.map(\.rawValue)).sorted()
    rows.append(
      DiagnosticsSummaryRow(
        label: "Failure categories",
        value: categories.isEmpty ? "None" : categories.joined(separator: ", ")
      )
    )
    return rows
  }

  private static func dateDescription(_ date: Date?) -> String {
    guard let date else { return "Never" }
    return date.formatted(date: .abbreviated, time: .shortened)
  }
}
