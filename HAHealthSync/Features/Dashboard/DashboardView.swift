import HealthSyncCore
import SwiftUI

struct DashboardView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    NavigationStack {
      List {
        previewSection
        syncSection
        categorySection

        if let currentError = model.currentError {
          Section("Current Issue") {
            Label(currentError.rawValue, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        }
      }
      .navigationTitle("Health Sync")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          NavigationLink {
            SettingsView()
          } label: {
            Label("Settings", systemImage: "gearshape")
          }
          .accessibilityIdentifier("settings-destination")
        }
      }
      .task {
        await model.refreshDashboardPreview()
      }
      .refreshable {
        await model.refreshDashboardPreview()
      }
      .overlay(alignment: .top) {
        if let feedback = model.manualSyncFeedback {
          syncToast(feedback)
        }
      }
      .animation(.snappy, value: model.manualSyncFeedback)
      // Held here rather than on the button: a List can recycle a scrolled-off row, which would
      // cancel the timer and leave the toast on screen for good.
      .task(id: model.manualSyncFeedback) {
        guard model.manualSyncFeedback != nil else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        model.clearManualSyncFeedback()
      }
    }
  }

  /// Confirms every successful manual sync, including one that found nothing to send: a run that
  /// returns in a tenth of a second with nothing to report is the case that looks like a failure.
  private func syncToast(_ feedback: ManualSyncFeedback) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Sync successful")
          .font(.subheadline.weight(.semibold))
        Text(feedback.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: .rect(cornerRadius: 14))
    .shadow(radius: 8, y: 2)
    .padding(.top, 8)
    .transition(.move(edge: .top).combined(with: .opacity))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("sync-toast")
    .accessibilityAddTraits(.isStaticText)
  }

  @ViewBuilder
  private var previewSection: some View {
    let dailyReadings = DashboardMetricFormatter.iPhoneDailyReadings(
      in: model.dashboardPreview
    )

    Section {
      if model.dashboardPreview.isLoading, model.dashboardPreview.readings.isEmpty {
        HStack {
          ProgressView()
          Text("Reading Apple Health…")
            .foregroundStyle(.secondary)
        }
      } else if dailyReadings.isEmpty {
        ContentUnavailableView(
          "No Daily Activity Yet",
          systemImage: "figure.walk",
          description: Text(
            "Daily steps, distance, and flights climbed appear when selected and available."
          )
        )
      } else {
        ForEach(dailyReadings, id: \.metricID) { reading in
          if reading.metricID == .steps {
            dailyStepsRow(reading)
          } else {
            dailyReadingRow(reading)
          }
        }
      }
    } header: {
      // Not a backlog: these are the values read from Apple Health, whether or not they have
      // been sent. Calling them "ready" read as a queue waiting to go out.
      Text("\(model.dashboardPreview.readyCount) values read from Apple Health")
        .accessibilityIdentifier("dashboard-summary")
    }
  }

  private func dailyStepsRow(_ reading: MetricReading) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent {
        Text(
          DashboardMetricFormatter.value(
            reading.value,
            unit: MetricRegistry[reading.metricID]?.bridgeUnit ?? .count
          )
        )
        .font(.headline)
      } label: {
        Label("Daily Steps", systemImage: "figure.walk")
      }
      Gauge(value: min(max(reading.value, 0), 10_000), in: 0...10_000) {
        EmptyView()
      }
      .tint(.green)
    }
    .accessibilityElement(children: .combine)
  }

  private func dailyReadingRow(_ reading: MetricReading) -> some View {
    let definition = MetricRegistry[reading.metricID]
    return LabeledContent {
      Text(
        DashboardMetricFormatter.value(
          reading.value,
          unit: definition?.bridgeUnit ?? .none
        )
      )
      .font(.headline)
    } label: {
      Label(
        definition?.displayName ?? reading.metricID.rawValue,
        systemImage: reading.metricID == .distance
          ? "point.bottomleft.forward.to.point.topright.scurvepath" : "stairs"
      )
    }
    .accessibilityElement(children: .combine)
  }

  private var syncSection: some View {
    Section {
      syncButton
      LabeledContent {
        if let lastSuccessfulSync = model.lastSuccessfulSync {
          Text(DashboardMetricFormatter.lastSync(lastSuccessfulSync))
        } else {
          Text("Never")
        }
      } label: {
        Text("Last sync")
      }
      .accessibilityIdentifier("last-sync")
      .listRowSeparator(.hidden, edges: .top)
    }
  }

  @ViewBuilder
  private var syncButton: some View {
    if #available(iOS 26.0, *) {
      syncButtonContent
        .buttonStyle(.glassProminent)
    } else {
      syncButtonContent
        .buttonStyle(.borderedProminent)
    }
  }

  private var syncButtonContent: some View {
    Button {
      Task {
        await model.syncNow()
        await model.refreshDashboardPreview()
      }
    } label: {
      ZStack {
        if model.isSyncing {
          ProgressView()
        } else {
          Text(model.manualSyncFeedback?.title ?? "Sync Now")
            .accessibilityIdentifier("sync-now-title")

          HStack {
            Image(
              systemName: model.manualSyncFeedback == nil
                ? "arrow.triangle.2.circlepath" : "checkmark"
            )
            .accessibilityHidden(true)
            Spacer()
          }
          .padding(.horizontal, 16)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .controlSize(.large)
    .disabled(model.isSyncing)
    .listRowSeparator(.hidden)
    .accessibilityIdentifier("sync-now")
    .accessibilityHint("Synchronizes both configured directions")
  }

  private var categorySection: some View {
    Section("Latest Data") {
      LabeledContent(
        "Activity",
        value: "\(model.dashboardPreview.readableCount(in: .activity))"
      )
      LabeledContent(
        "Vitals",
        value: "\(model.dashboardPreview.readableCount(in: .vitals))"
      )
      LabeledContent(
        "Sleep",
        value: "\(model.dashboardPreview.readableCount(in: .sleep))"
      )
      LabeledContent(
        "Body",
        value: "\(model.dashboardPreview.readableCount(in: .bodyMeasurements))"
      )
    }
    .accessibilityIdentifier("dashboard-category-counts")
  }
}
