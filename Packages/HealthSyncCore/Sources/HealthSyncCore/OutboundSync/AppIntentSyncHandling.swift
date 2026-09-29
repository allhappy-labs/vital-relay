public protocol AppIntentSyncHandling: Sendable {
  func synchronize() async -> AppIntentSyncResult
}

public struct AppIntentSyncResult: Codable, Sendable, Equatable {
  public let succeeded: Bool
  public let synchronizedMetricCount: Int
  public let synchronizedPairingCount: Int
  public let failureCategory: SyncFailureCategory?
  public let requiresPurchase: Bool

  public init(
    succeeded: Bool,
    synchronizedMetricCount: Int,
    synchronizedPairingCount: Int = 0,
    failureCategory: SyncFailureCategory?,
    requiresPurchase: Bool = false
  ) {
    self.succeeded = succeeded
    self.synchronizedMetricCount = synchronizedMetricCount
    self.synchronizedPairingCount = synchronizedPairingCount
    self.failureCategory = failureCategory
    self.requiresPurchase = requiresPurchase
  }
}

public actor AppIntentSyncHandler: AppIntentSyncHandling {
  private let coordinator: any BidirectionalSyncCoordinating

  public init(coordinator: any BidirectionalSyncCoordinating) {
    self.coordinator = coordinator
  }

  public func synchronize() async -> AppIntentSyncResult {
    let outcome = await coordinator.sync(trigger: .shortcut)
    if case .requiresPurchase = outcome {
      return AppIntentSyncResult(
        succeeded: false,
        synchronizedMetricCount: 0,
        failureCategory: nil,
        requiresPurchase: true
      )
    }
    guard case .performed(let report) = outcome else {
      return AppIntentSyncResult(
        succeeded: false,
        synchronizedMetricCount: 0,
        failureCategory: .unknown
      )
    }

    let metricCount = report.outbound?.synchronizedMetrics ?? 0
    let pairingCount = report.inbound?.savedPairings ?? 0
    // `deviceLocked` is reported only when it is the sole failure; any other failure is more
    // actionable for the Shortcut result.
    let categories = report.failureCategories
    if let failure = categories.first(where: { $0 != .deviceLocked }) ?? categories.first {
      return AppIntentSyncResult(
        succeeded: false,
        synchronizedMetricCount: metricCount,
        synchronizedPairingCount: pairingCount,
        failureCategory: failure
      )
    }
    return AppIntentSyncResult(
      succeeded: true,
      synchronizedMetricCount: metricCount,
      synchronizedPairingCount: pairingCount,
      failureCategory: nil
    )
  }
}
