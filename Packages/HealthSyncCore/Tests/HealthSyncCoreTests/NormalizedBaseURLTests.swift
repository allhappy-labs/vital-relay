import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Normalized Home Assistant base URL")
struct NormalizedBaseURLTests {
  @Test("Normalizes HTTPS URLs while preserving a reverse-proxy prefix")
  func normalizesHTTPSURL() throws {
    let baseURL = try NormalizedBaseURL.parse(
      "  HTTPS://HA.Example.COM:8443/home-assistant/?ignored=yes#fragment  ",
      allowConfirmedLocalHTTP: false
    )

    #expect(baseURL.url.absoluteString == "https://ha.example.com:8443/home-assistant")
    #expect(
      baseURL.authenticatedAPIURL.absoluteString
        == "https://ha.example.com:8443/home-assistant/api/"
    )
    #expect(
      baseURL.healthBridgeWebhookURL.absoluteString
        == "https://ha.example.com:8443/home-assistant/api/webhook/health_bridge"
    )
    #expect(
      baseURL.statesURL.absoluteString
        == "https://ha.example.com:8443/home-assistant/api/states"
    )
  }

  @Test("Safely encodes a Home Assistant entity as one path component")
  func encodesEntityID() throws {
    let baseURL = try NormalizedBaseURL.parse(
      "https://ha.example.com/prefix",
      allowConfirmedLocalHTTP: false
    )

    let stateURL = try baseURL.stateURL(entityID: "sensor.body mass/inside")

    #expect(
      stateURL.absoluteString
        == "https://ha.example.com/prefix/api/states/sensor.body%20mass%2Finside"
    )
  }

  @Test(arguments: ["", "   ", "sensor\u{0}invalid"])
  func rejectsInvalidEntityIDs(entityID: String) throws {
    let baseURL = try NormalizedBaseURL.parse(
      "https://ha.example.com",
      allowConfirmedLocalHTTP: false
    )

    #expect(throws: NormalizedBaseURLError.invalidPathComponent) {
      try baseURL.stateURL(entityID: entityID)
    }
  }

  @Test(
    arguments: [
      "http://192.168.200.10",
      "http://10.0.0.2:8123",
      "http://172.16.0.1",
      "http://127.0.0.1",
      "http://[::1]:8123",
      "http://[fe80::1]",
      "http://[fd00::1]",
      "http://homeassistant.local:8123",
      "http://subdomain.homeassistant.local",
    ]
  )
  func permitsConfirmedLocalHTTP(input: String) throws {
    let baseURL = try NormalizedBaseURL.parse(input, allowConfirmedLocalHTTP: true)

    #expect(baseURL.url.scheme == "http")
  }

  @Test(
    "Permits explicitly confirmed Tailscale HTTP addresses",
    arguments: [
      "http://homeassistant.example-tailnet.ts.net:8123",
      "http://100.64.0.0:8123",
      "http://100.127.255.255:8123",
      "http://[fd7a:115c:a1e0::1]:8123",
    ]
  )
  func permitsConfirmedTailscaleHTTP(input: String) throws {
    let baseURL = try NormalizedBaseURL.parse(input, allowConfirmedLocalHTTP: true)

    #expect(baseURL.url.scheme == "http")
  }

  @Test(
    arguments: [
      "http://192.168.200.10",
      "http://homeassistant.local:8123",
      "http://[::1]",
      "http://homeassistant.example-tailnet.ts.net:8123",
      "http://100.100.100.100:8123",
    ]
  )
  func localHTTPStillRequiresExplicitConfirmation(input: String) {
    #expect(throws: NormalizedBaseURLError.localHTTPRequiresConfirmation) {
      try NormalizedBaseURL.parse(input, allowConfirmedLocalHTTP: false)
    }
  }

  @Test(
    arguments: [
      "http://example.com",
      "http://8.8.8.8:8123",
      "http://172.15.255.255",
      "http://172.32.0.1",
      "http://192.168.200.10.example.com",
      "http://homeassistant.local.example.com",
      "http://homeassistant.example-tailnet.ts.net.example.com",
      "http://host.ts.net",
      "http://100.63.255.255:8123",
      "http://100.128.0.0:8123",
      "http://[2001:4860:4860::8888]",
    ]
  )
  func rejectsPublicHTTPEvenWhenConfirmed(input: String) {
    #expect(throws: NormalizedBaseURLError.insecureRemoteHTTP) {
      try NormalizedBaseURL.parse(input, allowConfirmedLocalHTTP: true)
    }
  }

  @Test(
    arguments: [
      "",
      "ha.example.com",
      "ftp://ha.example.com",
      "https://",
      "https:///missing-host",
      "https://user:password@ha.example.com",
      "https://ha example.com",
    ]
  )
  func rejectsMalformedOrUnsupportedInputs(input: String) {
    #expect(throws: (any Error).self) {
      try NormalizedBaseURL.parse(input, allowConfirmedLocalHTTP: false)
    }
  }
}
