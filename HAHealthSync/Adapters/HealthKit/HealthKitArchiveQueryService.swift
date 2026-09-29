import Foundation
import HealthKit
import HealthSyncCore

struct HealthKitArchiveQueryResult: Sendable {
  let samples: [HKSample]
  let deletedSampleIDs: [UUID]
  let anchor: HKQueryAnchor
}

protocol HealthKitArchiveQueryClient: Sendable {
  func authorizationBoundaries(types: Set<HealthObjectTypeID>) async throws -> [HealthObjectTypeID:
    Date]
  func oldestSampleDate(type: HealthObjectTypeID, lowerBound: Date?, metric: MetricID?) async throws
    -> Date?
  func changes(
    type: HealthObjectTypeID, interval: DateInterval?, anchor: HKQueryAnchor?, limit: Int
  ) async throws -> HealthKitArchiveQueryResult
}

struct HealthKitArchiveQueryService: HealthArchiveQuerying {
  private let client: any HealthKitArchiveQueryClient
  private let mapper: HealthKitArchiveSampleMapper
  private let changePageLimit: Int
  private static let windowDuration: TimeInterval = 30 * 86400

  init(
    client: any HealthKitArchiveQueryClient = HKHealthStoreArchiveQueryClient(),
    applicationBundleID: String = Bundle.main.bundleIdentifier
      ?? "com.marynavdovenko.HAHealthSync", changePageLimit: Int = 500
  ) {
    self.client = client
    mapper = HealthKitArchiveSampleMapper(applicationBundleID: applicationBundleID)
    self.changePageLimit = min(max(changePageLimit, 1), 1000)
  }

  func discover(types: Set<HealthObjectTypeID>) async throws -> [HealthObjectTypeID:
    ReadableHistory]
  {
    do {
      try Task.checkCancellation()
      let boundaries = try await client.authorizationBoundaries(types: types)
      var result: [HealthObjectTypeID: ReadableHistory] = [:]
      for type in types.sorted(by: { $0.rawValue < $1.rawValue }) {
        try Task.checkCancellation()
        let earliest = try await client.oldestSampleDate(
          type: type, lowerBound: boundaries[type], metric: nil)
        result[type] = Self.history(earliest: earliest, boundary: boundaries[type])
      }
      return result
    } catch { throw Self.classified(error) }
  }

  func discover(metrics: [MetricDefinition]) async throws -> ArchiveHistoryDiscovery {
    do {
      let supported = metrics.filter { $0.availability == .available }
      let types = try await discover(types: Set(supported.map(\.healthObjectType)))
      var metricHistory: [MetricID: ReadableHistory] = [:]
      for metric in supported {
        try Task.checkCancellation()
        guard metric.healthObjectType == .sleepAnalysis else {
          metricHistory[metric.id] = types[metric.healthObjectType]
          continue
        }
        let boundary: Date?
        switch types[metric.healthObjectType] {
        case .readable(_, let value), .noReadableSamples(let value): boundary = value
        case nil: boundary = nil
        }
        let earliest = try await client.oldestSampleDate(
          type: metric.healthObjectType, lowerBound: boundary, metric: metric.id)
        metricHistory[metric.id] = Self.history(earliest: earliest, boundary: boundary)
      }
      return ArchiveHistoryDiscovery(types: types, metrics: metricHistory)
    } catch { throw Self.classified(error) }
  }

  func page(
    type: HealthObjectTypeID, interval: DateInterval, cursor: ArchiveScanCursor?, limit: Int
  ) async throws -> ArchiveSamplePage {
    try Task.checkCancellation()
    guard interval.duration > 0, interval.duration.isFinite, (1...1000).contains(limit) else {
      throw ArchiveValidationError.invalidRequest
    }
    let start = cursor?.windowStart ?? interval.start
    let end = cursor?.windowEnd ?? min(start.addingTimeInterval(Self.windowDuration), interval.end)
    if let cursor {
      guard cursor.type == type, cursor.interval == interval, start >= interval.start, start < end,
        end <= interval.end, end.timeIntervalSince(start) <= Self.windowDuration
      else { throw ArchiveValidationError.invalidRequest }
    }
    let window = DateInterval(start: start, end: end)
    let result = try await changeResult(
      type: type, interval: window, anchor: cursor?.anchor, limit: limit)
    try Task.checkCancellation()
    let complete = result.samples.count + result.deletedSampleIDs.count < limit
    let next: ArchiveScanCursor?
    if !complete {
      next = ArchiveScanCursor(
        type: type, interval: interval, windowStart: start, windowEnd: end,
        anchor: try HealthKitAnchorCodec.encode(result.anchor))
    } else if end < interval.end {
      next = ArchiveScanCursor(
        type: type, interval: interval, windowStart: end,
        windowEnd: min(end.addingTimeInterval(Self.windowDuration), interval.end), anchor: nil)
    } else {
      next = nil
    }
    return ArchiveSamplePage(
      samples: try result.samples.compactMap { try mapper.map($0, type: type) },
      deletedSampleIDs: result.deletedSampleIDs, coveredInterval: window,
      isWindowComplete: complete, nextCursor: next)
  }

  func changes(type: HealthObjectTypeID, anchor: Data?) async throws -> ArchiveChangePage {
    try Task.checkCancellation()
    let result = try await changeResult(
      type: type, interval: nil, anchor: anchor, limit: changePageLimit)
    try Task.checkCancellation()
    return ArchiveChangePage(
      samples: try result.samples.compactMap { try mapper.map($0, type: type) },
      deletedSampleIDs: result.deletedSampleIDs,
      candidateAnchor: try HealthKitAnchorCodec.encode(result.anchor),
      hasMore: result.samples.count + result.deletedSampleIDs.count >= changePageLimit)
  }

  private static func history(earliest: Date?, boundary: Date?) -> ReadableHistory {
    earliest.map { .readable(earliest: $0, authorizationBoundary: boundary) }
      ?? .noReadableSamples(authorizationBoundary: boundary)
  }

  private func changeResult(
    type: HealthObjectTypeID, interval: DateInterval?, anchor: Data?, limit: Int
  ) async throws -> HealthKitArchiveQueryResult {
    do {
      let decoded = try anchor.map(HealthKitAnchorCodec.decode)
      return try await client.changes(type: type, interval: interval, anchor: decoded, limit: limit)
    } catch is HealthKitAnchorCodecError {
      throw ArchiveQueryError.anchorInvalidated
    } catch {
      throw Self.classified(error, hasAnchor: anchor != nil)
    }
  }

  private static func classified(_ error: any Error, hasAnchor: Bool = false) -> any Error {
    let failure = error as NSError
    guard failure.domain == HKErrorDomain else { return error }
    switch failure.code {
    case HKError.Code.errorDatabaseInaccessible.rawValue: return ArchiveQueryError.deviceLocked
    case HKError.Code.errorAuthorizationDenied.rawValue:
      return ArchiveQueryError.permissionRestricted
    case HKError.Code.errorInvalidArgument.rawValue where hasAnchor:
      return ArchiveQueryError.anchorInvalidated
    default: return error
    }
  }
}

final class HKHealthStoreArchiveQueryClient: HealthKitArchiveQueryClient, @unchecked Sendable {
  private let store: HKHealthStore
  init(store: HKHealthStore = HKHealthStore()) { self.store = store }

  func authorizationBoundaries(types: Set<HealthObjectTypeID>) async throws -> [HealthObjectTypeID:
    Date]
  {
    let resolved = try Dictionary(
      uniqueKeysWithValues: types.map { ($0, try HealthKitTypeResolver.objectType(for: $0)) })
    if #available(iOS 27.0, *) {
      let boundaries: [HKObjectType: Date] = try await withCheckedThrowingContinuation {
        continuation in
        store.getEarliestAuthorizedSampleDate(for: Set(resolved.values)) { dates, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let dates {
            continuation.resume(returning: dates)
          } else {
            continuation.resume(throwing: ArchiveValidationError.invalidResponse)
          }
        }
      }
      // The archive workout type uses a wire alias, so map through the resolver rather
      // than assuming HealthKit identifiers equal every domain raw value.
      return resolved.compactMapValues { boundaries[$0] }
    }
    return [:]
  }

  func oldestSampleDate(type: HealthObjectTypeID, lowerBound: Date?, metric: MetricID?) async throws
    -> Date?
  {
    let sampleType = try Self.sampleType(type)
    var predicates = [HealthKitOriginMetadata.outboundPredicate]
    if let lowerBound {
      predicates.append(
        HKQuery.predicateForSamples(withStart: lowerBound, end: nil, options: .strictStartDate))
    }
    if let metric, let stages = Self.sleepValues(metric: metric) {
      predicates.append(
        NSCompoundPredicate(
          orPredicateWithSubpredicates: stages.map {
            HKQuery.predicateForCategorySamples(with: .equalTo, value: $0)
          }))
    }
    return try await withCheckedThrowingContinuation { continuation in
      // HealthKit sorts in its database; only one original is materialized, even for decades of history.
      let query = HKSampleQuery(
        sampleType: sampleType,
        predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates), limit: 1,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
      ) { _, samples, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: samples?.first?.startDate)
        }
      }
      store.execute(query)
    }
  }

  func changes(
    type: HealthObjectTypeID, interval: DateInterval?, anchor: HKQueryAnchor?, limit: Int
  ) async throws -> HealthKitArchiveQueryResult {
    guard (1...1000).contains(limit) else { throw ArchiveValidationError.invalidRequest }
    let sampleType = try Self.sampleType(type)
    var predicates = [HealthKitOriginMetadata.outboundPredicate]
    // Overlapping windows retain crossing intervals and boundary ties; archive UUID keys deduplicate.
    if let interval {
      predicates.append(
        HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: []))
    }
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKAnchoredObjectQuery(
        type: sampleType, predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
        anchor: anchor, limit: limit
      ) { _, samples, deleted, next, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let next else {
          continuation.resume(throwing: HealthKitAnchoredQueryError.missingAnchor)
          return
        }
        continuation.resume(
          returning: HealthKitArchiveQueryResult(
            samples: samples ?? [], deletedSampleIDs: (deleted ?? []).map(\.uuid), anchor: next))
      }
      store.execute(query)
    }
  }

  private static func sampleType(_ type: HealthObjectTypeID) throws -> HKSampleType {
    guard let resolved = try HealthKitTypeResolver.objectType(for: type) as? HKSampleType else {
      throw HealthKitMetricQueryError.unsupportedMetric
    }
    return resolved
  }

  static func sleepValues(metric: MetricID) -> [Int]? {
    switch metric {
    case .sleepREM: return [HKCategoryValueSleepAnalysis.asleepREM.rawValue]
    case .sleepDeep: return [HKCategoryValueSleepAnalysis.asleepDeep.rawValue]
    case .sleepCore: return [HKCategoryValueSleepAnalysis.asleepCore.rawValue]
    case .sleepAwake: return [HKCategoryValueSleepAnalysis.awake.rawValue]
    case .sleepUnspecified: return [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
    case .sleepDuration, .asleepTime, .wakeTime: return [1, 3, 4, 5]
    default: return nil
    }
  }
}
