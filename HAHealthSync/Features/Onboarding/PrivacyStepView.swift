import HealthSyncCore
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
          .font(.system(size: 56))
          .foregroundStyle(MetricCategory.vitals.tint.gradient)
          .accessibilityHidden(true)

        Text("Your health data stays under your control")
          .font(.largeTitle.bold())

        Text(
          "Health Sync processes data on this iPhone and sends it directly to your own Home Assistant instance. There are no accounts, analytics, advertisements, cloud storage, or external servers."
        )

        Label {
          Text("Credentials are stored in the iOS Keychain")
        } icon: {
          IconTile(systemImage: "key.fill", tint: .gray)
        }
        Label {
          Text("Only health types you select are requested")
        } icon: {
          IconTile(systemImage: "checkmark.shield.fill", tint: .green)
        }
        Label {
          Text("Health values are excluded from app logs")
        } icon: {
          IconTile(systemImage: "eye.slash.fill", tint: .blue)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .safeAreaInset(edge: .bottom) {
      bottomAction
    }
    .navigationTitle("Privacy")
  }

  private var bottomAction: some View {
    actionButton.primaryActionBar()
  }

  private var actionButton: some View {
    Button(action: continueAction) {
      Text("Continue")
        .frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier("privacy-continue")
    .accessibilityHint("Continues to Apple Health metric selection")
  }
}
