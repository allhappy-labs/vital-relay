import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      NavigationLink {
        HomeAssistantConnectionSettingsView()
      } label: {
        SettingsDestinationLabel(
          title: "Home Assistant Connection",
          subtitle: SettingsSummary.server(model.currentConfiguration),
          systemImage: "house.and.flag",
          accessibilityIdentifier: "settings-home-assistant-connection"
        )
      }
      .accessibilityIdentifier("settings-home-assistant-connection")
      .settingsDestinationSeparatorAlignment()

      NavigationLink {
        ExportSettingsView()
      } label: {
        SettingsDestinationLabel(
          title: "Export to Home Assistant",
          subtitle: SettingsSummary.export(
            selectedMetrics: model.selectedMetricCount,
            medicationEnabled: model.medicationSyncEnabled
          ),
          systemImage: "arrow.up.right.circle",
          accessibilityIdentifier: "settings-export-home-assistant"
        )
      }
      .accessibilityIdentifier("settings-export-home-assistant")
      .settingsDestinationSeparatorAlignment()

      NavigationLink {
        ImportSettingsView()
      } label: {
        SettingsDestinationLabel(
          title: "Import to Apple Health",
          subtitle: SettingsSummary.importSummary(pairingCount: model.pairings.count),
          systemImage: "arrow.down.left.circle",
          accessibilityIdentifier: "settings-import-apple-health"
        )
      }
      .accessibilityIdentifier("settings-import-apple-health")
      .settingsDestinationSeparatorAlignment()

      NavigationLink {
        AppPrivacySettingsView()
      } label: {
        SettingsDestinationLabel(
          title: "App & Privacy",
          subtitle: "Diagnostics and local app data",
          systemImage: "hand.raised",
          accessibilityIdentifier: "settings-app-privacy"
        )
      }
      .accessibilityIdentifier("settings-app-privacy")
      .settingsDestinationSeparatorAlignment()

      Button {
        showLifetimeUnlock = true
      } label: {
        SettingsDestinationLabel(
          title: "Lifetime Unlock",
          subtitle: model.lifetimeAccessState == .unlocked
            ? "Unlocked" : "Background, Shortcuts, and history",
          systemImage: "lock.open",
          accessibilityIdentifier: "settings-lifetime-unlock"
        )
      }
      .accessibilityIdentifier("settings-lifetime-unlock")
      .settingsDestinationSeparatorAlignment()
    }
    .navigationTitle("Settings")
    .sheet(isPresented: $showLifetimeUnlock) { LifetimeUnlockView() }
  }

  @State private var showLifetimeUnlock = false
}

private struct SettingsDestinationLabel: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let accessibilityIdentifier: String

  nonisolated static let iconColumnWidth: CGFloat = 52
  nonisolated static let iconCanvasSize: CGFloat = 36
  nonisolated static let columnSpacing: CGFloat = 16

  var body: some View {
    HStack(alignment: .center, spacing: Self.columnSpacing) {
      Image(systemName: systemImage)
        .resizable()
        .scaledToFit()
        .frame(width: Self.iconCanvasSize, height: Self.iconCanvasSize)
        .foregroundStyle(.tint)
        .frame(width: Self.iconColumnWidth, alignment: .center)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
          .accessibilityIdentifier("\(accessibilityIdentifier)-title")
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("\(accessibilityIdentifier)-subtitle")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 10)
  }
}

extension View {
  fileprivate func settingsDestinationSeparatorAlignment() -> some View {
    alignmentGuide(.listRowSeparatorLeading) { dimensions in
      dimensions[.leading] + SettingsDestinationLabel.iconColumnWidth
        + SettingsDestinationLabel.columnSpacing
    }
  }
}
