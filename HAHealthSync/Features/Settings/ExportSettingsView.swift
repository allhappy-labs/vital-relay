import SwiftUI

struct ExportSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section("Data") {
        NavigationLink("Health Metrics") {
          MetricSelectionView()
        }
        .accessibilityIdentifier("choose-health-metrics")

        if model.medicationSyncAvailable {
          NavigationLink("Medications") {
            MedicationSelectionView()
          }
          .accessibilityIdentifier("medication-sync-settings")
        }
      }

      Section("Automation") {
        NavigationLink("Background Sync") {
          BackgroundSyncSettingsView()
        }
        .accessibilityIdentifier("background-sync-settings")

        NavigationLink("Historical Import") {
          HistoricalImportSettingsView()
        }
        .accessibilityIdentifier("historical-import-settings")
      }

      Section("Apple Health") {
        Button("Review Read Permissions") {
          Task {
            await model.requestHealthAuthorization(
              for: model.currentConfiguration.selectedMetrics
            )
          }
        }
        .disabled(model.currentConfiguration.selectedMetrics.isEmpty)
        .accessibilityIdentifier("export-review-read-permissions")
      }
    }
    .navigationTitle("Export to Home Assistant")
  }
}
