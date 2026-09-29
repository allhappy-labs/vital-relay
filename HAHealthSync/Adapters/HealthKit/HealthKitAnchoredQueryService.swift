import Foundation
import HealthKit
import HealthSyncCore

enum HealthKitAnchoredQueryError: Error, Equatable, Sendable {
  case unsupportedMetric
  case missingAnchor
}

struct HealthKitAnchoredResult: Sendable {
  let addedSampleIDs: [UUID]
  let deletedSampleIDs: [UUID]
  let newAnchor: HKQueryAnchor
}

protocol HealthKitAnchoredQueryClient: Sendable {
  func changes(
    for sampleType: HKSampleType,
    anchor: HKQueryAnchor?
  ) async throws -> HealthKitAnchoredResult
}

struct HealthKitAnchoredQueryService: Sendable {
  private let client: any HealthKitAnchoredQueryClient

  init(client: any HealthKitAnchoredQueryClient) {
    self.client = client
  }

  func changes(
    for metric: MetricID,
    committedAnchor: Data?
  ) async throws -> MetricChanges {
    try Task.checkCancellation()
    guard let definition = MetricRegistry[metric],
      let sampleType = try HealthKitTypeResolver.objectType(
        for: definition.healthObjectType
      ) as? HKSampleType
    else {
      throw HealthKitAnchoredQueryError.unsupportedMetric
    }
    let anchor = try committedAnchor.map(HealthKitAnchorCodec.decode)
    let result: HealthKitAnchoredResult
    do {
      result = try await client.changes(for: sampleType, anchor: anchor)
    } catch {
      let nsError = error as NSError
      if nsError.domain == HKErrorDomain,
        nsError.code == HKError.Code.errorDatabaseInaccessible.rawValue
      {
        throw MetricChangeQueryError.databaseInaccessible
      }
      throw error
    }
    try Task.checkCancellation()
    return MetricChanges(
      addedSampleIDs: result.addedSampleIDs,
      deletedSampleIDs: result.deletedSampleIDs,
      candidateAnchor: try HealthKitAnchorCodec.encode(result.newAnchor)
    )
  }
}

extension HealthKitAnchoredQueryService: MetricChangeQuerying {}

final class HKHealthStoreAnchoredQueryClient: HealthKitAnchoredQueryClient, @unchecked Sendable {
  private let healthStore: HKHealthStore

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func changes(
    for sampleType: HKSampleType,
    anchor: HKQueryAnchor?
  ) async throws -> HealthKitAnchoredResult {
    try await withCheckedThrowingContinuation { continuation in
      let query = HKAnchoredObjectQuery(
        type: sampleType,
        predicate: nil,
        anchor: anchor,
        limit: HKObjectQueryNoLimit
      ) { _, samples, deletedObjects, newAnchor, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let newAnchor else {
          continuation.resume(throwing: HealthKitAnchoredQueryError.missingAnchor)
          return
        }
        continuation.resume(
          returning: HealthKitAnchoredResult(
            addedSampleIDs: (samples ?? []).map(\.uuid),
            deletedSampleIDs: (deletedObjects ?? []).map(\.uuid),
            newAnchor: newAnchor
          )
        )
      }
      healthStore.execute(query)
    }
  }
}
