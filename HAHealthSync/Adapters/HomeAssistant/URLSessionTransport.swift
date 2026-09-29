import Foundation
import HealthSyncCore
import OSLog

actor URLSessionTransport: HTTPTransport {
  private static let logger = Logger(
    subsystem: "com.olhapi.HAHealthSync",
    category: "network"
  )

  private let session: URLSession
  private let resolver: any HostAddressResolving

  init(
    protocolClasses: [AnyClass]? = nil,
    resolver: any HostAddressResolving = SystemHostAddressResolver()
  ) {
    self.resolver = resolver
    session = URLSession(
      configuration: Self.makeConfiguration(protocolClasses: protocolClasses)
    )
  }

  static func makeConfiguration(
    protocolClasses: [AnyClass]? = nil
  ) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    if let protocolClasses {
      configuration.protocolClasses = protocolClasses
    }
    return configuration
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    Self.logger.debug("Starting private HTTP request")
    do {
      let outgoingRequest: URLRequest
      do {
        outgoingRequest = try await preparedRequest(request)
      } catch is CancellationError {
        throw NetworkFailure.cancelled
      }
      let (data, response) = try await session.data(for: outgoingRequest)
      guard let httpResponse = response as? HTTPURLResponse else {
        Self.logger.error("HTTP request returned a non-HTTP response")
        throw NetworkFailure.malformedResponse
      }
      Self.logger.debug(
        "HTTP request completed with status \(httpResponse.statusCode, privacy: .public)"
      )
      return (data, httpResponse)
    } catch {
      Self.logger.error("HTTP request failed")
      throw error
    }
  }

  private func preparedRequest(_ request: URLRequest) async throws -> URLRequest {
    try Task.checkCancellation()
    guard let url = request.url,
      url.scheme?.lowercased() == "http",
      let host = url.host,
      TailscaleAddressPolicy.isMachineMagicDNSHost(host)
    else {
      return request
    }

    let resolved: [ResolvedIPAddress]
    do {
      resolved = try await resolver.addresses(for: host)
    } catch is CancellationError {
      throw NetworkFailure.cancelled
    } catch {
      throw NetworkFailure.dnsFailure
    }
    try Task.checkCancellation()

    guard !resolved.isEmpty else {
      throw NetworkFailure.dnsFailure
    }
    let accepted =
      resolved
      .filter { TailscaleAddressPolicy.isTailscaleIPAddress($0.stringValue) }
      .sorted {
        if $0.sortRank == $1.sortRank {
          return $0.stringValue < $1.stringValue
        }
        return $0.sortRank < $1.sortRank
      }
    guard let selected = accepted.first else {
      throw NetworkFailure.validation
    }

    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.percentEncodedHost = selected.percentEncodedHost
    guard let rewrittenURL = components?.url else {
      throw NetworkFailure.validation
    }
    var rewritten = request
    rewritten.url = rewrittenURL
    try Task.checkCancellation()
    return rewritten
  }
}
