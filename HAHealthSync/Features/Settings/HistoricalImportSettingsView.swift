import HealthSyncCore
import SwiftUI

enum ArchiveImportPresentation {
  static let privacyNotice =
    "Importing creates a long-lived copy of readable Apple Health samples in Home Assistant. Home Assistant administrators and backups may access it. Removing HealthKit access or local app data does not erase that copy."
  static let deletionHelp =
    "To delete the server archive, open the authenticated Health Bridge archive card in Home Assistant. An administrator must confirm archive deletion for this user. Recorder history, statistics, and backups remain separate."

  static func ownerDescription(state: ArchiveOwnerState?, fingerprint: String?) -> String {
    let suffix = fingerprint.map { " Fingerprint: \($0)." } ?? ""
    switch state {
    case .unbound:
      return
        "No archive uploader is approved. Request approval from a Home Assistant administrator.\(suffix)"
    case .pending:
      return
        "Archive uploader approval is pending. Match this fingerprint in Home Assistant.\(suffix)"
    case .active:
      return "This iPhone is the approved archive uploader.\(suffix)"
    case .notOwner:
      return
        "This iPhone's archive access was revoked. Request administrator approval to transfer ownership. Older originals remain archived.\(suffix)"
    case nil:
      return "Archive uploader status is unavailable."
    }
  }

  static func archiveStatus(_ report: ArchiveImportReport) -> String {
    if report.failures.contains(where: { $0.issue == .ownerChanged }) {
      return "Archive uploader changed; import paused"
    }
    if report.failures.contains(where: {
      $0.issue == .ownerPending || $0.issue == .ownerRequired
        || $0.issue == .checkpointOwnerMismatch
    }) {
      return "Archive uploader approval or rescan required"
    }
    let affected = report.failures.filter { recoveryGuidance($0) != nil }.map(affectedType)
    if !affected.isEmpty {
      return
        "Reconciliation required for \(Set(affected).sorted().joined(separator: ", ")); archive completion cannot be confirmed"
    }
    switch report.archiveState {
    case .idle: return "Not started"
    case .importing: return "Archiving samples"
    case .archived: return "Samples archived"
    case .paused: return "Paused; committed samples remain archived"
    case .failed: return "Archive import failed"
    }
  }

  static func recoveryGuidance(_ failure: ArchiveImportFailure) -> String? {
    let guidance: String
    switch failure.issue {
    case .reconciliationRequired:
      guidance =
        "Health history changed and deletion reconciliation is still required. Use Resume Import to retry."
    case .authorizationUnproven:
      guidance =
        "Readable Health access could not be verified. Review the selected Health access, then use Resume Import. This does not identify the permission state."
    case .inventoryTooDense:
      guidance =
        "This history exceeds the safe reconciliation limit. Keep local progress and ask your Home Assistant administrator to review importer and integration support before retrying."
    case .inventoryUnstable:
      guidance =
        "Health or archive history kept changing during reconciliation. Wait for other imports or edits to finish, then use Resume Import."
    case .ownerRequired:
      guidance =
        "This iPhone needs archive uploader approval in Home Assistant. Request approval here."
    case .ownerPending:
      guidance =
        "Archive uploader approval is pending in Home Assistant. Ask an administrator to review the claim fingerprint."
    case .ownerChanged:
      guidance =
        "This iPhone no longer owns the archive. Ask an administrator to approve a transfer before importing again."
    case .checkpointOwnerMismatch:
      guidance =
        "Saved archive work belongs to another iPhone or an older credential. Reset archive import here to rescan readable samples."
    default: return nil
    }
    if failure.issue == .ownerRequired || failure.issue == .ownerPending
      || failure.issue == .ownerChanged || failure.issue == .checkpointOwnerMismatch
    {
      return guidance
    }
    return "\(affectedType(failure)): \(guidance) Archive completion cannot be confirmed."
  }

  private static func affectedType(_ failure: ArchiveImportFailure) -> String {
    guard let type = failure.type else { return "Selected Health data" }
    let names = MetricRegistry.all.filter { $0.healthObjectType == type }.map(\.displayName)
    return names.isEmpty ? type.rawValue : names.joined(separator: ", ")
  }
}

struct HistoricalImportSettingsView: View {
  @Environment(AppModel.self) private var model

  @State private var isEnabled = false
  @State private var selection: Set<MetricID> = []
  @State private var requestedStart = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
  @State private var loaded = false
  @State private var showEnableConfirmation = false
  @State private var allReadableHistory = true
  @State private var showArchiveResetConfirmation = false
  @State private var showLifetimeUnlock = false

  var body: some View {
    Form {
      Section {
        if model.lifetimeAccessState != .unlocked {
          Button("Unlock Historical Import") { showLifetimeUnlock = true }
            .accessibilityIdentifier("historical-import-unlock")
          Text(
            "Historical import needs the lifetime unlock. Health permission, a compatible Health Bridge, and archive uploader approval are separate requirements."
          )
          .font(.footnote)
        }
        Text(
          model.isFullHistoryAvailable
            ? ArchiveImportPresentation.privacyNotice
            : "Experimental import supports only SQLite recorder schema 53, writes history-only statistics, and is limited to the latest 14 days. An incompatible Home Assistant setup disables historical import without affecting live sync."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("historical-import-warning")

        Toggle("Experimental Historical Import", isOn: historicalImportBinding)
          .disabled(model.lifetimeAccessState != .unlocked)
          .accessibilityIdentifier("historical-import-toggle")
      }

      Section("Compatibility") {
        HStack {
          Text("Health Bridge")
          Spacer()
          Text(capabilityDescription)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("historical-import-capability")
        }
        Text(model.archiveAvailabilityDescription)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("historical-import-archive-capability")
      }

      if model.isFullHistoryAvailable {
        Section("Archive uploader approval") {
          Text(
            ArchiveImportPresentation.ownerDescription(
              state: model.archiveCapability?.ownerState,
              fingerprint: model.archiveCapability?.fingerprint
                ?? model.archiveClaimStatus?.fingerprint
                ?? model.archiveUploaderFingerprintValue
            )
          )
          .accessibilityIdentifier("historical-import-owner-state")
          if let issue = model.archiveClaimFailure,
            issue != .checkpointOwnerMismatch,
            let guidance = ArchiveImportPresentation.recoveryGuidance(
              .init(category: .configuration, issue: issue))
          {
            Text(guidance)
              .foregroundStyle(.orange)
              .accessibilityIdentifier("historical-import-owner-guidance")
          }
          if model.archiveCapability?.ownerState == .unbound
            || model.archiveCapability?.ownerState == .notOwner
          {
            Button("Request Archive Approval") {
              Task { await model.requestArchiveOwnerClaim() }
            }
            .accessibilityIdentifier("historical-import-owner-claim")
          }
          Button("Refresh Approval Status") {
            Task { await model.refreshArchiveAvailability() }
          }
          .accessibilityIdentifier("historical-import-owner-refresh")
          if model.archiveClaimFailure == .checkpointOwnerMismatch {
            Text("Saved archive work cannot be resumed with this iPhone's credential.")
              .foregroundStyle(.orange)
            Button("Reset Archive Import and Rescan", role: .destructive) {
              showArchiveResetConfirmation = true
            }
            .accessibilityIdentifier("historical-import-safe-rescan")
          }
        }
      }

      if model.isFullHistoryAvailable {
        Section("History range") {
          Toggle("All readable history", isOn: $allReadableHistory)
            .accessibilityIdentifier("historical-import-all-readable")
          if !allReadableHistory {
            DatePicker(
              "Start date", selection: $requestedStart,
              in: archiveEarliestStart...Date.now, displayedComponents: [.date]
            )
          }
          Text(
            "Each metric begins at its own earliest readable sample. Limited Health access may make that date later."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      } else {
        Section("Import window") {
          DatePicker(
            "Start date",
            selection: $requestedStart,
            in: earliestStart...Date.now,
            displayedComponents: [.date]
          )
          Text("The integration enforces the 14-day limit, including a small clock-skew allowance.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        NavigationLink {
          HistoricalEligibleMetricsView(
            definitions: eligibleDefinitions,
            selection: $selection,
            discovery: model.isFullHistoryAvailable ? model.archiveDiscovery : nil
          )
        } label: {
          LabeledContent(
            "Eligible Metrics",
            value: "\(selection.count) of \(eligibleDefinitions.count)"
          )
        }
        .accessibilityIdentifier("historical-eligible-metrics")
        .accessibilityValue("\(selection.count) selected")
      } footer: {
        Text(
          model.isFullHistoryAvailable
            ? "Supported workouts and new Health Bridge metrics are included. Medication records use a separate opt-in."
            : "Workouts, timestamps, and medication sensors are not backfill eligible.")
      }

      Section {
        if model.isFullHistoryAvailable && model.isArchiveImportRunning {
          HStack {
            ProgressView()
            Text("Archiving readable samples…")
          }
          Button("Pause Import") {
            Task { await model.pauseArchiveImport() }
          }
          .accessibilityIdentifier("historical-import-pause")
        } else if model.isBackfillRunning {
          HStack {
            ProgressView()
            Text("Importing without retaining raw values…")
          }
          Button("Cancel Import", role: .destructive) {
            model.cancelHistoricalImport()
          }
          .accessibilityIdentifier("historical-import-cancel")
        } else {
          Button(
            model.isFullHistoryAvailable ? "Archive Readable History" : "Import Confirmed History"
          ) {
            Task {
              if model.isFullHistoryAvailable {
                await model.importReadableHistory(
                  metrics: selection,
                  requestedStart: allReadableHistory ? nil : requestedStart)
              } else {
                await model.importHistory(metrics: selection, requestedStart: requestedStart)
              }
            }
          }
          .disabled(!canImport)
          .accessibilityIdentifier("historical-import-start")
          if model.isFullHistoryAvailable,
            model.lastArchiveReport?.archiveState == .paused
          {
            Button("Resume Import") {
              Task { await model.resumeArchiveImport() }
            }
            .disabled(
              !isEnabled || !model.canArchiveHistory || model.lifetimeAccessState != .unlocked
            )
            .accessibilityIdentifier("historical-import-resume")
          }
        }
      }

      if model.isFullHistoryAvailable, let report = model.lastArchiveReport {
        Section("Archive progress") {
          LabeledContent("Archive", value: ArchiveImportPresentation.archiveStatus(report))
            .accessibilityIdentifier("historical-import-archive-status")
          LabeledContent("Samples archived", value: "\(report.archivedSamples)")
            .accessibilityIdentifier("historical-import-archived-samples")
          LabeledContent("Deletions archived", value: "\(report.archivedDeletions)")
          ForEach(eligibleDefinitions, id: \.id) { definition in
            if let state = report.projectionStates[definition.id] {
              LabeledContent(
                "\(definition.displayName) statistics",
                value: state == .current ? "Current" : state == .failed ? "Failed" : "Pending"
              )
              .accessibilityIdentifier(
                "historical-import-statistics-\(definition.id.rawValue)"
              )
            }
          }
          if !report.noReadableMetrics.isEmpty {
            Text(
              "No readable samples found for \(report.noReadableMetrics.count) selected metrics. This does not identify the Health permission state."
            )
            .accessibilityIdentifier("historical-import-no-readable")
          }
          ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
            if let guidance = ArchiveImportPresentation.recoveryGuidance(failure) {
              Text(guidance)
                .foregroundStyle(.orange)
                .accessibilityIdentifier(
                  failure.issue == .reconciliationRequired
                    ? "historical-import-reconciliation-required"
                    : "historical-import-recovery-\(failure.issue?.rawValue ?? "unknown")")
            }
          }
          Button("Refresh Statistics Status") {
            Task { await model.refreshArchiveProjection() }
          }
          .accessibilityIdentifier("historical-import-refresh-statistics")
        }
      } else if let report = model.lastBackfillReport {
        Section("Last import") {
          LabeledContent("Attempted metrics", value: "\(report.attemptedMetrics)")
          LabeledContent("Committed metrics", value: "\(report.committedMetrics)")
          LabeledContent(
            "Skipped (no eligible history)",
            value: "\(report.skippedMetrics)"
          )
          .accessibilityIdentifier("historical-import-skipped")
          LabeledContent("Committed points", value: "\(report.committedPoints)")
          LabeledContent("Failures", value: "\(report.failures.count)")
            .accessibilityIdentifier("historical-import-failures")
          if report.committedMetrics > 0 {
            Text(
              "Home Assistant confirmed that \(report.committedPoints) points were committed."
            )
            .foregroundStyle(.secondary)
          }
          if report.skippedMetrics > 0 {
            Text(
              "Skipped metrics did not have at least two eligible points in the import window."
            )
            .foregroundStyle(.secondary)
          }
        }
      }

      if model.isFullHistoryAvailable {
        Section("Archive privacy and deletion") {
          Text(ArchiveImportPresentation.privacyNotice)
            .accessibilityIdentifier("historical-import-privacy")
          Text(ArchiveImportPresentation.deletionHelp)
            .accessibilityIdentifier("historical-import-deletion-help")
          if let url = URL(string: model.currentConfiguration.baseURL) {
            Link("Open Home Assistant", destination: url)
              .accessibilityIdentifier("historical-import-open-home-assistant")
          }
        }
      }
    }
    .navigationTitle("Historical Import")
    .sheet(isPresented: $showLifetimeUnlock) { LifetimeUnlockView() }
    .confirmationDialog(
      "Reset Archive Import?", isPresented: $showArchiveResetConfirmation,
      titleVisibility: .visible
    ) {
      Button("Reset and Rescan", role: .destructive) {
        Task { await model.resetArchiveImportForThisPhone() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This removes the local pending archive upload and checkpoints. The next import scans samples readable on this iPhone. Home Assistant originals remain preserved."
      )
    }
    .alert("Enable Experimental Import?", isPresented: $showEnableConfirmation) {
      Button("Cancel", role: .cancel) {
        isEnabled = false
      }
      Button("Enable Experimental Import") {
        Task { await persistEnabled(true) }
      }
    } message: {
      Text(
        model.isFullHistoryAvailable
          ? ArchiveImportPresentation.privacyNotice
          : "This uses Home Assistant recorder internals that may change. Live synchronization remains separate."
      )
    }
    .task {
      guard !loaded else { return }
      isEnabled = model.experimentalBackfillEnabled
      selection = Set(eligibleDefinitions.map(\.id))
      loaded = true
      await model.refreshBackfillCapability()
      await model.refreshArchiveAvailability()
      selection = model.archiveSavedSelection?.metrics ?? Set(eligibleDefinitions.map(\.id))
      if let savedStart = model.archiveSavedSelection?.requestedStart {
        allReadableHistory = false
        requestedStart = savedStart
      }
    }
  }

  private var eligibleDefinitions: [MetricDefinition] {
    model.isFullHistoryAvailable
      ? model.archiveEligibleDefinitions
      : HistoricalMetricSelectionPolicy.eligibleDefinitions(
        selectedMetrics: model.currentConfiguration.selectedMetrics)
  }

  private var archiveEarliestStart: Date {
    model.archiveDiscovery?.metrics.values.compactMap {
      if case .readable(let date, _) = $0 { return date }
      return nil
    }.min() ?? earliestStart
  }

  private var earliestStart: Date {
    Date.now.addingTimeInterval(-14 * 24 * 60 * 60)
  }

  private var canImport: Bool {
    guard model.lifetimeAccessState == .unlocked, isEnabled, !selection.isEmpty,
      !model.isBackfillRunning,
      !model.isArchiveImportRunning
    else { return false }
    if model.isFullHistoryAvailable {
      guard model.canArchiveHistory else { return false }
      return selection.contains {
        if case .readable = model.archiveDiscovery?.metrics[$0] { return true }
        return false
      }
    }
    if case .incompatible = model.historicalImportCapability { return false }
    return true
  }

  private var historicalImportBinding: Binding<Bool> {
    Binding(
      get: { isEnabled },
      set: { enabled in
        if enabled, !model.experimentalBackfillEnabled {
          showEnableConfirmation = true
        } else if !enabled, model.experimentalBackfillEnabled {
          Task { await persistEnabled(false) }
        }
      }
    )
  }

  private var capabilityDescription: String {
    if model.isFullHistoryAvailable { return "Archive protocol 2 available" }
    return switch model.historicalImportCapability {
    case .disabledByUser:
      "Disabled"
    case .unprobed:
      "Not checked"
    case .available(let version):
      "Available (protocol \(version))"
    case .incompatible(let reason):
      "Incompatible: \(reason.rawValue)"
    case .temporarilyUnavailable:
      "Temporarily unavailable"
    }
  }

  private func persistEnabled(_ enabled: Bool) async {
    await model.setExperimentalBackfillEnabled(enabled)
    isEnabled = model.experimentalBackfillEnabled
  }
}
