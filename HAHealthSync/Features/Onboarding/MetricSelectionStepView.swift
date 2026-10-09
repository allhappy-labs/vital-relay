import HealthSyncCore
import SwiftUI

struct MetricSelectionStepView: View {
  @Binding var selection: Set<MetricID>
  let continueAction: () -> Void

  var body: some View {
    List {
      Section {
        Text("Step 2 of 3")
          .font(.headline)
          .foregroundStyle(MetricCategory.vitals.tint)
      }

      MetricSelectionSections(
        selection: $selection,
        definitions: MetricSelectionPolicy.onboardingDefinitions(
          osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
      )

      Section {
        Text("Apple Health to Home Assistant")
          .font(.headline)
        Text("iOS will ask only for the selected HealthKit read permissions.")
      }

    }
    .navigationTitle("Choose Metrics")
    .safeAreaInset(edge: .bottom) {
      bottomAction
    }
  }

  private var bottomAction: some View {
    actionButton.primaryActionBar()
  }

  private var actionButton: some View {
    Button(action: continueAction) {
      Text("Request Health Access")
        .frame(maxWidth: .infinity)
    }
    .disabled(selection.isEmpty)
    .accessibilityIdentifier("request-health-access")
    .accessibilityHint("Requests read access only for the selected health types")
  }
}
