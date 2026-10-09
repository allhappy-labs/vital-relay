import HealthSyncCore
import SwiftUI

struct LifetimeUnlockPresentation {
  let state: PaidAccessState
  let displayPrice: String?
  var isDeveloperAccess = false

  var offersRetry: Bool { !isDeveloperAccess && state == .unavailable && displayPrice == nil }

  let freeFeatures = ["Sync Now", "Home Assistant connection", "Metric and pairing selection"]
  let paidFeatures = [
    "Background sync", "Shortcuts sync", "Historical import",
    "Original-sample archive (iOS 27)",
  ]

  var purchaseTitle: String? {
    guard !isDeveloperAccess, state == .locked, let displayPrice else { return nil }
    return "Unlock for \(displayPrice)"
  }

  var status: String {
    if isDeveloperAccess { return "Developer access on this build (not an App Store purchase)." }
    return switch state {
    case .checking: "Checking purchases…"
    case .unlocked: "Lifetime access unlocked."
    case .locked: "Lifetime access is locked."
    case .unavailable:
      "The App Store is unavailable. Try again later or restore a previous purchase."
    }
  }

  static func message(for outcome: PurchaseOutcome) -> String? {
    switch outcome {
    case .purchased: nil
    case .cancelled: "Purchase cancelled. No access was changed."
    case .pending: "Purchase pending. Paid features remain locked until Apple verifies it."
    case .unverified: "This purchase could not be verified. Paid features remain locked."
    case .unavailable: "The App Store is unavailable. Please try again later."
    }
  }
}

struct LifetimeUnlockView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AppModel.self) private var model
  @State private var isBusy = false
  @State private var message: String?

  private var unlock: any LifetimeUnlockPresenting { model.lifetimeUnlock }

  private var presentation: LifetimeUnlockPresentation {
    LifetimeUnlockPresentation(
      state: model.lifetimeAccessState, displayPrice: unlock.displayPrice,
      isDeveloperAccess: unlock.isDeveloperAccess)
  }

  var body: some View {
    NavigationStack {
      List {
        Section("Free with Health Sync") {
          ForEach(presentation.freeFeatures, id: \.self) { feature in
            Label {
              Text(feature)
            } icon: {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
          }
        }
        .accessibilityIdentifier("lifetime-unlock-free-features")

        Section("Lifetime unlock") {
          ForEach(presentation.paidFeatures, id: \.self) { feature in
            Label {
              Text(feature)
            } icon: {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(.yellow)
            }
          }
          Text(presentation.status)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("lifetime-unlock-status")
          if let message {
            Text(message)
              .accessibilityIdentifier("lifetime-unlock-message")
          }
          if let purchaseTitle = presentation.purchaseTitle {
            Button {
              Task {
                isBusy = true
                let outcome = await unlock.purchase()
                message = LifetimeUnlockPresentation.message(for: outcome)
                isBusy = false
              }
            } label: {
              Text(purchaseTitle)
                .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .disabled(isBusy)
            .accessibilityIdentifier("lifetime-unlock-buy")
          }
          if presentation.offersRetry {
            Button("Try Again") {
              Task {
                isBusy = true
                message = nil
                await unlock.load()
                isBusy = false
              }
            }
            .disabled(isBusy)
            .accessibilityIdentifier("lifetime-unlock-retry")
          }
          if !unlock.isDeveloperAccess {
            Button("Restore Purchases") {
              Task {
                isBusy = true
                do {
                  try await unlock.restore()
                  message =
                    unlock.state == .unlocked
                    ? "Lifetime access restored."
                    : "No verified lifetime purchase was found for this Apple Account."
                } catch {
                  message = "Restore is unavailable. Please try again later."
                }
                isBusy = false
              }
            }
            .disabled(isBusy)
            .accessibilityIdentifier("lifetime-unlock-restore")
          }
        }

        Section {
          Text(
            "A purchase does not replace Apple Health permission, Home Assistant access, a compatible Health Bridge, or archive uploader approval."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Lifetime Unlock")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Label {
            Text("Lifetime Unlock")
              .font(.headline)
              .fontDesign(.rounded)
          } icon: {
            Image(
              systemName: model.lifetimeAccessState == .unlocked
                ? "checkmark.seal.fill" : "lock.open.fill"
            )
            .foregroundStyle(.yellow.gradient)
          }
          .labelStyle(.titleAndIcon)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("lifetime-unlock-done")
        }
      }
    }
  }
}
