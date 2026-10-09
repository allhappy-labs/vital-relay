import HealthSyncCore
import SwiftUI

enum DashboardLayout {
  static func columnCount(isAccessibilitySize: Bool) -> Int {
    isAccessibilitySize ? 1 : 2
  }
}

struct DashboardView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var columns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: 12),
      count: DashboardLayout.columnCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          SyncStatusCard(
            summary: SyncStatusSummary.make(
              isSyncing: model.isSyncing,
              currentError: model.currentError,
              lastSuccessfulSync: model.lastSuccessfulSync
            )
          ) {
            syncButton
          }
          todaySection
          categorySection
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("Vital Relay")
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
      // Held here rather than on the button so a re-render cannot cancel the timer and leave
      // the toast on screen for good.
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

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.title3.weight(.semibold))
  }

  @ViewBuilder
  private var todaySection: some View {
    let dailyReadings = DashboardMetricFormatter.iPhoneDailyReadings(in: model.dashboardPreview)
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("Today")
      // Not a backlog: these are the values read from Apple Health, whether or not they have
      // been sent. Calling them "ready" read as a queue waiting to go out.
      Text("\(model.dashboardPreview.readyCount) values read from Apple Health")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("dashboard-summary")

      if model.dashboardPreview.isLoading, model.dashboardPreview.readings.isEmpty {
        HStack {
          ProgressView()
          Text("Reading Apple Health…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
      } else if dailyReadings.isEmpty {
        ContentUnavailableView(
          "No Daily Activity Yet",
          systemImage: "figure.walk",
          description: Text(
            "Daily steps, distance, and flights climbed appear when selected and available."
          )
        )
        .background(
          Color(uiColor: .secondarySystemGroupedBackground),
          in: .rect(cornerRadius: DesignTokens.cardCornerRadius)
        )
      } else {
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(dailyReadings, id: \.metricID) { reading in
            dailyTile(reading)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func dailyTile(_ reading: MetricReading) -> some View {
    let definition = MetricRegistry[reading.metricID]
    let value = DashboardMetricFormatter.value(
      reading.value,
      unit: definition?.bridgeUnit ?? .none
    )
    let tint = MetricCategory.activity.tint
    switch reading.metricID {
    case .steps:
      MetricTile(
        title: "Daily Steps", value: value, tint: tint, symbol: "figure.walk",
        valueDescription: StepGoal.percentText(reading.value)
      ) {
        GoalRing(progress: StepGoal.progress(reading.value), tint: tint)
      }
    case .distance:
      MetricTile(
        title: definition?.displayName ?? reading.metricID.rawValue,
        value: value,
        tint: tint,
        symbol: "point.bottomleft.forward.to.point.topright.scurvepath"
      )
    default:
      MetricTile(
        title: definition?.displayName ?? reading.metricID.rawValue,
        value: value,
        tint: tint,
        symbol: "stairs"
      )
    }
  }

  private var categorySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("Latest Data")
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach([MetricCategory.activity, .vitals, .sleep, .bodyMeasurements], id: \.self) {
          category in
          MetricTile(
            // "Body" keeps the existing dashboard label; selection lists use the full title.
            title: category == .bodyMeasurements ? "Body" : category.title,
            value: DashboardMetricFormatter.valueCount(
              model.dashboardPreview.readableCount(in: category)
            ),
            tint: category.tint,
            symbol: category.symbol
          )
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard-category-counts")
  }

  private var syncButton: some View {
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

          // The leading icon collides with the centred title at accessibility text sizes.
          if !dynamicTypeSize.isAccessibilitySize {
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
      }
      .frame(maxWidth: .infinity)
    }
    .primaryActionStyle()
    .disabled(model.isSyncing)
    .accessibilityIdentifier("sync-now")
    .accessibilityHint("Synchronizes both configured directions")
  }
}
