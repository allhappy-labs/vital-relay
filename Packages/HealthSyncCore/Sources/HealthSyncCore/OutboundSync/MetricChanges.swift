import Foundation

public enum MetricChangeQueryError: Error, Sendable, Equatable {
  case databaseInaccessible
}

public struct MetricChanges: Sendable, Equatable {
  public let hasChanges: Bool
  public let addedSampleIDs: [UUID]
  public let deletedSampleIDs: [UUID]
  public let candidateAnchor: Data

  public init(
    addedSampleIDs: [UUID],
    deletedSampleIDs: [UUID],
    candidateAnchor: Data
  ) {
    hasChanges = !addedSampleIDs.isEmpty || !deletedSampleIDs.isEmpty
    self.addedSampleIDs = addedSampleIDs
    self.deletedSampleIDs = deletedSampleIDs
    self.candidateAnchor = candidateAnchor
  }
}

public protocol MetricChangeQuerying: Sendable {
  func changes(
    for metric: MetricID,
    committedAnchor: Data?
  ) async throws -> MetricChanges
}
