import HealthSyncCore
import SwiftUI

enum HistoricalMetricSelectionPolicy {
  static func eligibleDefinitions(selectedMetrics: Set<MetricID>) -> [MetricDefinition] {
    MetricRegistry.backfillEligible.filter { selectedMetrics.contains($0.id) }
  }

  static func archiveEligibleDefinitions(
    selectedMetrics: Set<MetricID>, capability: ArchiveCapability
  ) -> [MetricDefinition] {
    MetricRegistry.selectable.filter {
      selectedMetrics.contains($0.id)
        && capability.supportedMetrics.contains($0.id.rawValue)
        && capability.supportedSampleTypes.contains($0.healthObjectType.rawValue)
    }
  }
}

struct HistoricalEligibleMetricsView: View {
  let definitions: [MetricDefinition]
  @Binding var selection: Set<MetricID>
  var discovery: ArchiveHistoryDiscovery?

  var body: some View {
    List {
      Section("Selection") {
        LabeledContent("Selected", value: "\(selection.count) of \(definitions.count)")
        Button("Select All", systemImage: "checkmark.circle") {
          selection = Set(definitions.map(\.id))
        }
        .disabled(selection.count == definitions.count)
        Button("Clear", systemImage: "xmark.circle") {
          selection.removeAll()
        }
        .disabled(selection.isEmpty)
      }

      ForEach(MetricCategory.allCases, id: \.self) { category in
        let categoryDefinitions = definitions.filter { $0.category == category }
        if !categoryDefinitions.isEmpty {
          Section(categoryTitle(category)) {
            ForEach(categoryDefinitions, id: \.id) { definition in
              Toggle(definition.displayName, isOn: binding(for: definition.id))
                .accessibilityIdentifier(
                  "historical-import-metric-\(definition.id.rawValue)"
                )
              if let history = discovery?.metrics[definition.id] {
                Text(Self.historyDescription(history))
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                  .accessibilityIdentifier(
                    "historical-import-earliest-\(definition.id.rawValue)"
                  )
              }
            }
          }
        }
      }
    }
    .navigationTitle("Eligible Metrics")
  }

  private func binding(for metricID: MetricID) -> Binding<Bool> {
    Binding(
      get: { selection.contains(metricID) },
      set: { selected in
        if selected {
          selection.insert(metricID)
        } else {
          selection.remove(metricID)
        }
      }
    )
  }

  private func categoryTitle(_ category: MetricCategory) -> String {
    switch category {
    case .activity: "Activity"
    case .bodyMeasurements: "Body Measurements"
    case .vitals: "Vitals"
    case .sleep: "Sleep"
    case .other: "Other"
    }
  }

  static func historyDescription(_ history: ReadableHistory) -> String {
    switch history {
    case .readable(let date, let boundary):
      let earliest = date.formatted(date: .abbreviated, time: .omitted)
      if boundary != nil { return "Earliest readable: \(earliest) (limited access)" }
      return "Earliest readable: \(earliest)"
    case .noReadableSamples:
      return "No readable samples found"
    }
  }
}
