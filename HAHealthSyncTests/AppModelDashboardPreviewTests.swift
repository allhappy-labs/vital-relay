import Foundation
import HealthSyncCore
import XCTest

@testable import HAHealthSync

@MainActor
final class AppModelDashboardPreviewTests: XCTestCase {
  func testPreviewReadsOnlySelectedMetricsAndKeepsSuccessfulValues() async {
    let now = Date(timeIntervalSince1970: 1_788_052_800)
    let query = DashboardPreviewMetricQuery(results: [
      .steps: .success(MetricReading(metricID: .steps, timestamp: now, value: 246)),
      .heartRate: .success(MetricReading(metricID: .heartRate, timestamp: now, value: 72)),
    ])
    let configuration = AppConfiguration(
      baseURL: "https://example.invalid",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [.steps, .heartRate],
      backgroundSyncEnabled: false
    )
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      metricQuery: query,
      initialConfiguration: configuration,
      isOnboardingComplete: true
    )

    await model.refreshDashboardPreview(now: now, calendar: .current)

    let requestedMetricIDs = await query.requestedMetricIDs
    XCTAssertEqual(requestedMetricIDs, [.heartRate, .steps])
    XCTAssertEqual(model.dashboardPreview.readings[.steps]?.value, 246)
    XCTAssertEqual(model.dashboardPreview.readings[.heartRate]?.value, 72)
    XCTAssertEqual(model.dashboardPreview.refreshedAt, now)
    XCTAssertFalse(model.dashboardPreview.isLoading)
  }

  func testPreviewRetainsSuccessfulValuesAndCategorizesFailures() async {
    let now = Date(timeIntervalSince1970: 1_788_052_800)
    let query = DashboardPreviewMetricQuery(results: [
      .steps: .success(MetricReading(metricID: .steps, timestamp: now, value: 246)),
      .heartRate: .failure(.unauthorized),
    ])
    let model = AppModel(
      bidirectionalSyncCoordinator: nil,
      metricQuery: query,
      initialConfiguration: AppConfiguration(
        baseURL: "https://example.invalid",
        allowsConfirmedLocalHTTP: false,
        healthBridgeUserID: "example-user",
        selectedMetrics: [.steps, .heartRate],
        backgroundSyncEnabled: false
      ),
      isOnboardingComplete: true
    )

    await model.refreshDashboardPreview(now: now, calendar: .current)

    XCTAssertEqual(Set(model.dashboardPreview.readings.keys), [.steps])
    XCTAssertEqual(model.dashboardPreview.failureCategories[.heartRate], .unauthorized)
  }
}

private actor DashboardPreviewMetricQuery: MetricQuerying {
  private let results: [MetricID: Result<MetricReading, NetworkFailure>]
  private var requested: [MetricID] = []

  init(results: [MetricID: Result<MetricReading, NetworkFailure>]) {
    self.results = results
  }

  var requestedMetricIDs: [MetricID] {
    requested.sorted { $0.rawValue < $1.rawValue }
  }

  func requestReadAuthorization(for metrics: Set<MetricID>) {}

  func currentReading(
    for definition: MetricDefinition,
    now: Date,
    calendar: Calendar
  ) throws -> MetricReading? {
    requested.append(definition.id)
    return try results[definition.id]?.get()
  }
}
