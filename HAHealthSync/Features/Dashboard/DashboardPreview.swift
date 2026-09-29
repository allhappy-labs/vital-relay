import Foundation
import HealthSyncCore

struct DashboardPreviewState: Equatable, Sendable {
  var readings: [MetricID: MetricReading] = [:]
  var failureCategories: [MetricID: SyncFailureCategory] = [:]
  var isLoading = false
  var refreshedAt: Date?

  var readyCount: Int { readings.count }

  func readableCount(in category: MetricCategory) -> Int {
    readings.keys.reduce(into: 0) { count, metricID in
      if MetricRegistry[metricID]?.category == category {
        count += 1
      }
    }
  }
}
