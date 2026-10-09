import SwiftUI

struct ResetSynchronizationStateReviewView: View {
  var body: some View {
    DestructiveActionReviewView(
      presentation: .reset,
      actionIdentifier: "reset-sync-state",
      scopeIdentifier: "reset-scope-description"
    ) { model in
      await model.resetSynchronizationState()
      return "Synchronization state was reset."
    }
  }
}

struct DestructiveActionReviewView: View {
  @Environment(AppModel.self) private var model

  let presentation: DestructiveActionPresentation
  let actionIdentifier: String
  let scopeIdentifier: String
  let performAction: @MainActor (AppModel) async -> String

  @State private var showReview = false
  @State private var showFinalConfirmation = false
  @State private var resultMessage: String?

  var body: some View {
    List {
      Section(presentation.removedHeading) {
        ForEach(presentation.removed, id: \.self) { item in
          Label {
            Text(item)
          } icon: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(StatusTone.failed.color)
          }
        }
      }
      .accessibilityIdentifier(scopeIdentifier)

      Section(presentation.preservedHeading) {
        ForEach(presentation.preserved, id: \.self) { item in
          Label {
            Text(item)
          } icon: {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(StatusTone.synced.color)
          }
        }
      }

      Section {
        Button(role: .destructive) {
          showReview = true
        } label: {
          Text(presentation.reviewButtonTitle)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(model.isPerformingDestructiveAction)
        .accessibilityIdentifier(actionIdentifier)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }

      if model.isPerformingDestructiveAction {
        Section {
          HStack {
            ProgressView()
            Text("Updating protected local storage…")
          }
        }
      }

      if let resultMessage {
        Section(model.maintenanceFailureCount == 0 ? "Success" : "Partial Cleanup") {
          Text(resultMessage)
            .accessibilityIdentifier("maintenance-result")
        }
      }
    }
    .navigationTitle(presentation.title)
    .confirmationDialog(
      presentation.stageOneTitle,
      isPresented: $showReview,
      titleVisibility: .visible
    ) {
      Button(presentation.reviewButtonTitle, role: .destructive) {
        Task {
          await Task.yield()
          showFinalConfirmation = true
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(presentation.stageOneMessage)
    }
    .alert(presentation.title, isPresented: $showFinalConfirmation) {
      Button(presentation.confirmationTitle, role: .destructive) {
        Task { await perform() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(presentation.confirmationMessage)
    }
  }

  private func perform() async {
    resultMessage = nil
    let success = await performAction(model)
    guard model.isOnboardingComplete else { return }
    if model.maintenanceFailureCount == 0 {
      resultMessage = success
    } else {
      resultMessage =
        "Some local operations failed. No paths, credentials, or health values are included in this result."
    }
  }
}
