import HealthSyncCore
import SwiftUI

struct OnboardingView: View {
  @Environment(AppModel.self) private var model

  @State private var path: [OnboardingRoute] = []
  @State private var selectedMetrics: Set<MetricID> = []

  var body: some View {
    NavigationStack(path: $path) {
      PrivacyStepView {
        path.append(.metrics)
      }
      .navigationDestination(for: OnboardingRoute.self) { route in
        switch route {
        case .metrics:
          MetricSelectionStepView(selection: $selectedMetrics) {
            Task {
              await model.requestHealthAuthorization(for: selectedMetrics)
              path.append(.connect(selectedMetrics))
            }
          }
        case .connect(let approvedMetrics):
          ConnectionStepView(selectedMetrics: approvedMetrics)
        }
      }
    }
  }
}

enum OnboardingRoute: Hashable {
  case metrics
  case connect(Set<MetricID>)
}

enum OnboardingNavigationPolicy {
  static func step(for route: OnboardingRoute?) -> Int {
    switch route {
    case nil: 1
    case .metrics: 2
    case .connect: 3
    }
  }

  static func previousRoute(from route: OnboardingRoute) -> OnboardingRoute? {
    switch route {
    case .metrics: nil
    case .connect: .metrics
    }
  }
}
