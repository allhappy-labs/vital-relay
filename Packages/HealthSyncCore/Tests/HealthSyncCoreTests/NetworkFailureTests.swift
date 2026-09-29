import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Network failure classification")
struct NetworkFailureTests {
  @Test(
    arguments: [
      (URLError.Code.timedOut, NetworkFailure.timeout),
      (.cannotFindHost, .dnsFailure),
      (.dnsLookupFailed, .dnsFailure),
      (.notConnectedToInternet, .offline),
      (.networkConnectionLost, .connectionLost),
      (.secureConnectionFailed, .tlsFailure),
      (.serverCertificateUntrusted, .tlsFailure),
      (.serverCertificateHasBadDate, .tlsFailure),
    ]
  )
  func classifiesTransportErrors(code: URLError.Code, expected: NetworkFailure) {
    #expect(NetworkFailure.classify(URLError(code)) == expected)
  }

  @Test("Preserves cancellation")
  func classifiesCancellation() {
    #expect(NetworkFailure.classify(CancellationError()) == .cancelled)
    #expect(NetworkFailure.classify(URLError(.cancelled)) == .cancelled)
  }

  @Test(
    arguments: [
      (401, NetworkFailure.unauthorized),
      (403, .forbidden),
      (404, .notFound),
      (422, .validation),
      (500, .server(statusCode: 500)),
      (503, .server(statusCode: 503)),
      (418, .unexpectedStatus(statusCode: 418)),
    ]
  )
  func classifiesHTTPStatuses(statusCode: Int, expected: NetworkFailure) {
    #expect(NetworkFailure.classify(statusCode: statusCode) == expected)
  }

  @Test("Parses a bounded Retry-After delay")
  func parsesRetryAfter() {
    #expect(
      NetworkFailure.classify(statusCode: 429, headers: ["Retry-After": "12"])
        == .rateLimited(retryAfter: 12)
    )
    #expect(
      NetworkFailure.classify(statusCode: 429, headers: ["retry-after": "999999"])
        == .rateLimited(retryAfter: 3_600)
    )
    #expect(
      NetworkFailure.classify(statusCode: 429, headers: ["Retry-After": "private"])
        == .rateLimited(retryAfter: nil)
    )
  }

  @Test("Descriptions cannot echo request URLs, bodies, or credentials")
  func descriptionsArePrivacySafe() {
    let forbiddenText = ["ha.example.com", "secret-token", "8421"]
    let failures: [NetworkFailure] = [
      .timeout,
      .dnsFailure,
      .offline,
      .connectionLost,
      .tlsFailure,
      .unauthorized,
      .forbidden,
      .notFound,
      .validation,
      .rateLimited(retryAfter: 12),
      .server(statusCode: 503),
      .malformedResponse,
      .protocolMismatch,
      .unexpectedStatus(statusCode: 418),
    ]

    for failure in failures {
      for forbidden in forbiddenText {
        #expect(!failure.localizedDescription.localizedCaseInsensitiveContains(forbidden))
      }
    }
  }
}
