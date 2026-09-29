import Foundation
import HealthSyncCore

struct ConnectionDraft: Equatable {
  var baseURL: String
  var userID: String
  var webhookSecret: String
  var accessToken: String
  var allowsLocalHTTP: Bool

  static let empty = ConnectionDraft(
    baseURL: "",
    userID: "",
    webhookSecret: "",
    accessToken: "",
    allowsLocalHTTP: false
  )

  mutating func clearSecrets() {
    webhookSecret = ""
    accessToken = ""
  }

  func configuration(preserving existing: AppConfiguration) -> AppConfiguration {
    var configuration = existing
    configuration.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    configuration.healthBridgeUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
    configuration.allowsConfirmedLocalHTTP = allowsLocalHTTP
    return configuration
  }
}
