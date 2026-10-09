import HealthSyncCore
import SwiftUI

struct BackgroundMetricRegistrationsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      if selectedDefinitions.isEmpty {
        ContentUnavailableView(
          "No Selected Metrics",
          systemImage: "waveform.path.ecg",
          description: Text("Select Health metrics before enabling background sync.")
        )
      } else {
        ForEach(selectedDefinitions, id: \.id) { definition in
          LabeledContent {
            Text(registrationDescription(for: definition.id))
              .foregroundStyle(registrationTone(for: definition.id)?.color ?? .secondary)
          } label: {
            TileLabel(
              definition.displayName, systemImage: definition.category.symbol,
              tint: definition.category.tint)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("background-registration-\(definition.id.rawValue)")
        }
      }
    }
    .navigationTitle("Metric Registrations")
    .accessibilityIdentifier("background-registration-list")
  }

  private var selectedDefinitions: [MetricDefinition] {
    MetricRegistry.selectable.filter {
      model.currentConfiguration.selectedMetrics.contains($0.id)
    }
  }

  private func registrationTone(for metric: MetricID) -> StatusTone? {
    switch model.syncStatus.registrations[metric] {
    case .registered: .synced
    case .failed: .failed
    case .unavailable: .attention
    case .disabled, .none: nil
    }
  }

  private func registrationDescription(for metric: MetricID) -> String {
    switch model.syncStatus.registrations[metric] {
    case .registered:
      "Registered"
    case .failed(let category, _):
      "Failed: \(category.rawValue)"
    case .unavailable:
      "Unavailable"
    case .disabled, .none:
      "Disabled"
    }
  }
}
