import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class LiveTailscaleConnectivityTests: XCTestCase {
  func testMagicDNSHTTPReachesHomeAssistant() async throws {
    try await assertUnauthenticatedResponse(
      from: URLSessionTransport(),
      url: try liveBaseURL().authenticatedAPIURL
    )
  }

  func testResolvedTailscaleIPHTTPReachesHomeAssistant() async throws {
    let magicDNSURL = try liveBaseURL().authenticatedAPIURL
    let host = try XCTUnwrap(magicDNSURL.host)
    let addresses = try await SystemHostAddressResolver().addresses(for: host)
    let tailscaleAddress = try XCTUnwrap(
      addresses.first { TailscaleAddressPolicy.isTailscaleIPAddress($0.stringValue) }
    )
    var components = URLComponents(url: magicDNSURL, resolvingAgainstBaseURL: false)
    components?.percentEncodedHost = tailscaleAddress.percentEncodedHost

    try await assertUnauthenticatedResponse(
      from: URLSessionTransport(),
      url: try XCTUnwrap(components?.url)
    )
  }

  private func assertUnauthenticatedResponse(
    from transport: URLSessionTransport,
    url: URL
  ) async throws {
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("Bearer intentionally-invalid-diagnostic", forHTTPHeaderField: "Authorization")
    do {
      let (_, response) = try await transport.data(for: request)
      XCTAssertEqual(response.statusCode, 401)
    } catch let error as URLError {
      XCTFail("URL transport failed with code \(error.code.rawValue)")
    } catch let failure as NetworkFailure {
      XCTFail("Transport failed with category \(failure)")
    } catch {
      XCTFail("Transport failed with type \(type(of: error))")
    }
  }

  private func liveBaseURL() throws -> NormalizedBaseURL {
    guard
      let fileURL = Bundle(for: Self.self).url(
        forResource: "IntegrationTests.local",
        withExtension: "json"
      )
    else {
      throw XCTSkip("Ignored local integration configuration is not present")
    }
    let configuration = try JSONDecoder().decode(
      LiveIntegrationConfiguration.self,
      from: Data(contentsOf: fileURL)
    )
    return try NormalizedBaseURL.parse(
      configuration.baseURL,
      allowConfirmedLocalHTTP: true
    )
  }
}

private struct LiveIntegrationConfiguration: Decodable {
  let baseURL: String

  private enum CodingKeys: String, CodingKey {
    case baseURL = "base_url"
  }
}
