import HealthSyncCore
import SwiftUI

struct MetricSelectionView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var selection: Set<MetricID> = []
  @State private var query = ""
  @State private var loaded = false
  @State private var isSaving = false

  var body: some View {
    List {
      Section("Selection") {
        LabeledContent("Selected", value: "\(selection.count)")
          .accessibilityIdentifier("metric-selection-count")
      }

      MetricSelectionSections(
        selection: $selection,
        definitions: MetricSelectionPolicy.filteredDefinitions(
          query: query,
          osMajorVersion: currentOSMajorVersion
        )
      )

      Section {
        Button {
          isSaving = true
          Task {
            await model.updateSelectedMetrics(selection)
            isSaving = false
            if model.currentError == nil {
              dismiss()
            }
          }
        } label: {
          HStack {
            Spacer()
            if isSaving {
              ProgressView()
            } else {
              Text("Save Metric Selection")
            }
            Spacer()
          }
        }
        .disabled(selection.isEmpty || isSaving)
        .accessibilityIdentifier("save-metric-selection")
      } footer: {
        Text("Only newly selected HealthKit types require another permission request.")
      }

      if model.medicationSyncAvailable {
        Section {
          Text("Medications use separate per-medication authorization in Settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Health Metrics")
    .searchable(text: $query, prompt: "Search metrics")
    .task {
      guard !loaded else { return }
      selection = model.currentConfiguration.selectedMetrics
      loaded = true
    }
  }

  private var currentOSMajorVersion: Int {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion
  }
}

struct MetricSelectionSections: View {
  @Binding var selection: Set<MetricID>
  var definitions: [MetricDefinition]

  var body: some View {
    Section("All Metrics") {
      Button("Select All", systemImage: "checkmark.circle") {
        MetricSelectionPolicy.turnAllOn(
          selection: &selection,
          osMajorVersion: currentOSMajorVersion
        )
      }
      .disabled(availableMetricIDs.isSubset(of: selection))
      .accessibilityIdentifier("turn-all-metrics-on")

      Button("Clear", systemImage: "xmark.circle") {
        MetricSelectionPolicy.turnAllOff(selection: &selection)
      }
      .disabled(selection.isEmpty)
      .accessibilityIdentifier("turn-all-metrics-off")
    }

    ForEach(MetricCategory.allCases, id: \.self) { category in
      Section {
        ForEach(definitions(in: category), id: \.id) { definition in
          Toggle(definition.displayName, isOn: binding(for: definition.id))
            .accessibilityIdentifier("metric-\(definition.id.rawValue)")
        }
      } header: {
        Text(title(for: category))
          .accessibilityIdentifier("metric-category-\(category.rawValue)")
      }
    }
  }

  private func definitions(in category: MetricCategory) -> [MetricDefinition] {
    definitions.filter { $0.category == category }
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

  private var currentOSMajorVersion: Int {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion
  }

  private var availableMetricIDs: Set<MetricID> {
    MetricSelectionPolicy.availableMetricIDs(osMajorVersion: currentOSMajorVersion)
  }

  private func title(for category: MetricCategory) -> String {
    switch category {
    case .activity: "Activity"
    case .bodyMeasurements: "Body Measurements"
    case .vitals: "Vitals"
    case .sleep: "Sleep"
    case .other: "Other"
    }
  }
}

enum MetricSelectionPolicy {
  static func availableMetricIDs(
    osMajorVersion: Int,
    isTypeAvailable: (HealthObjectTypeID) -> Bool = runtimeTypeIsAvailable
  ) -> Set<MetricID> {
    Set(
      MetricRegistry.selectable
        .filter {
          osMajorVersion >= $0.minimumIOSMajorVersion
            && isTypeAvailable($0.healthObjectType)
        }
        .map(\.id)
    )
  }

  static func turnAllOn(
    selection: inout Set<MetricID>,
    osMajorVersion: Int,
    isTypeAvailable: (HealthObjectTypeID) -> Bool = runtimeTypeIsAvailable
  ) {
    selection.formUnion(
      availableMetricIDs(osMajorVersion: osMajorVersion, isTypeAvailable: isTypeAvailable)
    )
  }

  static func turnAllOff(selection: inout Set<MetricID>) {
    selection.removeAll()
  }

  static func filteredDefinitions(
    query: String,
    osMajorVersion: Int,
    isTypeAvailable: (HealthObjectTypeID) -> Bool = runtimeTypeIsAvailable
  ) -> [MetricDefinition] {
    let available = MetricRegistry.selectable.filter {
      osMajorVersion >= $0.minimumIOSMajorVersion
        && isTypeAvailable($0.healthObjectType)
    }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return available }
    return available.filter {
      $0.displayName.localizedCaseInsensitiveContains(trimmed)
    }
  }

  static func onboardingDefinitions(
    osMajorVersion: Int,
    isTypeAvailable: (HealthObjectTypeID) -> Bool = runtimeTypeIsAvailable
  ) -> [MetricDefinition] {
    filteredDefinitions(
      query: "",
      osMajorVersion: osMajorVersion,
      isTypeAvailable: isTypeAvailable
    )
  }

  private static func runtimeTypeIsAvailable(_ type: HealthObjectTypeID) -> Bool {
    (try? HealthKitTypeResolver.objectType(for: type)) != nil
  }
}
