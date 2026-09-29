import SwiftUI

struct AppPrivacySettingsView: View {
  var body: some View {
    List {
      Section {
        NavigationLink("Diagnostics") {
          DiagnosticsView()
        }
        .accessibilityIdentifier("diagnostics-settings")

        NavigationLink("Data Management") {
          DataManagementView()
        }
        .accessibilityIdentifier("data-management-settings")
      } footer: {
        Text(
          "Health data is processed on this iPhone and sent directly to your configured Home Assistant instance."
        )
      }

      Section {
        Link(
          "Privacy Policy",
          destination: URL(string: "https://health-sync.olhapi.com/privacy")!
        )
        .accessibilityIdentifier("privacy-policy-link")
      }
    }
    .navigationTitle("App & Privacy")
  }
}
