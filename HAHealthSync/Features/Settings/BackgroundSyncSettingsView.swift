import HealthSyncCore
import SwiftUI
import UIKit

struct BackgroundSyncSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  @State private var isEnabled = false
  @State private var frequency = BackgroundSyncFrequency.balanced
  @State private var loaded = false
  @State private var systemStatus = BackgroundSystemStatus()
  @State private var publishAttempts = false
  @State private var publishMessage: String?
  @State private var showLifetimeUnlock = false

  var body: some View {
    List {
      Section {
        if model.lifetimeAccessState != .unlocked {
          Button("Unlock Background Sync") { showLifetimeUnlock = true }
            .accessibilityIdentifier("background-unlock")
          Text("Background sync needs the lifetime unlock. Sync Now remains free.")
            .font(.footnote)
        }
        Toggle("Background Sync", isOn: $isEnabled)
          .disabled(model.lifetimeAccessState != .unlocked)
          .accessibilityIdentifier("background-sync-toggle")
          .onChange(of: isEnabled) { _, enabled in
            guard loaded else { return }
            Task {
              await model.setBackgroundSyncEnabled(enabled)
              isEnabled = model.backgroundSyncEnabled
            }
          }
        Picker("Sync Interval", selection: $frequency) {
          ForEach(BackgroundSyncFrequency.allCases, id: \.self) { option in
            Text(option.selectionLabel).tag(option)
          }
        }
        .pickerStyle(.menu)
        .disabled(!isEnabled || model.lifetimeAccessState != .unlocked)
        .accessibilityIdentifier("background-sync-frequency-picker")
        .onChange(of: frequency) { _, selectedFrequency in
          guard loaded else { return }
          Task {
            await model.setBackgroundSyncFrequency(selectedFrequency)
            frequency = model.backgroundSyncFrequency
          }
        }
      } footer: {
        Text(
          "The selected interval is a requested best-effort cadence. iOS decides when background work actually runs."
        )
        .accessibilityIdentifier("background-frequency-explanation")
      }

      Section {
        LabeledContent("Background App Refresh", value: backgroundRefreshLabel)
          .accessibilityIdentifier("background-system-refresh")
        if systemStatus.backgroundRefresh == .denied {
          Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
              openURL(url)
            }
          }
          .accessibilityIdentifier("background-system-open-settings")
        }
        LabeledContent("Low Power Mode", value: systemStatus.isLowPowerModeEnabled ? "On" : "Off")
          .accessibilityIdentifier("background-system-low-power")
        LabeledContent("Earliest next automatic sync", value: earliestNextLabel)
          .accessibilityIdentifier("background-system-earliest-next")
        LabeledContent("Last automatic attempt", value: lastAutomaticLabel)
          .accessibilityIdentifier("background-system-last-automatic")
        LabeledContent("Last full sweep", value: formatted(model.lastFullSweepAt))
          .accessibilityIdentifier("background-system-last-sweep")
        Toggle("Publish sync attempts to Home Assistant", isOn: $publishAttempts)
          .accessibilityIdentifier("background-publish-attempts-toggle")
          .onChange(of: publishAttempts) { _, enabled in
            guard loaded, enabled != model.publishSyncAttempts else { return }
            Task {
              let result = await model.setPublishSyncAttempts(enabled)
              publishMessage = message(for: result)
              publishAttempts = model.publishSyncAttempts
            }
          }
        NavigationLink {
          ShortcutsAutomationGuideView()
        } label: {
          Text("Sync more often with Shortcuts")
        }
        .accessibilityIdentifier("background-shortcuts-guide")
      } header: {
        Text("System")
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          if systemStatus.isLowPowerModeEnabled {
            Text("iOS pauses background refresh in Low Power Mode.")
          }
          Text(
            "iOS decides when background sync runs. Apple Health can't be read while iPhone is locked; sync catches up after you unlock. If you swipe HA Health Sync away in the app switcher, iOS stops background sync until you open it again."
          )
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

      Section("Status") {
        LabeledContent(
          "Last attempt",
          value: formatted(model.syncStatus.lastAttemptedAt)
        )
        LabeledContent(
          "Last success",
          value: formatted(model.syncStatus.lastSuccessfulAt)
        )
        LabeledContent(
          "Last failure",
          value: model.syncStatus.lastFailure?.category.rawValue ?? "None"
        )
      }

      Section("Details") {
        NavigationLink {
          BackgroundMetricRegistrationsView()
        } label: {
          LabeledContent(
            "Metric Registrations",
            value: "\(registeredMetricCount) of \(selectedDefinitions.count)"
          )
        }
        .accessibilityIdentifier("background-metric-registrations")

        NavigationLink {
          RecentSyncEventsView(events: model.syncStatus.recentEvents)
        } label: {
          LabeledContent(
            "Recent Sync Events",
            value: "\(model.syncStatus.recentEvents.count)"
          )
        }
        .accessibilityIdentifier("background-recent-events")
      }
    }
    .navigationTitle("Background Sync")
    .sheet(isPresented: $showLifetimeUnlock) { LifetimeUnlockView() }
    .task {
      isEnabled = model.backgroundSyncEnabled
      frequency = model.backgroundSyncFrequency
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

  private var lastAutomaticLabel: String {
    guard let event = model.lastAutomaticEvent else { return "None yet" }
    let time = (event.startedAt ?? event.finishedAt).formatted(date: .omitted, time: .shortened)
    return
      "\(time) · \(RecentSyncEventFormatter.triggerTitle(event.trigger)) · \(RecentSyncEventFormatter.outcomeLabel(event))"
  }

  private func message(for result: PublishSyncAttemptsResult) -> String? {
    switch result {
    case .enabled, .disabled: nil
    case .requiresAdministrator: "Needs a long-lived token from a Home Assistant administrator."
    case .failed(let category): "Couldn't reach Home Assistant (\(category.rawValue))."
    }
  }
}
