import Testing

@testable import HealthSyncCore

@Suite("Tailscale address policy")
struct TailscaleAddressPolicyTests {
  @Test(
    arguments: [
      ("homeassistant.example-tailnet.ts.net", true),
      ("HOMEASSISTANT.EXAMPLE-TAILNET.TS.NET", true),
      ("host.ts.net", false),
      ("homeassistant..ts.net", false),
      ("homeassistant.example-tailnet.ts.net.example.com", false),
      ("example.com", false),
    ]
  )
  func classifiesMagicDNSHosts(host: String, expected: Bool) {
    #expect(TailscaleAddressPolicy.isMachineMagicDNSHost(host) == expected)
  }

  @Test(
    arguments: [
      ("100.64.0.0", true),
      ("100.127.255.255", true),
      ("100.63.255.255", false),
      ("100.128.0.0", false),
      ("192.168.200.10", false),
      ("fd7a:115c:a1e0::", true),
      ("fd7a:115c:a1e0:ffff:ffff:ffff:ffff:ffff", true),
      ("fd7a:115c:a1df::", false),
      ("fd7a:115c:a1e1::", false),
      ("fd00::1", false),
      ("not-an-address", false),
    ]
  )
  func classifiesTailscaleAddresses(address: String, expected: Bool) {
    #expect(TailscaleAddressPolicy.isTailscaleIPAddress(address) == expected)
  }
}
