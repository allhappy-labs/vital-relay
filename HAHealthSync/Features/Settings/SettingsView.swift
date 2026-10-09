import HealthSyncCore
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      NavigationLink {
        HomeAssistantConnectionSettingsView()
      } label: {
        TileLabel(
          "Home Assistant Connection",
          subtitle: SettingsSummary.server(model.currentConfiguration),
          systemImage: "house.fill",
          tint: .blue,
          identifier: "settings-home-assistant-connection"
        )
      }
      .accessibilityIdentifier("settings-home-assistant-connection")

      NavigationLink {
        ExportSettingsView()
      } label: {
        TileLabel(
          "Export to Home Assistant",
          subtitle: SettingsSummary.export(
            selectedMetrics: model.selectedMetricCount,
            medicationEnabled: model.medicationSyncEnabled
          ),
          systemImage: "arrow.up.right",
          tint: MetricCategory.activity.tint,
          identifier: "settings-export-home-assistant"
        )
      }
      .accessibilityIdentifier("settings-export-home-assistant")

      NavigationLink {
        ImportSettingsView()
      } label: {
        TileLabel(
          "Import to Apple Health",
          subtitle: SettingsSummary.importSummary(pairingCount: model.pairings.count),
          systemImage: "arrow.down.left",
          tint: MetricCategory.vitals.tint,
          identifier: "settings-import-apple-health"
        )
      }
      .accessibilityIdentifier("settings-import-apple-health")

      NavigationLink {
        AppPrivacySettingsView()
      } label: {
        TileLabel(
          "App & Privacy",
          subtitle: "Diagnostics and local app data",
          systemImage: "hand.raised.fill",
          tint: .gray,
          identifier: "settings-app-privacy"
        )
      }
      .accessibilityIdentifier("settings-app-privacy")

      Button {
        showLifetimeUnlock = true
      } label: {
        TileLabel(
          "Lifetime Unlock",
          subtitle: model.lifetimeAccessState == .unlocked
            ? "Unlocked" : "Background, Shortcuts, and history",
          systemImage: model.lifetimeAccessState == .unlocked ? "checkmark.seal.fill" : "lock.fill",
          tint: .yellow,
          identifier: "settings-lifetime-unlock"
        )
        .foregroundStyle(.primary)
      }
      // Rows here read as destinations; keep this one from turning accent blue like a link.
      .tint(.primary)
      .accessibilityIdentifier("settings-lifetime-unlock")
    }
    .navigationTitle("Settings")
    .sheet(isPresented: $showLifetimeUnlock) { LifetimeUnlockView() }
  }

  @State private var showLifetimeUnlock = false
}
