import SwiftUI

struct AppPrivacySettingsView: View {
  var body: some View {
    List {
      Section {
        NavigationLink {
          DiagnosticsView()
        } label: {
          TileLabel("Diagnostics", systemImage: "stethoscope", tint: .gray)
        }
        .accessibilityIdentifier("diagnostics-settings")

        NavigationLink {
          DataManagementView()
        } label: {
          TileLabel("Data Management", systemImage: "externaldrive.fill", tint: .gray)
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
