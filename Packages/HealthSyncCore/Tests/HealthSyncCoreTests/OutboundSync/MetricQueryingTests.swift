import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Metric query contract")
struct MetricQueryingTests {
  @Test("Fake returns configured readings and empty results")
  func readingsAndEmptyResults() async throws {
    let service = FakeMetricQueryService()
    let timestamp = Date(timeIntervalSince1970: 1_788_035_400)
    let reading = MetricReading(metricID: .steps, timestamp: timestamp, value: 42)
    await service.setReading(reading)
    let definition = try #require(MetricRegistry[.steps])

    #expect(
      try await service.currentReading(
        for: definition,
        now: timestamp,
        calendar: Calendar(identifier: .gregorian)
      ) == reading
    )

    await service.setReading(nil)
    #expect(
      try await service.currentReading(
        for: definition,
        now: timestamp,
        calendar: Calendar(identifier: .gregorian)
      ) == nil
    )
  }

  @Test("Fake records selected authorization types")
  func selectedAuthorization() async throws {
    let service = FakeMetricQueryService()

    try await service.requestReadAuthorization(for: [.steps, .bodyMass])

    #expect(await service.authorizedMetrics == [.steps, .bodyMass])
  }

  @Test("Fake forwards authorization and query errors")
  func configuredErrors() async throws {
    let authorizationService = FakeMetricQueryService()
    await authorizationService.setAuthorizationError(.authorizationDenied)
    do {
      try await authorizationService.requestReadAuthorization(for: [.steps])
      Issue.record("Expected authorization error")
    } catch {
      #expect(error as? FakeMetricQueryError == .authorizationDenied)
    }

    let queryService = FakeMetricQueryService()
    await queryService.setQueryError(.queryFailed)
    let definition = try #require(MetricRegistry[.steps])
    do {
      _ = try await queryService.currentReading(
        for: definition,
        now: .now,
        calendar: Calendar(identifier: .gregorian)
      )
      Issue.record("Expected query error")
    } catch {
      #expect(error as? FakeMetricQueryError == .queryFailed)
    }
  }

  @Test("Fake respects structured cancellation")
  func cancellation() async throws {
    let service = FakeMetricQueryService()
    let definition = try #require(MetricRegistry[.steps])
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await service.currentReading(
        for: definition,
        now: .now,
        calendar: Calendar(identifier: .gregorian)
      )
    }

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
}

extension FakeMetricQueryService {
  fileprivate func setAuthorizationError(_ error: FakeMetricQueryError?) {
    authorizationError = error
  }

  fileprivate func setQueryError(_ error: FakeMetricQueryError?) {
    queryError = error
  }
}
