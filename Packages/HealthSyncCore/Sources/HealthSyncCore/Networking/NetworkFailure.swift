import Foundation

public enum NetworkFailure: Error, Equatable, Sendable {
  case cancelled
  case timeout
  case dnsFailure
  case offline
  case connectionLost
  case tlsFailure
  case unauthorized
  case forbidden
  case notFound
  case validation
  case rateLimited(retryAfter: TimeInterval?)
  case server(statusCode: Int)
  case malformedResponse
  case protocolMismatch
  case unexpectedStatus(statusCode: Int)
  case transport

  public static func classify(_ error: any Error) -> Self {
    if error is CancellationError {
      return .cancelled
    }

    guard let urlError = error as? URLError else {
      return .transport
    }

    switch urlError.code {
    case .cancelled:
      return .cancelled
    case .timedOut:
      return .timeout
    case .cannotFindHost, .dnsLookupFailed:
      return .dnsFailure
    case .notConnectedToInternet:
      return .offline
    case .networkConnectionLost:
      return .connectionLost
    case .secureConnectionFailed,
      .serverCertificateHasBadDate,
      .serverCertificateUntrusted,
      .serverCertificateHasUnknownRoot,
      .serverCertificateNotYetValid,
      .clientCertificateRejected,
      .clientCertificateRequired:
      return .tlsFailure
    default:
      return .transport
    }
  }

  public static func classify(
    statusCode: Int,
    headers: [String: String] = [:]
  ) -> Self {
    switch statusCode {
    case 401:
      return .unauthorized
    case 403:
      return .forbidden
    case 404:
      return .notFound
    case 422:
      return .validation
    case 429:
      return .rateLimited(retryAfter: retryAfter(from: headers))
    case 500...599:
      return .server(statusCode: statusCode)
    default:
      return .unexpectedStatus(statusCode: statusCode)
    }
  }

  private static func retryAfter(from headers: [String: String]) -> TimeInterval? {
    guard let value = headers.first(where: { $0.key.lowercased() == "retry-after" })?.value,
      let delay = TimeInterval(value), delay >= 0
    else {
      return nil
    }
    return min(delay, 3_600)
  }
}

extension NetworkFailure: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .cancelled:
      "The request was cancelled."
    case .timeout:
      "The connection timed out."
    case .dnsFailure:
      "The Home Assistant host could not be found."
    case .offline:
      "The device is offline."
    case .connectionLost:
      "The network connection was lost."
    case .tlsFailure:
      "The secure connection could not be verified."
    case .unauthorized:
      "Home Assistant rejected the access token."
    case .forbidden:
      "Home Assistant denied this request."
    case .notFound:
      "The Home Assistant endpoint was not found."
    case .validation:
      "Home Assistant rejected the request data."
    case .rateLimited:
      "Home Assistant is receiving too many requests."
    case .server:
      "Home Assistant reported a server error."
    case .malformedResponse:
      "Home Assistant returned an unreadable response."
    case .protocolMismatch:
      "The Health Bridge response did not match the expected protocol."
    case .unexpectedStatus:
      "Home Assistant returned an unexpected status."
    case .transport:
      "The request could not be completed."
    }
  }
}
