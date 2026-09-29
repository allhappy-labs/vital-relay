import Foundation

public struct DiagnosticReport: Codable, Sendable, Equatable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let appVersion: String
  public let buildVersion: String
  public let osVersion: String
  public let integrationVersion: String?
  public let liveProtocolVersion: Int
  public let backfillProtocolVersion: Int
  public let authenticatedAPIConnected: Bool
  public let webhookConnected: Bool
  public let backgroundSyncEnabled: Bool
  public let backgroundSyncFrequency: BackgroundSyncFrequency
  public let historicalImportEnabled: Bool
  public let medicationSyncEnabled: Bool
  public let selectedMetricCount: Int
  public let pairingCount: Int
  public let registeredBackgroundMetricCount: Int
  public let lastAttemptedAt: Date?
  public let lastSuccessfulAt: Date?
  public let failureCategories: [String]
  public let interruptedEventCount: Int
  public let throttledWakeCount: Int

  public init(
    generatedAt: Date,
    appVersion: String,
    buildVersion: String,
    osVersion: String,
    integrationVersion: String?,
    liveProtocolVersion: Int,
    backfillProtocolVersion: Int,
    authenticatedAPIConnected: Bool,
    webhookConnected: Bool,
    backgroundSyncEnabled: Bool,
    backgroundSyncFrequency: BackgroundSyncFrequency,
    historicalImportEnabled: Bool,
    medicationSyncEnabled: Bool,
    selectedMetricCount: Int,
    pairingCount: Int,
    registeredBackgroundMetricCount: Int,
    lastAttemptedAt: Date?,
    lastSuccessfulAt: Date?,
    failureCategories: [String],
    interruptedEventCount: Int = 0,
    throttledWakeCount: Int = 0
  ) {
    schemaVersion = 1
    self.generatedAt = generatedAt
    self.appVersion = appVersion
    self.buildVersion = buildVersion
    self.osVersion = osVersion
    self.integrationVersion = integrationVersion
    self.liveProtocolVersion = liveProtocolVersion
    self.backfillProtocolVersion = backfillProtocolVersion
    self.authenticatedAPIConnected = authenticatedAPIConnected
    self.webhookConnected = webhookConnected
    self.backgroundSyncEnabled = backgroundSyncEnabled
    self.backgroundSyncFrequency = backgroundSyncFrequency
    self.historicalImportEnabled = historicalImportEnabled
    self.medicationSyncEnabled = medicationSyncEnabled
    self.selectedMetricCount = selectedMetricCount
    self.pairingCount = pairingCount
    self.registeredBackgroundMetricCount = registeredBackgroundMetricCount
    self.lastAttemptedAt = lastAttemptedAt
    self.lastSuccessfulAt = lastSuccessfulAt
    self.failureCategories = failureCategories.sorted()
    self.interruptedEventCount = interruptedEventCount
    self.throttledWakeCount = throttledWakeCount
  }

  public func render(redacting secrets: [String] = []) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(ISO8601DateFormatter().string(from: date))
    }
    let data = try encoder.encode(self)
    guard let text = String(data: data, encoding: .utf8) else {
      throw DiagnosticReportError.encodingFailed
    }
    return SecretRedactor.redact(text, secrets: secrets)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case generatedAt = "generated_at"
    case appVersion = "app_version"
    case buildVersion = "build_version"
    case osVersion = "os_version"
    case integrationVersion = "integration_version"
    case liveProtocolVersion = "live_protocol_version"
    case backfillProtocolVersion = "backfill_protocol_version"
    case authenticatedAPIConnected = "authenticated_api_connected"
    case webhookConnected = "webhook_connected"
    case backgroundSyncEnabled = "background_sync_enabled"
    case backgroundSyncFrequency = "background_sync_frequency"
    case historicalImportEnabled = "historical_import_enabled"
    case medicationSyncEnabled = "medication_sync_enabled"
    case selectedMetricCount = "selected_metric_count"
    case pairingCount = "pairing_count"
    case registeredBackgroundMetricCount = "registered_background_metric_count"
    case lastAttemptedAt = "last_attempted_at"
    case lastSuccessfulAt = "last_successful_at"
    case failureCategories = "failure_categories"
    case interruptedEventCount = "interrupted_event_count"
    case throttledWakeCount = "throttled_wake_count"
  }
}

public enum DiagnosticReportError: Error, Sendable, Equatable {
  case encodingFailed
}
