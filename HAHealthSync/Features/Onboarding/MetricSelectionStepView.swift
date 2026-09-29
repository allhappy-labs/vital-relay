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
          .foregroundStyle(.secondary)
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

  @ViewBuilder
  private var bottomAction: some View {
    if #available(iOS 26.0, *) {
      actionButton
        .buttonStyle(.glassProminent)
        .padding()
    } else {
      actionButton
        .buttonStyle(.borderedProminent)
        .padding()
        .background(.bar)
    }
  }

  private var actionButton: some View {
    Button("Request Health Access", action: continueAction)
      .controlSize(.large)
      .frame(maxWidth: .infinity)
      .disabled(selection.isEmpty)
      .accessibilityIdentifier("request-health-access")
      .accessibilityHint("Requests read access only for the selected health types")
  }
}
