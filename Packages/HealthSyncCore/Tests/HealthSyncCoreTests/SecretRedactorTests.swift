import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Secret and health-value redaction")
struct SecretRedactorTests {
  @Test("Redacts credentials URLs addresses entities and value fields")
  func adversarialText() {
    let input = #"""
      Authorization: bEaReR Access.Token-123
      POST https://user:password@[fd00::1234]:8123/api/webhook/health_bridge?token=Webhook-Secret%2F%2B#private
      fallback=http://192.168.200.10:8123/api/states/sensor.body_mass
      {"token":"Webhook-Secret/+","state":"8421","nested":{"value":98.6}}
      request body: {"value":42,"entity_id":"sensor.body_mass"}
      error across lines
      ACCESS_TOKEN = Access.Token-123
      """#

    let output = SecretRedactor.redact(
      input,
      secrets: ["Webhook-Secret/+", "Access.Token-123"]
    )

    for sensitive in [
      "Access.Token-123", "Webhook-Secret/+", "Webhook-Secret%2F%2B",
      "user:password", "fd00::1234", "192.168.200.10", "sensor.body_mass", "8421", "98.6",
    ] {
      #expect(output.contains(sensitive) == false)
    }
    #expect(output.contains("<redacted-url>"))
    #expect(output.contains("<redacted>"))
  }

  @Test("Redaction is case-insensitive for field names and handles multiline JSON")
  func mixedCaseFields() {
    let input = """
      BeArEr: secret-value
      \"STATE\": \"private-state\",
      \"VaLuE\": 123.45,
      \"WEBHOOK_SECRET\": \"private-webhook\"
      host [2001:db8::1]
      """

    let output = SecretRedactor.redact(input, secrets: ["secret-value"])

    #expect(output.contains("secret-value") == false)
    #expect(output.contains("private-state") == false)
    #expect(output.contains("123.45") == false)
    #expect(output.contains("private-webhook") == false)
    #expect(output.contains("2001:db8::1") == false)
  }
}
