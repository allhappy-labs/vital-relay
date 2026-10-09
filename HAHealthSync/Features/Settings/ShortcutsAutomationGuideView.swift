import SwiftUI

struct ShortcutsAutomationGuideView: View {
  @Environment(\.openURL) private var openURL
  @Environment(AppModel.self) private var model
  @State private var showLifetimeUnlock = false

  private let steps = [
    "Open Shortcuts, then Automation, then New Automation.",
    "Choose Time of Day, pick a time, and choose Daily.",
    "Add the action “Sync Health with Home Assistant”.",
    "Choose Run Immediately and turn off Notify When Run.",
    "Repeat for each hour you want. Shortcuts also can't read Apple Health while iPhone is locked.",
  ]

  var body: some View {
    List {
      if model.lifetimeAccessState != .unlocked {
        Section {
          Text("Shortcuts-triggered sync needs the lifetime unlock. In-app Sync Now remains free.")
          Button("View Lifetime Unlock") { showLifetimeUnlock = true }
            .accessibilityIdentifier("shortcuts-guide-unlock")
        }
      }
      Section {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
          Label {
            Text(step)
          } icon: {
            Text("\(index + 1)")
              .font(.subheadline.weight(.bold).monospacedDigit())
              .foregroundStyle(.white)
              .frame(width: 26, height: 26)
              .background(Color.indigo, in: .circle)
          }
        }
      } footer: {
        InfoFooter(
          "Automations run the same sync as Sync Now.",
          details: "They are a supplement to background sync, which iOS schedules on its own."
        )
      }

      Section {
        Button {
          if let url = URL(string: "shortcuts://") {
            openURL(url)
          }
        } label: {
          Text("Open Shortcuts")
            .frame(maxWidth: .infinity)
        }
        .primaryActionStyle()
        .accessibilityIdentifier("shortcuts-guide-open")
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }
    }
    .navigationTitle("Sync with Shortcuts")
    .sheet(isPresented: $showLifetimeUnlock) { LifetimeUnlockView() }
  }
}
