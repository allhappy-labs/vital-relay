import HealthSyncCore
import SwiftUI

struct ConnectionStepView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let selectedMetrics: Set<MetricID>
  var mode: ConnectionScreenMode = .onboarding

  @State private var draft = ConnectionDraft.empty
  @State private var showLocalHTTPWarning = false
  @State private var loadedExistingConfiguration = false
  @State private var isSaving = false
  @State private var saveError: SyncFailureCategory?

  var body: some View {
    @Bindable var model = model

    Form {
      if mode == .onboarding {
        Section {
          Text("Step 3 of 3")
            .font(.headline)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Link(
          destination: URL(
            string: "https://github.com/allhappy-labs/vital-relay/blob/main/SETUP.md")!
        ) {
          Label("Setup Instructions", systemImage: "book")
        }
        .accessibilityIdentifier("setup-instructions-link")
      } footer: {
        Text("How to install Health Bridge in Home Assistant and find each value below.")
      }

      Section("Home Assistant") {
        TextField("Base URL", text: $draft.baseURL)
          .textContentType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("base-url-field")

        TextField("Health Bridge user ID", text: $draft.userID)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("user-id-field")

        Toggle(
          "Allow confirmed local HTTP",
          isOn: Binding(
            get: { draft.allowsLocalHTTP },
            set: { newValue in
              if newValue {
                showLocalHTTPWarning = true
              } else {
                draft.allowsLocalHTTP = false
              }
            }
          )
        )
      }

      Section("Health Bridge webhook") {
        SecureField("Webhook secret", text: $draft.webhookSecret)
          .textContentType(.password)
          .accessibilityIdentifier("webhook-secret-field")
        Button("Test Health Bridge Webhook") {
          Task {
            await model.storeWebhookSecretAndTest(
              configuration: configuration,
              webhookSecret: draft.webhookSecret
            )
          }
        }
        .disabled(draft.webhookSecret.isEmpty)
        .accessibilityIdentifier("test-webhook")
        ConnectionStateLabel(state: model.webhookConnectionState, context: .webhook)
      }

      Section {
        SecureField("Long-lived access token", text: $draft.accessToken)
          .textContentType(.password)
          .accessibilityIdentifier("access-token-field")
        Button("Test Authenticated API") {
          Task {
            await model.storeAccessTokenAndTest(
              configuration: configuration,
              accessToken: draft.accessToken
            )
          }
        }
        .disabled(draft.accessToken.isEmpty)
        .accessibilityIdentifier("test-authenticated-api")
        ConnectionStateLabel(
          state: model.authenticatedConnectionState,
          context: .authenticatedAPI
        )
      } header: {
        Text("Home Assistant API")
      } footer: {
        InfoFooter(saveFooterSummary, details: saveFooterDetails)
      }

      if let saveError {
        Section("Couldn’t Save Connection") {
          Label(saveErrorMessage(for: saveError), systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .accessibilityIdentifier("save-connection-error")
        }
      }
    }
    .navigationTitle(mode == .onboarding ? "Connect" : "Connection")
    .alert("Local HTTP is not encrypted", isPresented: $showLocalHTTPWarning) {
      Button("Cancel", role: .cancel) {}
      Button("Allow Local HTTP") {
        draft.allowsLocalHTTP = true
      }
    } message: {
      Text(
        "Only use HTTP for a Home Assistant address on your trusted local network. Remote addresses must use HTTPS."
      )
    }
    .task {
      guard mode == .settings, !loadedExistingConfiguration else { return }
      let existing = model.currentConfiguration
      draft.baseURL = existing.baseURL
      draft.userID = existing.healthBridgeUserID
      draft.allowsLocalHTTP = existing.allowsConfirmedLocalHTTP
      loadedExistingConfiguration = true
      model.resetConnectionTestStates()
    }
    .safeAreaInset(edge: .bottom) {
      bottomAction
    }
    .onChange(of: draft.baseURL) {
      model.resetConnectionTestStates()
    }
    .onChange(of: draft.allowsLocalHTTP) {
      model.resetConnectionTestStates()
    }
    .onChange(of: draft.userID) {
      model.invalidateWebhookConnectionTest()
    }
    .onChange(of: draft.webhookSecret) {
      model.invalidateWebhookConnectionTest()
    }
    .onChange(of: draft.accessToken) {
      model.invalidateAuthenticatedConnectionTest()
    }
    .onDisappear {
      draft.clearSecrets()
      model.resetConnectionTestStates()
    }
  }

  private var configuration: AppConfiguration {
    var existing = mode == .settings ? model.currentConfiguration : AppConfiguration.default
    if mode == .onboarding {
      existing.selectedMetrics = selectedMetrics
    }
    return draft.configuration(preserving: existing)
  }

  private var canSave: Bool {
    guard mode == .settings || !selectedMetrics.isEmpty else { return false }
    return ConnectionFormPolicy.canSave(
      mode: mode,
      baseURL: draft.baseURL,
      userID: draft.userID,
      webhookSecret: draft.webhookSecret,
      accessToken: draft.accessToken,
      webhookState: model.webhookConnectionState,
      authenticatedState: model.authenticatedConnectionState
    )
  }

  private var saveFooterSummary: String {
    mode == .settings
      ? "Leave a credential blank to keep its current Keychain value."
      : "Both connection tests must succeed before continuing."
  }

  private var saveFooterDetails: String {
    mode == .settings
      ? "Enter it only to replace or test it. The two credentials are never interchangeable."
      : "Network, token, and webhook-secret failures are shown separately."
  }

  private var bottomAction: some View {
    saveButton.primaryActionBar()
  }

  private var saveButton: some View {
    Button {
      guard !isSaving else { return }
      isSaving = true
      saveError = nil
      Task {
        await save()
        isSaving = false
      }
    } label: {
      Group {
        if isSaving {
          ProgressView()
        } else {
          Text(mode == .onboarding ? "Save and Continue" : "Save Connection")
        }
      }
      .frame(maxWidth: .infinity)
    }
    .disabled(!canSave || isSaving)
    .accessibilityIdentifier("save-connection")
  }

  private func saveErrorMessage(for error: SyncFailureCategory) -> String {
    switch error {
    case .credential:
      "The credentials couldn’t be saved to Keychain. Try again."
    case .configuration, .validation:
      "The connection settings couldn’t be saved. Check the fields and try again."
    default:
      "The connection couldn’t be saved. Try again."
    }
  }

  private func save() async {
    if mode == .onboarding {
      await model.completeOnboarding(
        configuration: configuration,
        webhookSecret: draft.webhookSecret,
        accessToken: draft.accessToken
      )
      if model.isOnboardingComplete {
        draft.clearSecrets()
        model.resetConnectionTestStates()
      } else {
        saveError = model.currentError ?? .configuration
      }
    } else {
      await model.updateConnection(
        configuration: configuration,
        webhookSecret: draft.webhookSecret,
        accessToken: draft.accessToken
      )
      if model.currentError == nil {
        draft.clearSecrets()
        model.resetConnectionTestStates()
        dismiss()
      } else {
        saveError = model.currentError ?? .configuration
      }
    }
  }
}

enum ConnectionScreenMode {
  case onboarding
  case settings
}

enum ConnectionFormPolicy {
  static func canSave(
    mode: ConnectionScreenMode,
    baseURL: String,
    userID: String,
    webhookSecret: String,
    accessToken: String,
    webhookState: ConnectionTestState,
    authenticatedState: ConnectionTestState
  ) -> Bool {
    guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return false
    }
    guard mode == .onboarding else { return true }
    return !webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && webhookState == .succeeded
      && authenticatedState == .succeeded
  }
}

enum ConnectionTestContext {
  case webhook
  case authenticatedAPI
}

enum ConnectionFailurePresentation {
  static func message(
    for category: SyncFailureCategory,
    context: ConnectionTestContext
  ) -> String {
    switch category {
    case .purchaseRequired:
      "Lifetime Unlock is required for this feature."
    case .timeout:
      "Network error: The connection timed out."
    case .dnsFailure:
      "Network error: The Home Assistant host could not be found."
    case .offline:
      "Network error: This iPhone is offline."
    case .connectionLost:
      "Network error: The connection was lost."
    case .tlsFailure:
      "Network error: The secure connection could not be verified."
    case .transport:
      "Network error: The request could not be completed."
    case .unauthorized:
      switch context {
      case .authenticatedAPI:
        "Token error: Home Assistant rejected the long-lived access token."
      case .webhook:
        "Webhook secret error: Health Bridge rejected the webhook secret."
      }
    case .forbidden:
      switch context {
      case .authenticatedAPI:
        "Token error: The long-lived access token does not have permission."
      case .webhook:
        "Webhook secret error: Health Bridge denied the request."
      }
    case .credential:
      switch context {
      case .authenticatedAPI:
        "Token error: Enter a long-lived access token and test again."
      case .webhook:
        "Webhook secret error: Enter the Health Bridge secret and test again."
      }
    case .notFound:
      switch context {
      case .authenticatedAPI:
        "Configuration error: The Home Assistant API endpoint was not found."
      case .webhook:
        "Configuration error: The Health Bridge webhook was not found."
      }
    case .rateLimited:
      "Home Assistant error: Too many requests. Try again later."
    case .server:
      "Home Assistant error: The server reported an internal error."
    case .malformedResponse:
      "Response error: Home Assistant returned unreadable data."
    case .protocolMismatch:
      "Response error: Health Bridge returned an incompatible acknowledgement."
    case .configuration, .validation:
      "Configuration error: Check the URL and connection fields."
    case .cancelled:
      "Connection test cancelled."
    case .healthKit, .deviceLocked, .checkpoint, .compatibility, .deadlineExceeded, .unknown:
      "Connection failed. Check the configuration and try again."
    }
  }
}

private struct ConnectionStateLabel: View {
  let state: ConnectionTestState
  let context: ConnectionTestContext

  var body: some View {
    switch state {
    case .notTested:
      EmptyView()
    case .testing:
      Label("Testing…", systemImage: "clock")
        .foregroundStyle(.secondary)
    case .succeeded:
      Label("Connection succeeded", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed(let category):
      Label(
        ConnectionFailurePresentation.message(for: category, context: context),
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.red)
    }
  }
}
