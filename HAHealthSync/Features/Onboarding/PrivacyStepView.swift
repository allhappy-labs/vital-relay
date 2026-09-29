import SwiftUI

struct PrivacyStepView: View {
  let continueAction: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Step 1 of 3")
          .font(.headline)
          .foregroundStyle(.secondary)

        Image(systemName: "heart.text.clipboard")
          .font(.system(size: 52))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        Text("Your health data stays under your control")
          .font(.largeTitle.bold())

        Text(
          "HA Health Sync processes data on this iPhone and sends it directly to your own Home Assistant instance. There are no accounts, analytics, advertisements, cloud storage, or external servers."
        )

        Label("Credentials are stored in the iOS Keychain", systemImage: "key.fill")
        Label("Only health types you select are requested", systemImage: "checkmark.shield.fill")
        Label("Health values are excluded from app logs", systemImage: "eye.slash.fill")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .safeAreaInset(edge: .bottom) {
      bottomAction
    }
    .navigationTitle("Privacy")
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
    Button("Continue", action: continueAction)
      .controlSize(.large)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("privacy-continue")
      .accessibilityHint("Continues to Apple Health metric selection")
  }
}
