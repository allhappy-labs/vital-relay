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
        Toggle(isOn: $isEnabled) {
          TileLabel(
            "Background Sync", systemImage: "arrow.triangle.2.circlepath", tint: .green)
        }
        .disabled(model.lifetimeAccessState != .unlocked)
        .accessibilityIdentifier("background-sync-toggle")
        .onChange(of: isEnabled) { _, enabled in
          guard loaded else { return }
          Task {
            await model.setBackgroundSyncEnabled(enabled)
            isEnabled = model.backgroundSyncEnabled
          }
        }
        Picker(selection: $frequency) {
          ForEach(BackgroundSyncFrequency.allCases, id: \.self) { option in
            Text(option.selectionLabel).tag(option)
          }
        } label: {
          TileLabel("Sync Interval", systemImage: "timer", tint: MetricCategory.activity.tint)
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
        InfoFooter(
          "The selected interval is a requested best-effort cadence.",
          details: "iOS decides when background work actually runs.",
          identifier: "background-frequency-explanation"
        )
      }
      if let blocker = BackgroundSyncBlocker.current(
        refresh: systemStatus.backgroundRefresh,
        isLowPowerModeEnabled: systemStatus.isLowPowerModeEnabled
      ) {
        Section {
          Label(blocker.message, systemImage: StatusTone.attention.symbol)
            .foregroundStyle(StatusTone.attention.color)
            .accessibilityIdentifier("background-sync-blocker")
          if blocker.offersSettings {
            Button("Open Settings") {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
              }
            }
            .accessibilityIdentifier("background-system-open-settings")
          }
        }
      }

      Section {
        LabeledContent {
          Text(lastAutomaticLabel)
        } label: {
          TileLabel("Last automatic sync", systemImage: "clock", tint: .blue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("background-system-last-automatic")
        NavigationLink {
          ShortcutsAutomationGuideView()
        } label: {
          TileLabel(
            "Sync more often with Shortcuts", systemImage: "square.2.layers.3d.fill",
            tint: .indigo)
        }
        .accessibilityIdentifier("background-shortcuts-guide")
        NavigationLink {
          SyncDetailsView()
        } label: {
          TileLabel("Sync Details", systemImage: "info.circle.fill", tint: .gray)
        }
        .accessibilityIdentifier("background-sync-details")
      } footer: {
        InfoFooter(
          "iOS decides when background sync runs.",
          details:
            "Apple Health can't be read while iPhone is locked; sync catches up after you unlock. If you swipe Vital Relay away in the app switcher, iOS stops background sync until you open it again."
        )
      }
    }
    .navigationTitle("Background Sync")
    .sheet(isPresented: $showLifetimeUnlock) { LifetimeUnlockView() }
    .task {
      isEnabled = model.backgroundSyncEnabled
      frequency = model.backgroundSyncFrequency
      loaded = true
      systemStatus.start()
      await model.refreshSyncStatus()
    }
    .onDisappear { systemStatus.stop() }
  }

  private var lastAutomaticLabel: String {
    guard let event = model.lastAutomaticEvent else { return "None yet" }
    let time = (event.startedAt ?? event.finishedAt).formatted(date: .omitted, time: .shortened)
    return
      "\(time) · \(RecentSyncEventFormatter.triggerTitle(event.trigger)) · \(RecentSyncEventFormatter.outcomeLabel(event))"
  }
}
