import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Allowlist-first diagnostics")
struct DiagnosticReportTests {
  @Test("Renders only versions booleans counts timestamps and categories")
  func safeReport() throws {
    let report = DiagnosticReport(
      generatedAt: Date(timeIntervalSince1970: 1_788_035_400),
      appVersion: "1.0",
      buildVersion: "42",
      osVersion: "iOS 26.5",
      integrationVersion: "1.2.1",
      liveProtocolVersion: 1,
      backfillProtocolVersion: 1,
      authenticatedAPIConnected: true,
      webhookConnected: true,
      backgroundSyncEnabled: true,
      backgroundSyncFrequency: .balanced,
      historicalImportEnabled: false,
      medicationSyncEnabled: true,
      selectedMetricCount: 3,
      pairingCount: 2,
      registeredBackgroundMetricCount: 2,
      lastAttemptedAt: Date(timeIntervalSince1970: 1_788_035_000),
      lastSuccessfulAt: Date(timeIntervalSince1970: 1_788_034_000),
      failureCategories: ["offline"],
      interruptedEventCount: 2,
      throttledWakeCount: 5
    )

    let output = try report.render(
      redacting: ["fixture-secret", "8421", "https://ha.example.invalid"]
    )

    #expect(output.contains(#""schema_version" : 1"#))
    #expect(output.contains(#""integration_version" : "1.2.1""#))
    #expect(output.contains(#""selected_metric_count" : 3"#))
    #expect(output.contains(#""background_sync_frequency" : "balanced""#))
    #expect(output.contains("offline"))
    #expect(output.contains(#""interrupted_event_count" : 2"#))
    #expect(output.contains(#""throttled_wake_count" : 5"#))
    #expect(output.contains("fixture-secret") == false)
    #expect(output.contains("8421") == false)
    #expect(output.contains("ha.example.invalid") == false)
    #expect(output.contains("base_url") == false)
    #expect(output.contains("entity_id") == false)
    #expect(output.contains("health_value") == false)
  }
}
