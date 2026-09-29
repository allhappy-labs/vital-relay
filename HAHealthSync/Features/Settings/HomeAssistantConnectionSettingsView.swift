import SwiftUI

struct HomeAssistantConnectionSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section("Connection") {
        LabeledContent(
          "Status",
          value: SettingsSummary.connectionStatus(model.currentConfiguration)
        )
        LabeledContent(
          "Server",
          value: SettingsSummary.server(model.currentConfiguration)
        )
      }

      Section {
        NavigationLink("Edit Connection") {
          ConnectionStepView(
            selectedMetrics: model.currentConfiguration.selectedMetrics,
            mode: .settings
          )
        }
        .accessibilityIdentifier("edit-home-assistant-connection")
      } footer: {
        Text("Credentials are stored separately in the iOS Keychain.")
      }
    }
    .navigationTitle("Home Assistant Connection")
  }
}
