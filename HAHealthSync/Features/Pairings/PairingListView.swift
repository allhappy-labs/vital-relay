import HealthSyncCore
import SwiftUI

struct PairingListView: View {
  @Environment(AppModel.self) private var model
  @State private var pendingDeletion: Pairing?
  @State private var pendingUVCandidates: [UVEntityCandidate] = []
  @State private var uvPresetError: String?
  @State private var uvExposureToggleValue = false

  var body: some View {
    List {
      Section {
        Toggle("UV Exposure", isOn: $uvExposureToggleValue)
          .disabled(model.isUpdatingUVExposureImport)
          .accessibilityIdentifier("uv-exposure-import-toggle")
          .onChange(of: uvExposureToggleValue) { _, enabled in
            guard enabled != model.uvExposureImportEnabled else { return }
            Task { await updateUVExposureImport(enabled) }
          }

        if model.isUpdatingUVExposureImport {
          HStack {
            ProgressView()
            Text("Finding UV sensors…")
              .foregroundStyle(.secondary)
          }
          .accessibilityIdentifier("uv-exposure-import-progress")
        }

        if let source = model.pairings.first(where: { $0.destination == .uvExposure }) {
          LabeledContent("Home Assistant source", value: source.entityID)
            .font(.footnote)
            .accessibilityIdentifier("uv-exposure-import-source")
        }

        if let uvPresetError {
          Label(uvPresetError, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.red)
            .accessibilityIdentifier("uv-exposure-import-error")
        }
      } header: {
        Text("Quick setup")
      } footer: {
        Text(
          "Finds a numeric current UV-index sensor, asks for Apple Health write access, and remembers the selected entity."
        )
      }

      Section("Pairings") {
        if model.pairings.isEmpty {
          ContentUnavailableView(
            "No Pairings",
            systemImage: "arrow.left.arrow.right",
            description: Text("Add a numeric Home Assistant entity to import it into Apple Health.")
          )
        } else {
          ForEach(model.pairings) { pairing in
            NavigationLink {
              PairingEditorView(pairing: pairing)
            } label: {
              PairingRow(pairing: pairing)
            }
            .accessibilityIdentifier("pairing-\(pairing.entityID)")
            .swipeActions {
              Button("Delete", role: .destructive) {
                pendingDeletion = pairing
              }
            }
          }
        }
      }

      Section("Health permission") {
        Button("Review Write Permissions") {
          Task {
            await model.requestHealthWriteAuthorization(
              for: Set(model.pairings.map(\.destination))
            )
          }
        }
        .disabled(model.pairings.isEmpty)
        .accessibilityIdentifier("review-health-write-permissions")
        Text("Only destinations used by your pairings are requested.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Entity Pairings")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        NavigationLink {
          PairingEditorView(pairing: nil)
        } label: {
          Label("Add Pairing", systemImage: "plus")
        }
        .accessibilityIdentifier("add-pairing")
      }
    }
    .confirmationDialog(
      "Delete this pairing?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Delete Pairing", role: .destructive) {
        guard let pairing = pendingDeletion else { return }
        pendingDeletion = nil
        Task { await model.deletePairing(id: pairing.id) }
      }
      Button("Cancel", role: .cancel) {
        pendingDeletion = nil
      }
    } message: {
      Text("The pairing and its duplicate-prevention checkpoint will be removed.")
    }
    .confirmationDialog(
      "Choose a UV sensor",
      isPresented: Binding(
        get: { !pendingUVCandidates.isEmpty },
        set: { if !$0 { pendingUVCandidates = [] } }
      ),
      titleVisibility: .visible
    ) {
      ForEach(pendingUVCandidates) { candidate in
        Button("\(candidate.displayName) — \(candidate.entityID)") {
          pendingUVCandidates = []
          Task {
            let result = await model.setUVExposureImportEnabled(
              true,
              selectedEntityID: candidate.entityID
            )
            handleUVPresetResult(result)
            uvExposureToggleValue = model.uvExposureImportEnabled
          }
        }
      }
      Button("Cancel", role: .cancel) {
        pendingUVCandidates = []
      }
    } message: {
      Text("More than one compatible current UV-index sensor was found.")
    }
    .task {
      await model.reloadPairings()
      uvExposureToggleValue = model.uvExposureImportEnabled
    }
  }

  private func updateUVExposureImport(_ enabled: Bool) async {
    uvPresetError = nil
    let result = await model.setUVExposureImportEnabled(enabled)
    handleUVPresetResult(result)
    uvExposureToggleValue = model.uvExposureImportEnabled
  }

  private func handleUVPresetResult(_ result: UVPresetEnableResult) {
    switch result {
    case .enabled, .disabled:
      uvPresetError = nil
    case .selectionRequired(let candidates):
      pendingUVCandidates = candidates
      uvExposureToggleValue = false
    case .noCandidates:
      uvPresetError =
        "No numeric current UV-index sensor was found in Home Assistant. Add one, then try again."
    case .failed(let category):
      uvPresetError = "UV Exposure could not be enabled (\(category.rawValue))."
    }
  }
}

private struct PairingRow: View {
  let pairing: Pairing

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(destinationName)
      Text(pairing.entityID)
        .font(.caption)
        .foregroundStyle(.secondary)
      Label(pairing.isEnabled ? "Enabled" : "Disabled", systemImage: statusSymbol)
        .font(.caption)
        .foregroundStyle(pairing.isEnabled ? .green : .secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private var destinationName: String {
    WritableHealthRegistry[pairing.destination]?.displayName ?? "Unavailable destination"
  }

  private var statusSymbol: String {
    pairing.isEnabled ? "checkmark.circle.fill" : "pause.circle"
  }
}
