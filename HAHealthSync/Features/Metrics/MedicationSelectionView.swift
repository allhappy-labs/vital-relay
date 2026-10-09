import HealthSyncCore
import SwiftUI

struct MedicationSelectionView: View {
  @Environment(AppModel.self) private var model

  @State private var authorizedMedications: [MedicationConcept] = []
  @State private var didRequestAuthorization = false
  @State private var isRequestingAuthorization = false
  @State private var isEnabled = false
  @State private var loaded = false

  var body: some View {
    Form {
      Section {
        Text(
          "On iOS 26 or newer, Apple shows a per-medication authorization sheet. Only medications you approve are read."
        )
        Text(
          "Read-only: Vital Relay cannot create medications or dose events. Authorized dose status is sent directly to your Home Assistant Health Bridge webhook."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("medication-read-only-explanation")

        Button {
          Task { await requestAccess() }
        } label: {
          if isRequestingAuthorization {
            ProgressView()
          } else {
            Text("Choose Medications in Apple Health")
          }
        }
        .disabled(isRequestingAuthorization)
        .accessibilityIdentifier("request-medication-access")
      }

      if didRequestAuthorization {
        Section("Authorized medications") {
          if authorizedMedications.isEmpty {
            Text("No medications were authorized.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(authorizedMedications, id: \.id) { medication in
              Label {
                Text(medication.name ?? "Authorized medication")
              } icon: {
                IconTile(systemImage: "pill.fill", tint: MetricCategory.bodyMeasurements.tint)
              }
            }
          }
        }
      }

      Section {
        Toggle(isOn: medicationSyncBinding) {
          TileLabel(
            "Sync Authorized Medications", systemImage: "pills.fill",
            tint: MetricCategory.bodyMeasurements.tint)
        }
        .disabled(!didRequestAuthorization && !isEnabled)
        .accessibilityIdentifier("medication-sync-toggle")
      } footer: {
        Text(
          "Medication sync is independent from numeric metric selection and Home Assistant → Apple Health pairings."
        )
      }
    }
    .navigationTitle("Medications")
    .task {
      guard !loaded else { return }
      isEnabled = model.medicationSyncEnabled
      loaded = true
    }
    .onDisappear {
      authorizedMedications.removeAll()
    }
  }

  private func requestAccess() async {
    isRequestingAuthorization = true
    defer { isRequestingAuthorization = false }
    authorizedMedications = await model.requestMedicationAuthorization()
    didRequestAuthorization = model.currentError == nil
  }

  private var medicationSyncBinding: Binding<Bool> {
    Binding(
      get: { isEnabled },
      set: { enabled in
        isEnabled = enabled
        Task {
          await model.setMedicationSyncEnabled(enabled)
          isEnabled = model.medicationSyncEnabled
        }
      }
    )
  }
}
