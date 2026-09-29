import Foundation
import HealthSyncCore

enum SettingsSummary {
  static func connectionStatus(_ configuration: AppConfiguration) -> String {
    configuration.baseURL.isEmpty || configuration.healthBridgeUserID.isEmpty
      ? "Not configured" : "Configured"
  }

  static func server(_ configuration: AppConfiguration) -> String {
    guard let components = URLComponents(string: configuration.baseURL),
      let host = components.host,
      !host.isEmpty
    else {
      return "Server unavailable"
    }
    return host
  }

  static func export(selectedMetrics: Int, medicationEnabled: Bool) -> String {
    medicationEnabled
      ? "\(selectedMetrics) metrics · Medications on"
      : "\(selectedMetrics) metrics"
  }

  static func importSummary(pairingCount: Int) -> String {
    "\(pairingCount) \(pairingCount == 1 ? "pairing" : "pairings")"
  }
}
