import Foundation

public struct InboundSyncFailure: Codable, Sendable, Equatable {
  public let pairingID: UUID?
  public let category: SyncFailureCategory

  public init(pairingID: UUID?, category: SyncFailureCategory) {
    self.pairingID = pairingID
    self.category = category
  }
}

public struct InboundSyncReport: Codable, Sendable, Equatable {
  public let trigger: SyncTrigger
  public let attemptedPairings: Int
  public let savedPairings: Int
  public let skippedPairings: Int
  public let failures: [InboundSyncFailure]
  public let startedAt: Date
  public let finishedAt: Date

  public init(
    trigger: SyncTrigger,
    attemptedPairings: Int,
    savedPairings: Int,
    skippedPairings: Int,
    failures: [InboundSyncFailure],
    startedAt: Date,
    finishedAt: Date
  ) {
    self.trigger = trigger
    self.attemptedPairings = attemptedPairings
    self.savedPairings = savedPairings
    self.skippedPairings = skippedPairings
    self.failures = failures
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }
}

public protocol InboundSyncCoordinating: Sendable {
  func sync(trigger: SyncTrigger) async -> InboundSyncReport
  func sync(trigger: SyncTrigger, deadline: ExecutionDeadline?) async -> InboundSyncReport
}

extension InboundSyncCoordinating {
  public func sync(trigger: SyncTrigger, deadline: ExecutionDeadline?) async -> InboundSyncReport {
    await sync(trigger: trigger)
  }
}
