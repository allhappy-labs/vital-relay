import XCTest

@testable import HAHealthSync

final class HostAddressResolverTests: XCTestCase {
  func testResolvedIPAddressAcceptsCanonicalIPv4AndIPv6() {
    XCTAssertEqual(ResolvedIPAddress("100.100.10.20"), .ipv4("100.100.10.20"))
    XCTAssertEqual(ResolvedIPAddress("fd7a:115c:a1e0::1"), .ipv6("fd7a:115c:a1e0::1"))
  }

  func testResolvedIPAddressRejectsNonAddresses() {
    XCTAssertNil(ResolvedIPAddress("host.example.com"))
    XCTAssertNil(ResolvedIPAddress("100.100.10.20.invalid"))
  }
}
