import Foundation
import Testing

@testable import HealthSyncCore

actor StubHTTPTransport: HTTPTransport {
  private let responseData: Data
  private let statusCode: Int
  private let headers: [String: String]
  private var recordedRequests: [URLRequest] = []

  init(
    responseData: Data,
    statusCode: Int = 200,
    headers: [String: String] = [:]
  ) {
    self.responseData = responseData
    self.statusCode = statusCode
    self.headers = headers
  }

  func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
    recordedRequests.append(request)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: headers
    )!
    return (responseData, response)
  }

  func requests() -> [URLRequest] {
    recordedRequests
  }
}

func fixtureData(named name: String) throws -> Data {
  let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
  return try Data(contentsOf: url)
}
