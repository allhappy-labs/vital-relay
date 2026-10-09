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
    let affected = report.failures.filter {
      switch $0.issue {
      case .reconciliationRequired, .authorizationUnproven, .inventoryTooDense,
        .inventoryUnstable:
        true
      default:
        false
      }
    }.map(affectedType)
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
    case nil:
      return
        "\(affectedType(failure)): Import paused (\(failure.category.rawValue)). Committed samples remain archived; use Resume Import to retry."
    default: return nil
    }
    if failure.issue == .ownerRequired || failure.issue == .ownerPending
      || failure.issue == .ownerChanged || failure.issue == .checkpointOwnerMismatch
    {
      return guidance
    }
    return "\(affectedType(failure)): \(guidance) Archive completion cannot be confirmed."
  }

  static func typeName(_ type: HealthObjectTypeID, selected: Set<MetricID>) -> String {
    let names = MetricRegistry.all
      .filter { $0.healthObjectType == type && selected.contains($0.id) }
      .map(\.displayName)
    if names.isEmpty { return type.rawValue }
    // Sleep alone can select nine metrics; listing them all makes an unreadable row.
    if names.count > 2 { return "\(typeCategory(type).title) (\(names.count) metrics)" }
    return names.joined(separator: ", ")
  }

  static func typeCategory(_ type: HealthObjectTypeID) -> MetricCategory {
    MetricRegistry.all.first { $0.healthObjectType == type }?.category ?? .other
  }

  static func percent(_ fraction: Double) -> String {
    "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
  }

  private static func affectedType(_ failure: ArchiveImportFailure) -> String {
    guard let type = failure.type else { return "Selected Health data" }
    let names = MetricRegistry.all.filter { $0.healthObjectType == type }.map(\.displayName)
    return names.isEmpty ? type.rawValue : names.joined(separator: ", ")
  }
}

/// The progress card's text. Pure, so every state is unit-tested.
struct ArchiveProgressSummary: Equatable {
  let headline: String
  let caption: String?
  let fraction: Double?

  /// The highest overall fraction seen in the current run. Only live reports count: when a new
  /// run starts, the screen still holds the previous run's finished or paused report.
  static func nextFloor(current: Double?, report: ArchiveImportReport?, isRunning: Bool)
    -> Double?
  {
    guard isRunning, let report, report.archiveState == .importing, report.phase != .idle,
      let fraction = report.overallFraction
    else { return current }
    return max(current ?? 0, fraction)
  }

  /// `floor` is the highest overall fraction shown so far in this run. `now` advances during a
  /// run, so a type's range grows and its fraction can dip slightly; the card never goes back.
  static func make(
    report: ArchiveImportReport?, isRunning: Bool, selected: Set<MetricID>, now: Date,
    floor: Double?
  ) -> ArchiveProgressSummary {
    guard let report else {
      return .init(
        headline: "Not started", caption: "Choose metrics below, then start.", fraction: nil)
    }
    let overall = report.overallFraction.map { max($0, isRunning ? floor ?? 0 : 0) }
    let percent = overall.map { " · " + ArchiveImportPresentation.percent($0) } ?? ""
    if isRunning || report.archiveState == .importing {
      switch report.phase {
      case .waiting(let until):
        let seconds = Int(until.timeIntervalSince(now).rounded(.up))
        return .init(
          headline: seconds > 0
            ? "Waiting for Home Assistant · resumes in \(seconds) s"
            : "Waiting for Home Assistant · resuming…",
          caption: "Home Assistant limits uploads per minute. Nothing is lost.",
          fraction: overall)
      case .archiving(let type):
        return .init(
          headline: "Archiving" + percent,
          caption: "Now: " + ArchiveImportPresentation.typeName(type, selected: selected),
          fraction: overall)
      case .checking(let type):
        return .init(
          headline: "Archiving" + percent,
          caption: "Checking "
            + ArchiveImportPresentation.typeName(type, selected: selected) + " for changes",
          fraction: overall)
      case .preparing, .idle:
        return .init(headline: "Archiving" + percent, caption: "Preparing…", fraction: overall)
      }
    }
    if report.archiveState == .archived {
      return .init(headline: "Archive complete", caption: nil, fraction: overall ?? 1)
    }
    return .init(headline: "Paused" + percent, caption: nil, fraction: overall)
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
  @State private var progressFloor: Double?

  var body: some View {
    Form {
      if model.lifetimeAccessState != .unlocked {
        Section {
          Button("Unlock Historical Import") { showLifetimeUnlock = true }
            .accessibilityIdentifier("historical-import-unlock")
          Text(
            "Historical import needs the lifetime unlock. Health permission, a compatible Health Bridge, and archive uploader approval are separate requirements."
          )
          .font(.footnote)
        }
      }
      if model.isFullHistoryAvailable {
        archiveSections
      } else {
        legacySections
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

  @ViewBuilder
  private var archiveSections: some View {
    let report = model.lastArchiveReport

    Section {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let live = ArchiveProgressSummary.make(
          report: report, isRunning: model.isArchiveImportRunning, selected: selection,
          now: context.date, floor: progressFloor)
        VStack(alignment: .leading, spacing: 10) {
          Text(live.headline)
            .font(.headline)
            .accessibilityIdentifier("historical-import-progress-headline")
          if let caption = live.caption {
            Text(caption)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          if let fraction = live.fraction {
            ProgressView(value: fraction)
              .tint(MetricCategory.sleep.tint)
          }
          if let report {
            Text("\(report.archivedSamples.formatted()) samples archived")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("historical-import-archived-samples")
          }
        }
        .padding(.vertical, 4)
      }
      archiveActions
    }
    .onChange(of: model.lastArchiveReport) { _, report in
      progressFloor = ArchiveProgressSummary.nextFloor(
        current: progressFloor, report: report, isRunning: model.isArchiveImportRunning)
    }
    .onChange(of: model.isArchiveImportRunning) { _, running in
      if running { progressFloor = nil }
    }

    if let report, !report.typeProgress.isEmpty {
      Section("Progress") {
        ForEach(
          report.typeProgress.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self
        ) { type in
          typeRow(type, progress: report.typeProgress[type]!, phase: report.phase)
        }
      }
    }

    let guidance = (report?.failures ?? []).compactMap { failure in
      ArchiveImportPresentation.recoveryGuidance(failure).map { (failure, $0) }
    }
    if !guidance.isEmpty {
      Section("Needs attention") {
        ForEach(Array(guidance.enumerated()), id: \.offset) { _, item in
          Label(item.1, systemImage: StatusTone.attention.symbol)
            .foregroundStyle(StatusTone.attention.color)
            .accessibilityIdentifier(
              item.0.issue == .reconciliationRequired
                ? "historical-import-reconciliation-required"
                : "historical-import-recovery-\(item.0.issue?.rawValue ?? "unknown")")
        }
      }
    }

    if model.archiveCapability?.ownerState != .active
      || model.archiveClaimFailure != nil
    {
      approvalSection
    }

    Section {
      Toggle(isOn: historicalImportBinding) {
        TileLabel(
          "Historical Import", systemImage: "clock.arrow.circlepath",
          tint: MetricCategory.sleep.tint)
      }
      .disabled(model.lifetimeAccessState != .unlocked)
      .accessibilityIdentifier("historical-import-toggle")
      Toggle(isOn: $allReadableHistory) {
        TileLabel("All readable history", systemImage: "infinity", tint: .blue)
      }
      .accessibilityIdentifier("historical-import-all-readable")
      if !allReadableHistory {
        DatePicker(
          "Start date", selection: $requestedStart,
          in: archiveEarliestStart...Date.now, displayedComponents: [.date])
      }
      NavigationLink {
        HistoricalEligibleMetricsView(
          definitions: eligibleDefinitions, selection: $selection,
          discovery: model.archiveDiscovery)
      } label: {
        LabeledContent {
          Text("\(selection.count) of \(eligibleDefinitions.count)")
        } label: {
          TileLabel(
            "Eligible Metrics", systemImage: "checklist", tint: MetricCategory.activity.tint)
        }
      }
      .accessibilityIdentifier("historical-eligible-metrics")
      .accessibilityValue("\(selection.count) selected")
    } header: {
      Text("Setup")
    } footer: {
      InfoFooter(
        "Importing creates a long-lived copy of readable Apple Health samples in Home Assistant.",
        details:
          "Home Assistant administrators and backups may access it. Removing HealthKit access or local app data does not erase that copy. Each metric begins at its own earliest readable sample; limited Health access may make that date later. Supported workouts and new Health Bridge metrics are included. Medication records use a separate opt-in."
      )
    }

    Section {
      NavigationLink {
        ArchiveDetailsView()
      } label: {
        TileLabel("Archive Details", systemImage: "info.circle.fill", tint: .gray)
      }
      .accessibilityIdentifier("historical-import-archive-details")
    }
  }

  @ViewBuilder
  private var archiveActions: some View {
    if model.isArchiveImportRunning {
      Button {
        Task { await model.pauseArchiveImport() }
      } label: {
        Text("Pause Import").frame(maxWidth: .infinity)
      }
      .accessibilityIdentifier("historical-import-pause")
    } else {
      Button {
        Task {
          await model.importReadableHistory(
            metrics: selection, requestedStart: allReadableHistory ? nil : requestedStart)
        }
      } label: {
        Text("Archive Readable History").frame(maxWidth: .infinity)
      }
      .primaryActionStyle()
      .disabled(!canImport)
      .accessibilityIdentifier("historical-import-start")
      if model.lastArchiveReport?.archiveState == .paused {
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

  private func typeRow(
    _ type: HealthObjectTypeID, progress: ArchiveTypeProgress, phase: ArchiveImportPhase
  ) -> some View {
    let category = ArchiveImportPresentation.typeCategory(type)
    let isCurrent = phase == .archiving(type) || phase == .checking(type)
    return LabeledContent {
      if progress.range == nil {
        Text("No readable data").foregroundStyle(.secondary)
      } else if progress.isComplete {
        Image(systemName: StatusTone.synced.symbol)
          .foregroundStyle(StatusTone.synced.color)
          .accessibilityLabel("Done")
      } else {
        HStack(spacing: 8) {
          ProgressView(value: progress.fraction)
            .frame(width: 56)
            .tint(category.tint)
          Text(ArchiveImportPresentation.percent(progress.fraction))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
    } label: {
      TileLabel(
        ArchiveImportPresentation.typeName(type, selected: selection),
        subtitle: progress.range.map {
          "Since " + $0.start.formatted(date: .abbreviated, time: .omitted)
        },
        systemImage: category.symbol, tint: category.tint
      )
      .fontWeight(isCurrent ? .semibold : nil)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("historical-import-type-\(type.rawValue)")
  }

  @ViewBuilder
  private var approvalSection: some View {
    Section("Approve this iPhone in Home Assistant") {
      Text(
        ArchiveImportPresentation.ownerDescription(
          state: model.archiveCapability?.ownerState,
          fingerprint: model.archiveCapability?.fingerprint
            ?? model.archiveClaimStatus?.fingerprint
            ?? model.archiveUploaderFingerprintValue
        )
      )
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

  @ViewBuilder
  private var legacySections: some View {
    Section {
      Text(
        "Experimental import supports only SQLite recorder schema 53, writes history-only statistics, and is limited to the latest 14 days. An incompatible Home Assistant setup disables historical import without affecting live sync."
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

    Section {
      NavigationLink {
        HistoricalEligibleMetricsView(
          definitions: eligibleDefinitions, selection: $selection, discovery: nil)
      } label: {
        LabeledContent(
          "Eligible Metrics",
          value: "\(selection.count) of \(eligibleDefinitions.count)"
        )
      }
      .accessibilityIdentifier("historical-eligible-metrics")
      .accessibilityValue("\(selection.count) selected")
    } footer: {
      Text("Workouts, timestamps, and medication sensors are not backfill eligible.")
    }

    Section {
      if model.isBackfillRunning {
        HStack {
          ProgressView()
          Text("Importing without retaining raw values…")
        }
        Button("Cancel Import", role: .destructive) {
          model.cancelHistoricalImport()
        }
        .accessibilityIdentifier("historical-import-cancel")
      } else {
        Button("Import Confirmed History") {
          Task { await model.importHistory(metrics: selection, requestedStart: requestedStart) }
        }
        .disabled(!canImport)
        .accessibilityIdentifier("historical-import-start")
      }
    }

    if let report = model.lastBackfillReport {
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
