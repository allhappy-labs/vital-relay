import HealthSyncCore
import SwiftUI

struct ExportSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section("Data") {
        NavigationLink {
          MetricSelectionView()
        } label: {
          TileLabel(
            "Health Metrics", systemImage: "heart.text.square.fill",
            tint: MetricCategory.vitals.tint)
        }
        .accessibilityIdentifier("choose-health-metrics")

        if model.medicationSyncAvailable {
          NavigationLink {
            MedicationSelectionView()
          } label: {
            TileLabel(
              "Medications", systemImage: "pills.fill", tint: MetricCategory.bodyMeasurements.tint)
          }
          .accessibilityIdentifier("medication-sync-settings")
        }
      }

      Section("Automation") {
        NavigationLink {
          BackgroundSyncSettingsView()
        } label: {
          TileLabel("Background Sync", systemImage: "arrow.triangle.2.circlepath", tint: .green)
        }
        .accessibilityIdentifier("background-sync-settings")

        NavigationLink {
          HistoricalImportSettingsView()
        } label: {
          TileLabel(
            "Historical Import", systemImage: "clock.arrow.circlepath",
            tint: MetricCategory.sleep.tint)
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
