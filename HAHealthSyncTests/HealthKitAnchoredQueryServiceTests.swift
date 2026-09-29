import Foundation
import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitAnchoredQueryServiceTests: XCTestCase {
  func testReturnsIDsAndCandidateWithoutPersisting() async throws {
    let committed = try HealthKitAnchorCodec.encode(HKQueryAnchor(fromValue: 4))
    let candidate = HKQueryAnchor(fromValue: 8)
    let added = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let deleted = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let client = FakeAnchoredQueryClient(
      result: HealthKitAnchoredResult(
        addedSampleIDs: [added],
        deletedSampleIDs: [deleted],
        newAnchor: candidate
      )
    )
    let service = HealthKitAnchoredQueryService(client: client)

    let changes = try await service.changes(for: .steps, committedAnchor: committed)

    XCTAssertTrue(changes.hasChanges)
    XCTAssertEqual(changes.addedSampleIDs, [added])
    XCTAssertEqual(changes.deletedSampleIDs, [deleted])
    XCTAssertNoThrow(try HealthKitAnchorCodec.decode(changes.candidateAnchor))
    let request = await client.request
    XCTAssertEqual(request?.typeIdentifier, HKQuantityTypeIdentifier.stepCount.rawValue)
    XCTAssertNotNil(request?.anchorData)
  }

  func testInitialEmptyResultStillReturnsACommittableCandidate() async throws {
    let client = FakeAnchoredQueryClient(
      result: HealthKitAnchoredResult(
        addedSampleIDs: [],
        deletedSampleIDs: [],
        newAnchor: HKQueryAnchor(fromValue: 1)
      )
    )
    let service = HealthKitAnchoredQueryService(client: client)

    let changes = try await service.changes(for: .bodyMass, committedAnchor: nil)

    XCTAssertFalse(changes.hasChanges)
    XCTAssertFalse(changes.candidateAnchor.isEmpty)
    let request = await client.request
    XCTAssertNil(request?.anchorData)
  }

  func testInvalidCommittedAnchorNeverRunsAQuery() async throws {
    let client = FakeAnchoredQueryClient(
      result: HealthKitAnchoredResult(
        addedSampleIDs: [],
        deletedSampleIDs: [],
        newAnchor: HKQueryAnchor(fromValue: 1)
      )
    )
    let service = HealthKitAnchoredQueryService(client: client)

    do {
      _ = try await service.changes(
        for: .steps,
        committedAnchor: Data("corrupt".utf8)
      )
      XCTFail("Expected invalid archive")
    } catch {
      XCTAssertEqual(error as? HealthKitAnchorCodecError, .invalidArchive)
    }
    let request = await client.request
    XCTAssertNil(request)
  }

  func testLockedHealthKitDatabaseMapsToRecoverableChangeQueryError() async {
    let client = FailingAnchoredQueryClient(
      error: NSError(
        domain: HKErrorDomain,
        code: HKError.Code.errorDatabaseInaccessible.rawValue
      )
    )
    let service = HealthKitAnchoredQueryService(client: client)

    do {
      _ = try await service.changes(for: .steps, committedAnchor: nil)
      XCTFail("Expected the locked HealthKit database to defer the query")
    } catch {
      XCTAssertEqual(error as? MetricChangeQueryError, .databaseInaccessible)
    }
  }
}

private struct FailingAnchoredQueryClient: HealthKitAnchoredQueryClient {
  let error: any Error & Sendable

  func changes(
    for sampleType: HKSampleType,
    anchor: HKQueryAnchor?
  ) throws -> HealthKitAnchoredResult {
    throw error
  }
}

private actor FakeAnchoredQueryClient: HealthKitAnchoredQueryClient {
  struct Request: Sendable {
    let typeIdentifier: String
    let anchorData: Data?
  }

  let result: HealthKitAnchoredResult
  private(set) var request: Request?

  init(result: HealthKitAnchoredResult) {
    self.result = result
  }

  func changes(
    for sampleType: HKSampleType,
    anchor: HKQueryAnchor?
  ) throws -> HealthKitAnchoredResult {
    try Task.checkCancellation()
    request = Request(
      typeIdentifier: sampleType.identifier,
      anchorData: try anchor.map(HealthKitAnchorCodec.encode)
    )
    return result
  }
}
