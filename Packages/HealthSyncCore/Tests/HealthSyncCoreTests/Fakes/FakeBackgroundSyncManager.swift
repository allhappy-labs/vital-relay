@testable import HealthSyncCore

actor FakeBackgroundSyncManager: BackgroundSyncManaging {
  private(set) var reconciliations: [(enabled: Bool, metrics: Set<MetricID>)] = []
  private(set) var stopCount = 0
  var states: [MetricID: BackgroundRegistrationState] = [:]

  func reconcile(enabled: Bool, metrics: Set<MetricID>) {
    reconciliations.append((enabled, metrics))
  }

  func stopAll() {
    stopCount += 1
  }

  func registrationStates() -> [MetricID: BackgroundRegistrationState] {
    states
  }
}
