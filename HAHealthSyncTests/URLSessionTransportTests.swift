import Foundation
import HealthSyncCore
import XCTest
import os

@testable import HAHealthSync

final class URLSessionTransportTests: XCTestCase {
  override func tearDown() {
    StubURLProtocol.reset()
    super.tearDown()
  }

  func testConfigurationDoesNotPersistHTTPState() {
    let configuration = URLSessionTransport.makeConfiguration(
      protocolClasses: [StubURLProtocol.self]
    )

    XCTAssertNil(configuration.urlCache)
    XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertNil(configuration.httpCookieStorage)
    XCTAssertFalse(configuration.httpShouldSetCookies)
    XCTAssertEqual(
      configuration.protocolClasses?.first.map(ObjectIdentifier.init),
      ObjectIdentifier(StubURLProtocol.self)
    )
  }

  func testForwardsMethodURLHeadersAndBody() async throws {
    let expectedBody = Data(#"{"request":"test"}"#.utf8)
    StubURLProtocol.install(id: "request") { request in
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.url?.absoluteString, "https://ha.example.com/api/test")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
      XCTAssertEqual(request.bodyData, expectedBody)
      return .response(statusCode: 201, data: Data("accepted".utf8))
    }

    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://ha.example.com/api/test")))
    request.httpMethod = "POST"
    request.setValue("request", forHTTPHeaderField: "X-Test-ID")
    request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
    request.httpBody = expectedBody

    let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])
    let (data, response) = try await transport.data(for: request)

    XCTAssertEqual(response.statusCode, 201)
    XCTAssertEqual(data, Data("accepted".utf8))
  }

  func testForwardsTransportErrors() async throws {
    StubURLProtocol.install(id: "error") { _ in
      .failure(URLError(.timedOut))
    }
    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://ha.example.com/api/")))
    request.setValue("error", forHTTPHeaderField: "X-Test-ID")
    let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])

    do {
      _ = try await transport.data(for: request)
      XCTFail("Expected the transport error to be forwarded")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .timedOut)
    }
  }

  func testRewritesTailscaleHTTPAndPreservesRequest() async throws {
    let expectedBody = Data(#"{"request":"test"}"#.utf8)
    StubURLProtocol.install(id: "rewrite") { request in
      XCTAssertEqual(
        request.url?.absoluteString,
        "http://100.100.10.20:8123/base%20path/api/?probe=yes"
      )
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.timeoutInterval, 17)
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
      XCTAssertEqual(request.bodyData, expectedBody)
      return .response(statusCode: 200, data: Data("accepted".utf8))
    }

    var request = URLRequest(
      url: try XCTUnwrap(
        URL(string: "http://ha.test-tailnet.ts.net:8123/base%20path/api/?probe=yes")
      )
    )
    request.httpMethod = "POST"
    request.timeoutInterval = 17
    request.setValue("rewrite", forHTTPHeaderField: "X-Test-ID")
    request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
    request.httpBody = expectedBody
    let resolver = FakeHostAddressResolver(
      result: .success([try XCTUnwrap(ResolvedIPAddress("100.100.10.20"))])
    )
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    let (_, response) = try await transport.data(for: request)

    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(resolver.hosts, ["ha.test-tailnet.ts.net"])
  }

  func testRewritesIPv6WithBrackets() async throws {
    StubURLProtocol.install(id: "ipv6") { request in
      XCTAssertEqual(
        request.url?.absoluteString,
        "http://[fd7a:115c:a1e0::1]:8123/api/"
      )
      return .response(statusCode: 200, data: Data())
    }
    var request = URLRequest(
      url: try XCTUnwrap(URL(string: "http://ha.test-tailnet.ts.net:8123/api/"))
    )
    request.setValue("ipv6", forHTTPHeaderField: "X-Test-ID")
    let resolver = FakeHostAddressResolver(
      result: .success([try XCTUnwrap(ResolvedIPAddress("fd7a:115c:a1e0::1"))])
    )
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    _ = try await transport.data(for: request)
  }

  func testPrefersIPv4ThenLexicalAddressOrder() async throws {
    StubURLProtocol.install(id: "order") { request in
      XCTAssertEqual(request.url?.host, "100.100.10.1")
      return .response(statusCode: 200, data: Data())
    }
    var request = URLRequest(
      url: try XCTUnwrap(URL(string: "http://ha.test-tailnet.ts.net:8123/api/"))
    )
    request.setValue("order", forHTTPHeaderField: "X-Test-ID")
    let resolver = FakeHostAddressResolver(
      result: .success([
        try XCTUnwrap(ResolvedIPAddress("fd7a:115c:a1e0::1")),
        try XCTUnwrap(ResolvedIPAddress("100.100.20.1")),
        try XCTUnwrap(ResolvedIPAddress("100.100.10.1")),
      ])
    )
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    _ = try await transport.data(for: request)
  }

  func testMixedResultsDiscardPublicAddresses() async throws {
    StubURLProtocol.install(id: "mixed") { request in
      XCTAssertEqual(request.url?.host, "100.100.10.20")
      return .response(statusCode: 200, data: Data())
    }
    var request = URLRequest(
      url: try XCTUnwrap(URL(string: "http://ha.test-tailnet.ts.net:8123/api/"))
    )
    request.setValue("mixed", forHTTPHeaderField: "X-Test-ID")
    let resolver = FakeHostAddressResolver(
      result: .success([
        try XCTUnwrap(ResolvedIPAddress("203.0.113.1")),
        try XCTUnwrap(ResolvedIPAddress("100.100.10.20")),
      ])
    )
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    _ = try await transport.data(for: request)
  }

  func testPublicOnlyResultFailsValidationBeforeRequest() async throws {
    let resolver = FakeHostAddressResolver(
      result: .success([try XCTUnwrap(ResolvedIPAddress("203.0.113.1"))])
    )
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    await assertFailure(
      .validation,
      from: transport,
      url: "http://ha.test-tailnet.ts.net:8123/api/"
    )
  }

  func testEmptyResultFailsAsDNSBeforeRequest() async throws {
    let resolver = FakeHostAddressResolver(result: .success([]))
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    await assertFailure(
      .dnsFailure,
      from: transport,
      url: "http://ha.test-tailnet.ts.net:8123/api/"
    )
  }

  func testResolverErrorFailsAsDNSBeforeRequest() async throws {
    let resolver = FakeHostAddressResolver(result: .failure(FakeResolutionError.failed))
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    await assertFailure(
      .dnsFailure,
      from: transport,
      url: "http://ha.test-tailnet.ts.net:8123/api/"
    )
  }

  func testNonMagicDNSRequestsBypassResolver() async throws {
    let urls = [
      "https://ha.test-tailnet.ts.net/api/",
      "http://100.100.10.20:8123/api/",
      "http://homeassistant.local:8123/api/",
      "http://192.168.200.10:8123/api/",
    ]
    let resolver = FakeHostAddressResolver(result: .failure(FakeResolutionError.failed))
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )

    for (index, url) in urls.enumerated() {
      let testID = "bypass-\(index)"
      StubURLProtocol.install(id: testID) { request in
        XCTAssertEqual(request.url?.absoluteString, url)
        return .response(statusCode: 200, data: Data())
      }
      var request = URLRequest(url: try XCTUnwrap(URL(string: url)))
      request.setValue(testID, forHTTPHeaderField: "X-Test-ID")
      _ = try await transport.data(for: request)
    }

    XCTAssertTrue(resolver.hosts.isEmpty)
  }

  func testPreCancelledRequestDoesNotResolveOrStartRequest() async throws {
    let resolver = FakeHostAddressResolver(
      result: .success([try XCTUnwrap(ResolvedIPAddress("100.100.10.20"))])
    )
    let transport = URLSessionTransport(
      protocolClasses: [StubURLProtocol.self],
      resolver: resolver
    )
    let operation = Task {
      try await transport.data(
        for: URLRequest(
          url: try XCTUnwrap(URL(string: "http://ha.test-tailnet.ts.net:8123/api/"))
        )
      )
    }
    operation.cancel()

    do {
      _ = try await operation.value
      XCTFail("Expected cancellation")
    } catch let failure as NetworkFailure {
      XCTAssertEqual(failure, .cancelled)
    } catch {
      XCTFail("Expected NetworkFailure.cancelled, received \(type(of: error))")
    }
    XCTAssertTrue(resolver.hosts.isEmpty)
  }

  func testCancellationStopsAnInFlightRequest() async throws {
    StubURLProtocol.install(id: "cancel") { _ in .pending }
    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://ha.example.com/api/")))
    request.setValue("cancel", forHTTPHeaderField: "X-Test-ID")
    let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])
    let operation = Task {
      try await transport.data(for: request)
    }

    await Task.yield()
    operation.cancel()

    do {
      _ = try await operation.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Structured cancellation may surface directly.
    } catch let failure as NetworkFailure {
      XCTAssertEqual(failure, .cancelled)
    } catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }
  }
}

private enum FakeResolutionError: Error {
  case failed
}

private final class FakeHostAddressResolver: HostAddressResolving, @unchecked Sendable {
  private let result: Result<[ResolvedIPAddress], any Error>
  private let requestedHosts = OSAllocatedUnfairLock(initialState: [String]())

  init(result: Result<[ResolvedIPAddress], any Error>) {
    self.result = result
  }

  func addresses(for host: String) async throws -> [ResolvedIPAddress] {
    requestedHosts.withLock { $0.append(host) }
    return try result.get()
  }

  var hosts: [String] {
    requestedHosts.withLock { $0 }
  }
}

private func assertFailure(
  _ expected: NetworkFailure,
  from transport: URLSessionTransport,
  url: String,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await transport.data(for: URLRequest(url: URL(string: url)!))
    XCTFail("Expected request failure", file: file, line: line)
  } catch let failure as NetworkFailure {
    XCTAssertEqual(failure, expected, file: file, line: line)
  } catch {
    XCTFail("Expected NetworkFailure, received \(type(of: error))", file: file, line: line)
  }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  enum Result: @unchecked Sendable {
    case response(statusCode: Int, data: Data)
    case failure(any Error)
    case pending
  }

  typealias Handler = @Sendable (URLRequest) -> Result

  private static let state = OSAllocatedUnfairLock(initialState: [String: Handler]())

  static func install(id: String, _ handler: @escaping Handler) {
    state.withLock { $0[id] = handler }
  }

  static func reset() {
    state.withLock { $0.removeAll() }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let testID = request.value(forHTTPHeaderField: "X-Test-ID")
    guard let testID, let handler = Self.state.withLock({ $0[testID] }) else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }

    switch handler(request) {
    case .response(let statusCode, let data):
      guard
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: statusCode,
          httpVersion: nil,
          headerFields: nil
        )
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        return
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    case .pending:
      break
    }
  }

  override func stopLoading() {}
}

extension URLRequest {
  fileprivate var bodyData: Data? {
    if let httpBody {
      return httpBody
    }
    guard let httpBodyStream else {
      return nil
    }

    httpBodyStream.open()
    defer { httpBodyStream.close() }

    var data = Data()
    let bufferSize = 1_024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while httpBodyStream.hasBytesAvailable {
      let count = httpBodyStream.read(buffer, maxLength: bufferSize)
      guard count >= 0 else {
        return nil
      }
      if count == 0 {
        break
      }
      data.append(buffer, count: count)
    }
    return data
  }
}
