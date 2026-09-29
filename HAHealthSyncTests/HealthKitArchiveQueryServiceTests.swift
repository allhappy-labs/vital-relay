import Foundation
import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitArchiveQueryServiceTests: XCTestCase {
  func testArchiveErrorsDistinguishLockedDatabaseAndInvalidAnchor() async throws {
    let client = ArchiveQueryFake()
    let service = HealthKitArchiveQueryService(client: client)
    await client.setFailure(
      NSError(domain: HKErrorDomain, code: HKError.Code.errorDatabaseInaccessible.rawValue))
    do {
      _ = try await service.changes(type: .stepCount, anchor: nil)
      XCTFail("Expected lock failure")
    } catch { XCTAssertEqual(error as? ArchiveQueryError, .deviceLocked) }
    await client.setFailure(
      NSError(domain: HKErrorDomain, code: HKError.Code.errorInvalidArgument.rawValue))
    let anchor = try HealthKitAnchorCodec.encode(HKQueryAnchor(fromValue: 1))
    do {
      _ = try await service.changes(type: .stepCount, anchor: anchor)
      XCTFail("Expected anchor failure")
    } catch { XCTAssertEqual(error as? ArchiveQueryError, .anchorInvalidated) }
    do {
      _ = try await service.changes(type: .stepCount, anchor: Data())
      XCTFail("Expected corrupt anchor failure")
    } catch { XCTAssertEqual(error as? ArchiveQueryError, .anchorInvalidated) }
  }

  func testDiscoveryReportsLockedDatabaseWithoutInferringPermission() async throws {
    let client = ArchiveQueryFake()
    await client.setFailure(
      NSError(domain: HKErrorDomain, code: HKError.Code.errorDatabaseInaccessible.rawValue))
    do {
      _ = try await HealthKitArchiveQueryService(client: client).discover(types: [.stepCount])
      XCTFail("Expected locked discovery")
    } catch { XCTAssertEqual(error as? ArchiveQueryError, .deviceLocked) }
  }
  func testLimitedBoundaryWithNoSamplesStaysExplicitlyAmbiguous() async throws {
    let client = ArchiveQueryFake()
    let boundary = Date(timeIntervalSince1970: 100)
    await client.configure(boundaries: [.stepCount: boundary], oldest: [:])
    let result = try await HealthKitArchiveQueryService(client: client).discover(types: [.stepCount]
    )
    XCTAssertEqual(result[.stepCount], .noReadableSamples(authorizationBoundary: boundary))
  }

  func testFilteredFullPageStillAdvancesAnchorBeforeReportingWindowComplete() async throws {
    let date = Date(timeIntervalSince1970: 100)
    let sample = HKQuantitySample(
      type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 1),
      start: date, end: date)
    let service = HealthKitArchiveQueryService(
      client: ArchiveQueryFake(samples: [sample]),
      applicationBundleID: sample.sourceRevision.source.bundleIdentifier)
    let page = try await service.page(
      type: .stepCount, interval: DateInterval(start: date, duration: 10), cursor: nil, limit: 1)
    XCTAssertTrue(page.samples.isEmpty)
    XCTAssertFalse(page.isWindowComplete)
    XCTAssertNotNil(page.nextCursor?.anchor)
  }

  func testCursorCannotBeReusedAcrossTypeOrInterval() async throws {
    let interval = DateInterval(start: Date(timeIntervalSince1970: 100), duration: 10)
    let cursor = ArchiveScanCursor(
      type: .bodyMass, interval: interval, windowStart: interval.start, windowEnd: interval.end,
      anchor: nil)
    do {
      _ = try await HealthKitArchiveQueryService(client: ArchiveQueryFake()).page(
        type: .stepCount, interval: interval, cursor: cursor, limit: 10)
      XCTFail("Expected mismatched cursor rejection")
    } catch { XCTAssertEqual(error as? ArchiveValidationError, .invalidRequest) }
  }

  func testDiscoveryKeepsLimitedAndAmbiguousTypeDatesIndependent() async throws {
    let client = ArchiveQueryFake()
    let boundary = Date(timeIntervalSince1970: 100)
    await client.configure(
      boundaries: [.stepCount: boundary],
      oldest: [.stepCount: boundary, .bodyMass: Date(timeIntervalSince1970: 10)])
    let service = HealthKitArchiveQueryService(client: client)
    let result = try await service.discover(types: [.stepCount, .bodyMass, .sleepAnalysis])
    XCTAssertEqual(
      result[.stepCount], .readable(earliest: boundary, authorizationBoundary: boundary))
    XCTAssertEqual(
      result[.bodyMass],
      .readable(earliest: Date(timeIntervalSince1970: 10), authorizationBoundary: nil))
    XCTAssertEqual(result[.sleepAnalysis], .noReadableSamples(authorizationBoundary: nil))
    let requests = await client.oldestRequests
    XCTAssertEqual(requests.first { $0.type == .stepCount }?.lowerBound, boundary)
  }

  func testSharedSleepTypeHasIndependentMetricEarliestDates() async throws {
    let client = ArchiveQueryFake()
    await client.configureMetrics([
      .sleepREM: Date(timeIntervalSince1970: 40), .sleepDeep: Date(timeIntervalSince1970: 20),
    ])
    let service = HealthKitArchiveQueryService(client: client)
    let result = try await service.discover(
      metrics: [.sleepREM, .sleepDeep].compactMap { MetricRegistry[$0] })
    XCTAssertEqual(result.types.count, 1)
    XCTAssertEqual(
      result.metrics[.sleepREM],
      .readable(earliest: Date(timeIntervalSince1970: 40), authorizationBoundary: nil))
    XCTAssertEqual(
      result.metrics[.sleepDeep],
      .readable(earliest: Date(timeIntervalSince1970: 20), authorizationBoundary: nil))
  }

  func testDenseWindowUsesBoundedAnchorPagesAndPreservesTimestampTies() async throws {
    let date = Date(timeIntervalSince1970: 100)
    let samples = (0..<5).map { _ in
      HKQuantitySample(
        type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 1),
        start: date, end: date)
    }
    let client = ArchiveQueryFake(samples: samples)
    let service = HealthKitArchiveQueryService(client: client, applicationBundleID: "other.app")
    let interval = DateInterval(start: date, duration: 10)
    var cursor: ArchiveScanCursor?
    var ids: [String] = []
    repeat {
      let page = try await service.page(
        type: .stepCount, interval: interval, cursor: cursor, limit: 2)
      ids += page.samples.map(\.uuid)
      cursor = page.nextCursor
    } while cursor != nil
    XCTAssertEqual(Set(ids), Set(samples.map { $0.uuid.uuidString.lowercased() }))
    XCTAssertEqual(ids.count, 5)
    let requests = await client.changeRequests
    XCTAssertTrue(requests.allSatisfy { $0.limit == 2 })
    XCTAssertEqual(requests.count, 3)
  }

  func testSparseMultiyearQueryAdvancesOnlyOneBoundedWindow() async throws {
    let client = ArchiveQueryFake()
    let service = HealthKitArchiveQueryService(client: client)
    let interval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 365 * 86400 * 10)
    let page = try await service.page(type: .stepCount, interval: interval, cursor: nil, limit: 20)
    XCTAssertEqual(page.coveredInterval.duration, 30 * 86400)
    XCTAssertNotNil(page.nextCursor)
    let requests = await client.changeRequests
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.interval?.duration, 30 * 86400)
  }

  func testChangesReturnBoundedCandidateAndDeletionIDs() async throws {
    let deleted = UUID()
    let client = ArchiveQueryFake(deleted: [deleted])
    let result = try await HealthKitArchiveQueryService(client: client, changePageLimit: 2).changes(
      type: .stepCount, anchor: nil)
    XCTAssertEqual(result.deletedSampleIDs, [deleted])
    XCTAssertFalse(result.hasMore)
    XCTAssertNoThrow(try HealthKitAnchorCodec.decode(result.candidateAnchor))
  }
}

private actor ArchiveQueryFake: HealthKitArchiveQueryClient {
  struct OldestRequest {
    let type: HealthObjectTypeID
    let lowerBound: Date?
  }
  struct ChangeRequest {
    let interval: DateInterval?
    let limit: Int
  }
  var oldestRequests: [OldestRequest] = []
  var changeRequests: [ChangeRequest] = []
  var boundaries: [HealthObjectTypeID: Date] = [:]
  var oldest: [HealthObjectTypeID: Date] = [:]
  var metrics: [MetricID: Date] = [:]
  let samples: [HKSample]
  let deleted: [UUID]
  var offset = 0
  var failure: NSError?
  func setFailure(_ value: NSError?) { failure = value }
  init(samples: [HKSample] = [], deleted: [UUID] = []) {
    self.samples = samples
    self.deleted = deleted
  }
  func configure(boundaries: [HealthObjectTypeID: Date], oldest: [HealthObjectTypeID: Date]) {
    self.boundaries = boundaries
    self.oldest = oldest
  }
  func configureMetrics(_ metrics: [MetricID: Date]) { self.metrics = metrics }
  func authorizationBoundaries(types: Set<HealthObjectTypeID>) async throws -> [HealthObjectTypeID:
    Date]
  {
    if let failure { throw failure }
    return boundaries
  }
  func oldestSampleDate(type: HealthObjectTypeID, lowerBound: Date?, metric: MetricID?) async throws
    -> Date?
  {
    oldestRequests.append(OldestRequest(type: type, lowerBound: lowerBound))
    return metric.flatMap { metrics[$0] } ?? oldest[type]
  }
  func changes(
    type: HealthObjectTypeID, interval: DateInterval?, anchor: HKQueryAnchor?, limit: Int
  ) async throws -> HealthKitArchiveQueryResult {
    if let failure { throw failure }
    changeRequests.append(ChangeRequest(interval: interval, limit: limit))
    let page = Array(samples.dropFirst(offset).prefix(limit))
    offset += page.count
    return HealthKitArchiveQueryResult(
      samples: page, deletedSampleIDs: deleted,
      anchor: HKQueryAnchor(fromValue: offset + deleted.count))
  }
}
