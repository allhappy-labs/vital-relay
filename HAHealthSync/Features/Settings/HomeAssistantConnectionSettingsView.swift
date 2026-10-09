import SwiftUI

struct HomeAssistantConnectionSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section("Connection") {
        LabeledContent {
          Text(SettingsSummary.connectionStatus(model.currentConfiguration))
        } label: {
          TileLabel("Status", systemImage: "antenna.radiowaves.left.and.right", tint: .green)
        }
        .accessibilityElement(children: .combine)
        LabeledContent {
          Text(SettingsSummary.server(model.currentConfiguration))
        } label: {
          TileLabel("Server", systemImage: "server.rack", tint: .blue)
        }
        .accessibilityElement(children: .combine)
      }

      Section {
        NavigationLink {
          ConnectionStepView(
            selectedMetrics: model.currentConfiguration.selectedMetrics,
            mode: .settings
          )
        } label: {
          TileLabel("Edit Connection", systemImage: "pencil", tint: .gray)
        }
        .accessibilityIdentifier("edit-home-assistant-connection")
      } footer: {
        Text("Credentials are stored separately in the iOS Keychain.")
      }
    }
    .navigationTitle("Home Assistant Connection")
  }
}
