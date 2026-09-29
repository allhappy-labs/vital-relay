import SwiftUI

struct ImportSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section {
        NavigationLink("Entity Pairings") {
          PairingListView()
        }
        .accessibilityIdentifier("health-import-pairings")
      } footer: {
        Text(
          "Imported samples are tagged so they are not exported back to Home Assistant."
        )
      }

      Section("Apple Health") {
        Button("Review Write Permissions") {
          Task {
            await model.requestHealthWriteAuthorization(
              for: Set(model.pairings.map(\.destination))
            )
          }
        }
        .disabled(model.pairings.isEmpty)
        .accessibilityIdentifier("import-review-write-permissions")
      }
    }
    .navigationTitle("Import to Apple Health")
  }
}
