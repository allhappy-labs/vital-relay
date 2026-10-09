import HealthSyncCore
import SwiftUI

/// Troubleshooting detail for background sync, kept off the main Background Sync screen.
struct SyncDetailsView: View {
  @Environment(AppModel.self) private var model
  @State private var systemStatus = BackgroundSystemStatus()
  @State private var publishAttempts = false
  @State private var publishMessage: String?
  @State private var loaded = false

  var body: some View {
    List {
      Section("System") {
        LabeledContent {
          Text(backgroundRefreshLabel)
            .foregroundStyle(
              systemStatus.backgroundRefresh == .available
                ? Color.secondary : StatusTone.attention.color)
        } label: {
          TileLabel("Background App Refresh", systemImage: "arrow.clockwise.icloud", tint: .gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("background-system-refresh")
        LabeledContent {
          Text(systemStatus.isLowPowerModeEnabled ? "On" : "Off")
            .foregroundStyle(
              systemStatus.isLowPowerModeEnabled ? StatusTone.attention.color : Color.secondary)
        } label: {
          TileLabel("Low Power Mode", systemImage: "battery.25", tint: .yellow)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("background-system-low-power")
        LabeledContent {
          Text(earliestNextLabel)
        } label: {
          TileLabel(
            "Earliest next automatic sync", systemImage: "calendar.badge.clock", tint: .blue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("background-system-earliest-next")
        LabeledContent {
          Text(formatted(model.lastFullSweepAt))
        } label: {
          TileLabel("Last full sweep", systemImage: "checklist", tint: .blue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("background-system-last-sweep")
      }

      Section("Status") {
        LabeledContent(
          "Last attempt",
          value: formatted(model.syncStatus.lastAttemptedAt)
        )
        LabeledContent(
          "Last success",
          value: formatted(model.syncStatus.lastSuccessfulAt)
        )
        LabeledContent("Last failure") {
          Text(model.syncStatus.lastFailure?.category.rawValue ?? "None")
            .foregroundStyle(
              model.syncStatus.lastFailure == nil ? Color.secondary : StatusTone.failed.color)
        }
      }

      Section("Diagnostics") {
        NavigationLink {
          BackgroundMetricRegistrationsView()
        } label: {
          LabeledContent {
            Text("\(registeredMetricCount) of \(selectedDefinitions.count)")
          } label: {
            TileLabel(
              "Metric Registrations", systemImage: "waveform.path.ecg",
              tint: MetricCategory.vitals.tint)
          }
        }
        .accessibilityIdentifier("background-metric-registrations")

        NavigationLink {
          RecentSyncEventsView(events: model.syncStatus.recentEvents)
        } label: {
          LabeledContent {
            Text("\(model.syncStatus.recentEvents.count)")
          } label: {
            TileLabel("Recent Sync Events", systemImage: "list.bullet.rectangle", tint: .gray)
          }
        }
        .accessibilityIdentifier("background-recent-events")
      }

      Section {
        Toggle(isOn: $publishAttempts) {
          TileLabel(
            "Publish sync attempts to Home Assistant", systemImage: "dot.radiowaves.up.forward",
            tint: .blue)
        }
        .accessibilityIdentifier("background-publish-attempts-toggle")
        .onChange(of: publishAttempts) { _, enabled in
          guard loaded, enabled != model.publishSyncAttempts else { return }
          Task {
            let result = await model.setPublishSyncAttempts(enabled)
            publishMessage = message(for: result)
            publishAttempts = model.publishSyncAttempts
          }
        }
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            "Publishing adds a sensor that updates on every attempt, including ones with nothing new. Requires an administrator token."
          )
          if let publishMessage {
            Text(publishMessage)
              .foregroundStyle(.red)
              .accessibilityIdentifier("background-publish-attempts-message")
          }
        }
      }
    }
    .navigationTitle("Sync Details")
    .task {
      publishAttempts = model.publishSyncAttempts
      loaded = true
      systemStatus.start()
      await model.refreshSyncStatus()
    }
    .onDisappear { systemStatus.stop() }
  }

  private var selectedDefinitions: [MetricDefinition] {
    MetricRegistry.selectable.filter {
      model.currentConfiguration.selectedMetrics.contains($0.id)
    }
  }

  private func formatted(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
  }

  private var registeredMetricCount: Int {
    selectedDefinitions.reduce(into: 0) { count, definition in
      if case .registered = model.syncStatus.registrations[definition.id] {
        count += 1
      }
    }
  }

  private var backgroundRefreshLabel: String {
    switch systemStatus.backgroundRefresh {
    case .available: "On"
    case .denied: "Off"
    case .restricted: "Restricted"
    }
  }

  private var earliestNextLabel: String {
    guard model.backgroundSyncEnabled else { return "Background sync off" }
    guard let date = model.earliestNextAutomaticSync else {
      return "After your next Apple Health update"
    }
    if date <= Date().addingTimeInterval(60) { return "Any time now" }
    return "Not before \(date.formatted(date: .omitted, time: .shortened))"
  }

  private func message(for result: PublishSyncAttemptsResult) -> String? {
    switch result {
    case .enabled, .disabled: nil
    case .requiresAdministrator: "Needs a long-lived token from a Home Assistant administrator."
    case .failed(let category): "Couldn't reach Home Assistant (\(category.rawValue))."
    }
  }
}
