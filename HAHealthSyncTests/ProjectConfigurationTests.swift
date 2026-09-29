import XCTest

@testable import HAHealthSync

final class ProjectConfigurationTests: XCTestCase {
  func testPrivacyUsageDescriptionsArePresent() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)

    XCTAssertFalse(
      try XCTUnwrap(info["NSHealthShareUsageDescription"] as? String).isEmpty
    )
    XCTAssertFalse(
      try XCTUnwrap(info["NSHealthUpdateUsageDescription"] as? String).isEmpty
    )
    XCTAssertFalse(
      try XCTUnwrap(info["NSLocalNetworkUsageDescription"] as? String).isEmpty
    )
  }

  func testBackgroundConfigurationIsMinimalAndExact() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)
    XCTAssertEqual(
      info["BGTaskSchedulerPermittedIdentifiers"] as? [String],
      [AppRefreshManager.identifier]
    )
    XCTAssertEqual(info["UIBackgroundModes"] as? [String], ["fetch"])
  }

  func testATSAllowsOnlyLocalNetworkingAndTailscaleHTTPRanges() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)
    let ats = try XCTUnwrap(info["NSAppTransportSecurity"] as? [String: Any])
    XCTAssertEqual(ats["NSAllowsLocalNetworking"] as? Bool, true)
    XCTAssertNil(ats["NSAllowsArbitraryLoads"])

    let exceptions = try XCTUnwrap(ats["NSExceptionDomains"] as? [String: Any])
    XCTAssertEqual(
      Set(exceptions.keys),
      ["100.64.0.0/10", "fd7a:115c:a1e0::/48"]
    )
    for range in ["100.64.0.0/10", "fd7a:115c:a1e0::/48"] {
      let policy = try XCTUnwrap(exceptions[range] as? [String: Any])
      XCTAssertEqual(policy["NSExceptionAllowsInsecureHTTPLoads"] as? Bool, true)
      XCTAssertEqual(policy.count, 1)
    }
  }
}
