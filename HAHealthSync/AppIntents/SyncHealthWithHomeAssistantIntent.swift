import AppIntents
import HealthSyncCore

struct SyncHealthWithHomeAssistantIntent: AppIntent {
  static let title: LocalizedStringResource = "Sync Health with Home Assistant"
  static let description = IntentDescription(
    "Synchronizes selected Apple Health metrics and enabled import pairings directly with Home Assistant."
  )

  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .background }

  @AppDependency private var handler: AppIntentSyncHandler

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let result = await handler.synchronize()
    return .result(dialog: IntentDialog(stringLiteral: AppIntentResultMessage.text(for: result)))
  }
}

enum AppIntentResultMessage {
  static func text(for result: AppIntentSyncResult) -> String {
    if result.requiresPurchase {
      return "Unlock Shortcuts sync in the app to run this Shortcut."
    }
    if result.succeeded {
      if result.synchronizedMetricCount == 0, result.synchronizedPairingCount == 0 {
        return "Nothing new to sync."
      }
      if result.synchronizedPairingCount > 0 {
        let noun = result.synchronizedPairingCount == 1 ? "pairing" : "pairings"
        return
          "Synced \(result.synchronizedMetricCount) metrics and \(result.synchronizedPairingCount) \(noun)."
      }
      return "Synced \(result.synchronizedMetricCount) metrics."
    }
    if result.failureCategory == .deviceLocked {
      let imports = result.synchronizedPairingCount > 0 ? " Home Assistant imports still ran." : ""
      return "Unlock iPhone to read Apple Health.\(imports)"
    }
    return "Sync failed: \(description(for: result.failureCategory))."
  }

  private static func description(for category: SyncFailureCategory?) -> String {
    switch category {
    case .purchaseRequired:
      "Lifetime Unlock required"
    case .unauthorized, .forbidden, .credential:
      "Home Assistant authentication"
    case .configuration:
      "app configuration"
    case .healthKit:
      "Apple Health data unavailable"
    case .deviceLocked:
      "iPhone locked"
    case .deadlineExceeded:
      "ran out of background time"
    case .timeout, .offline, .dnsFailure, .connectionLost, .transport:
      "network unavailable"
    case .tlsFailure:
      "secure connection"
    case .rateLimited:
      "Home Assistant rate limit"
    case .server:
      "Home Assistant unavailable"
    case .cancelled:
      "cancelled"
    case .notFound, .validation, .malformedResponse, .protocolMismatch, .compatibility:
      "Health Bridge compatibility"
    case .checkpoint:
      "local sync state"
    case .unknown, .none:
      "unknown error"
    }
  }
}
