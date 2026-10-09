import HealthSyncCore
import SwiftUI

struct ImportSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section {
        NavigationLink {
          PairingListView()
        } label: {
          TileLabel(
            "Entity Pairings", systemImage: "arrow.left.arrow.right",
            tint: MetricCategory.vitals.tint)
        }
        .accessibilityIdentifier("health-import-pairings")
      } footer: {
        Text(
          "Imported samples are tagged so they are not exported back to Home Assistant."
        )
      }

      Section {
        Button("Review Write Permissions") {
          Task {
            await model.requestHealthWriteAuthorization(
              for: Set(model.pairings.map(\.destination))
            )
          }
        }
        .disabled(model.pairings.isEmpty)
        .accessibilityIdentifier("import-review-write-permissions")
      } header: {
        Text("Apple Health")
      } footer: {
        Text("Only destinations used by your pairings are requested.")
      }
    }
    .navigationTitle("Import to Apple Health")
  }
}
