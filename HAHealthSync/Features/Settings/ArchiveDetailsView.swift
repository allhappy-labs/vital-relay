import HealthSyncCore
import SwiftUI

/// Technical archive state kept off the main Historical Import screen.
struct ArchiveDetailsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section("Health Bridge") {
        LabeledContent {
          Text("Archive protocol 2 available")
            .foregroundStyle(StatusTone.synced.color)
            .accessibilityIdentifier("historical-import-capability")
        } label: {
          TileLabel("Compatibility", systemImage: "server.rack", tint: .blue)
        }
        Text(model.archiveAvailabilityDescription)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("historical-import-archive-capability")
      }

      Section("Archive uploader") {
        Text(
          ArchiveImportPresentation.ownerDescription(
            state: model.archiveCapability?.ownerState,
            fingerprint: model.archiveCapability?.fingerprint
              ?? model.archiveClaimStatus?.fingerprint
              ?? model.archiveUploaderFingerprintValue
          )
        )
        .accessibilityIdentifier("historical-import-owner-state")
        Button("Refresh Approval Status") {
          Task { await model.refreshArchiveAvailability() }
        }
        .accessibilityIdentifier("historical-import-owner-refresh")
      }

      if let report = model.lastArchiveReport {
        Section("Archive") {
          LabeledContent("Status", value: ArchiveImportPresentation.archiveStatus(report))
            .accessibilityIdentifier("historical-import-archive-status")
          LabeledContent("Deletions archived", value: "\(report.archivedDeletions)")
          ForEach(model.archiveEligibleDefinitions, id: \.id) { definition in
            if let state = report.projectionStates[definition.id] {
              LabeledContent(
                "\(definition.displayName) statistics",
                value: state == .current ? "Current" : state == .failed ? "Failed" : "Pending"
              )
              .accessibilityIdentifier("historical-import-statistics-\(definition.id.rawValue)")
            }
          }
          if !report.noReadableMetrics.isEmpty {
            Text(
              "No readable samples found for \(report.noReadableMetrics.count) selected metrics. This does not identify the Health permission state."
            )
            .accessibilityIdentifier("historical-import-no-readable")
          }
          Button("Refresh Statistics Status") {
            Task { await model.refreshArchiveProjection() }
          }
          .accessibilityIdentifier("historical-import-refresh-statistics")
        }
      }

      Section("Privacy and deletion") {
        Text(ArchiveImportPresentation.privacyNotice)
          .accessibilityIdentifier("historical-import-privacy")
        Text(ArchiveImportPresentation.deletionHelp)
          .accessibilityIdentifier("historical-import-deletion-help")
        if let url = URL(string: model.currentConfiguration.baseURL) {
          Link("Open Home Assistant", destination: url)
            .accessibilityIdentifier("historical-import-open-home-assistant")
        }
      }
    }
    .navigationTitle("Archive Details")
  }
}
