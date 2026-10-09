import SwiftUI

struct DataManagementView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section {
        NavigationLink {
          ResetSynchronizationStateReviewView()
        } label: {
          TileLabel(
            "Reset Synchronization State", systemImage: "arrow.counterclockwise",
            tint: StatusTone.attention.color)
        }
        .accessibilityIdentifier("reset-sync-state-destination")

        NavigationLink {
          DeleteAllLocalDataReviewView()
        } label: {
          TileLabel(
            "Delete All Local App Data", systemImage: "trash.fill", tint: StatusTone.failed.color)
        }
        .accessibilityIdentifier("delete-all-data-destination")
      } footer: {
        Text(
          "Both actions clear local archive progress, but leave archived health samples in Home Assistant."
        )
      }

      Section("Server archive") {
        Text(ArchiveImportPresentation.deletionHelp)
          .accessibilityIdentifier("data-management-archive-deletion-help")
        if let url = URL(string: model.currentConfiguration.baseURL) {
          Link("Open Home Assistant", destination: url)
            .accessibilityIdentifier("data-management-open-home-assistant")
        }
      }
    }
    .navigationTitle("Data Management")
  }
}
