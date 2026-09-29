import AppIntents
import SwiftUI

@main
struct HAHealthSyncApp: App {
  @State private var model = AppRuntime.makeAppModel()

  var body: some Scene {
    WindowGroup {
      Group {
        if model.isOnboardingComplete {
          DashboardView()
        } else {
          OnboardingView()
        }
      }
      .environment(model)
      .task {
        await model.load()
      }
    }
  }
}
