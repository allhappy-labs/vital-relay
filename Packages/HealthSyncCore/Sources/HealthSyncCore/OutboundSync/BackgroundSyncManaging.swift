public protocol BackgroundSyncManaging: Sendable {
  func reconcile(enabled: Bool, metrics: Set<MetricID>) async
  func stopAll() async
  func registrationStates() async -> [MetricID: BackgroundRegistrationState]
}
