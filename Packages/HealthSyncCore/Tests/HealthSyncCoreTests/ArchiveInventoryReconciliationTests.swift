import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Archive inventory protocol")
struct ArchiveInventoryProtocolTests {
  let baseURL = try! NormalizedBaseURL.parse(
    "https://ha.example.invalid/prefix", allowConfirmedLocalHTTP: false)

  @Test func inventoryUsesCanonicalHALRequestAndStrictPage() async throws {
    let fixture = try #require(
      JSONSerialization.jsonObject(with: fixtureData(named: "archive-inventory-v2"))
        as? [String: Any])
    let query = try JSONDecoder().decode(
      ArchiveInventoryQuery.self, from: JSONSerialization.data(withJSONObject: fixture["request"]!))
    let transport = StubHTTPTransport(
      responseData: try JSONSerialization.data(withJSONObject: fixture["response"]!))
    let client = HealthBridgeArchiveClient(
      transport: transport, userID: "person-1", token: "secret",
      uploaderCredential: String(repeating: "A", count: 43))
    let page = try await client.page(query: query, baseURL: baseURL)
    #expect(page.sampleIDs == ["bd085ccc-22f4-4e80-a865-149bb5b0d1d4"])
    #expect(page.revision == 1)
    let request = try #require(await transport.requests().first)
    #expect(request.url?.path == "/prefix/api/webhook/health_bridge")
    let body = try #require(request.httpBody)
    var expected = try #require(fixture["request"] as? [String: Any])
    expected["token"] = "secret"
    expected["uploader_credential"] = String(repeating: "A", count: 43)
    #expect(
      try JSONSerialization.jsonObject(with: body) as? NSDictionary == expected as NSDictionary)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test func requestBoundsAndConditionalDeletionOnly() throws {
    for limit in [0, 201] {
      #expect(throws: (any Error).self) { try inventoryQuery(limit: limit).validate() }
    }
    #expect(throws: (any Error).self) {
      try inventoryQuery(cursor: String(repeating: "x", count: 2049)).validate()
    }
    var json = try #require(
      JSONSerialization.jsonObject(with: fixtureData(named: "archive-batch-v2")) as? [String: Any])
    json["expected_inventory_revision"] = 1
    #expect(throws: (any Error).self) {
      try ArchiveBatch.decodeValidated(JSONSerialization.data(withJSONObject: json))
    }
  }

  @Test func rejectsMalformedInventoryPages() throws {
    let fixture = try #require(
      JSONSerialization.jsonObject(with: fixtureData(named: "archive-inventory-v2"))
        as? [String: Any])
    let good = try #require(fixture["response"] as? [String: Any])
    for (key, value): (String, Any) in [
      ("revision", -1), ("revision", true), ("revision", "1"),
      ("revision", NSDecimalNumber(string: "9223372036854775808")),
      ("next_cursor", String(repeating: "x", count: 2049)),
      ("next_cursor", "same"), ("sample_ids", ["not-a-uuid"]),
      ("sample_ids", Array(repeating: "bd085ccc-22f4-4e80-a865-149bb5b0d1d4", count: 201)),
      ("request_id", "wrong"), ("protocol_version", 3), ("extra", true),
    ] {
      var bad = good
      bad[key] = value
      #expect(throws: (any Error).self) {
        let page = try JSONDecoder().decode(
          ArchiveInventoryPage.self, from: JSONSerialization.data(withJSONObject: bad))
        try page.validate(query: inventoryQuery(cursor: "same"))
      }
    }
    var missing = good
    missing.removeValue(forKey: "next_cursor")
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        ArchiveInventoryPage.self, from: JSONSerialization.data(withJSONObject: missing))
    }
  }

  @Test func onlyInventoryChangedConflictIsRestartable() async throws {
    for (code, body, expected): (Int, String, ArchiveClientError?) in [
      (409, "{\"ok\":false,\"error\":\"inventory_changed\"}", .inventoryChanged),
      (409, "{\"ok\":false,\"error\":\"batch_conflict\"}", nil),
      (422, "{\"ok\":false,\"error\":\"inventory_changed\"}", nil),
    ] {
      let transport = StubHTTPTransport(responseData: Data(body.utf8), statusCode: code)
      let client = HealthBridgeArchiveClient(
        transport: transport, userID: "person-1", token: "secret",
        uploaderCredential: String(repeating: "A", count: 43))
      do {
        _ = try await client.page(query: inventoryQuery(), baseURL: baseURL)
        Issue.record("Expected inventory failure")
      } catch {
        if let expected {
          #expect(error as? ArchiveClientError == expected)
        } else {
          #expect(error is NetworkFailure)
        }
      }
    }
  }

  private func inventoryQuery(limit: Int = 200, cursor: String? = nil) -> ArchiveInventoryQuery {
    ArchiveInventoryQuery(
      requestID: "request-inventory-001", userID: "person-1",
      sampleType: HealthObjectTypeID.stepCount.rawValue,
      start: "2024-01-01T00:00:00Z", end: "2024-01-02T00:00:00Z", limit: limit, cursor: cursor)
  }
}

@Suite("Archive inventory recovery")
struct ArchiveInventoryRecoveryTests {
  @Test func transferBetweenInventoryPagesRetainsLocalCheckpoint() async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(
      rows: Dictionary(uniqueKeysWithValues: (1...202).map { ($0, 160.0) }))
    await server.configure(transferOnPage: true)
    let store = recoveryStore()
    let before = try await store.load()

    let report = await coordinator(query, server, store).resume()

    #expect(report.failures.first?.issue == .ownerChanged)
    #expect(await server.accepted.isEmpty)
    let after = try await store.load()
    #expect(after.pending == before.pending)
    #expect(after.types[.stepCount]?.anchor == before.types[.stepCount]?.anchor)
    #expect(after.types[.stepCount]?.coverage == before.types[.stepCount]?.coverage)
  }
  @Test(arguments: [false, true])
  func fractionalHistoricalExtentDoesNotDiscardArchivedEdgeUUIDs(hasTail: Bool) async throws {
    let query = InventoryHealthFixture()
    let interval = DateInterval(
      start: Date(timeIntervalSince1970: 100.0004),
      end: Date(timeIntervalSince1970: hasTail ? 200.0004 : 200))
    let server = InventoryServerFixture(
      rows: hasTail ? [1: 100, 2: 160, 3: 200] : [1: 100, 2: 160])
    let store = recoveryStore(interval: interval)
    let report = await coordinator(query, server, store, end: interval.end).resume()
    #expect(report.archiveState == .archived)
    #expect(
      await server.deletedIDs.sorted()
        == (hasTail ? [inventoryID(1), inventoryID(3)] : [inventoryID(1)]))
    #expect(await server.rows.keys.sorted() == [2])
    #expect(await server.queries.first?.start == "1970-01-01T00:01:40.000Z")
    #expect(
      await server.queries.first?.end
        == (hasTail ? "1970-01-01T00:03:20.001Z" : "1970-01-01T00:03:20.000Z"))
  }

  @Test(arguments: [false, true])
  func cleanSnapshotRevalidatesRevisionAfterLocalEnumeration(interrupted: Bool) async throws {
    let query = InventoryHealthFixture()
    if interrupted { await query.configure(mode: "fail-second-read") }
    let server = InventoryServerFixture(rows: [2: 160])
    await query.insertAfterNextPage(on: server)
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(await query.requestedIntervals.count == 2)
    #expect(await server.accepted.isEmpty)
    #expect(await server.rows.keys.sorted() == [2, 3])
    let state = try await store.load()
    if interrupted {
      #expect(report.archiveState == .paused)
      #expect(report.failures.first?.category == .deviceLocked)
      #expect(state.types[.stepCount]?.reconciliationRequired == true)
      #expect(state.types[.stepCount]?.coverage.intervals.isEmpty == true)
    } else {
      #expect(report.archiveState == .archived)
      #expect(state.types[.stepCount]?.reconciliationRequired == false)
      #expect(state.types[.stepCount]?.coverage.intervals == [inventoryInterval])
    }
  }

  @Test func correctionsCommitBeforeConditionalMissingOriginalDeletion() async throws {
    let query = InventoryHealthFixture()
    await query.configure(mode: "correction")
    let server = InventoryServerFixture(rows: [1: 100, 2: 160])
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .archived)
    let batches = await server.attempted
    #expect(batches.count == 2)
    #expect(batches.first?.expectedInventoryRevision == nil)
    #expect(batches.first?.samples.first?.uuid == inventoryID(2))
    #expect(
      batches.first?.samples.first?.payload
        == .quantity(
          .init(rawValue: 9, rawUnit: "count", canonicalValue: 9, canonicalUnit: "count")))
    #expect(batches.last?.expectedInventoryRevision == 1)
    #expect(batches.last?.expectedOwnerGeneration == 1)
    #expect(batches.last?.deletions.map(\.uuid) == [inventoryID(1)])
    #expect(try await store.load().types[.stepCount]?.anchor == Data([2]))
    #expect(try await store.load().types[.stepCount]?.coverage.intervals == [inventoryInterval])
  }

  @Test func eightRevisionConflictsPauseWithoutCoverageOrPendingMutation() async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(rows: [1: 100, 2: 160])
    await server.configure(conflictingDeletes: 8)
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .paused)
    #expect(report.failures.first?.issue == .inventoryUnstable)
    #expect(await server.conflicts == 8)
    #expect(await server.accepted.isEmpty)
    #expect(await server.rows.keys.sorted() == [1, 2])
    let state = try await store.load()
    #expect(state.pending == nil)
    #expect(state.types[.stepCount]?.reconciliationRequired == true)
    #expect(state.types[.stepCount]?.coverage.intervals.isEmpty == true)
    #expect(state.types[.stepCount]?.inventoryComparison == nil)
  }

  @Test func uploadAfterLocalEnumerationCannotBecomeAnInferredDeletion() async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(rows: [1: 100, 2: 160])
    await query.insertAfterNextPage(on: server)
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .archived)
    #expect(await server.rows.keys.sorted() == [2, 3])
    #expect(await server.deletedIDs == [inventoryID(1)])
    #expect(await server.attempted.first?.expectedInventoryRevision == 0)
  }

  @Test(arguments: [false, true])
  func fractionalAuthorizationProofSurvivesLostReceiptButRejectsMovement(moved: Bool) async throws {
    let query = InventoryHealthFixture()
    let boundary = 100.0004
    await query.configure(boundary: boundary)
    let server = InventoryServerFixture(rows: [1: 110, 2: 160])
    await server.configure(loseReceipt: true)
    let store = recoveryStore()
    let first = await coordinator(query, server, store).resume()
    #expect(first.failures.first?.category == .connectionLost)
    let state = try await store.load()
    let pending = try #require(state.pending)
    #expect(
      pending.nextCheckpoint.observedAuthorizationBoundary == Date(timeIntervalSince1970: boundary))
    #expect(
      ArchiveWire.utcDate(pending.batch.coverage.start!)! >= Date(timeIntervalSince1970: boundary))
    let restored = InMemoryArchiveCheckpointStore(
      state: try ArchiveCheckpointCodec.decode(ArchiveCheckpointCodec.encode(state)))
    if moved { await query.configure(boundary: 100.0005) }
    let second = await coordinator(query, server, restored).resume()
    if moved {
      #expect(second.archiveState == .paused)
      #expect(second.failures.first?.issue == .authorizationUnproven)
      #expect(await server.attempted.count == 1)
      #expect(try await restored.load().pending?.batch == pending.batch)
    } else {
      #expect(second.archiveState == .archived)
      #expect(await server.attempted.count == 2)
      #expect(await server.attempted.allSatisfy { $0 == pending.batch })
      #expect(try await restored.load().pending == nil)
      #expect(try await restored.load().archivedDeletions == 1)
    }
  }

  @Test func invalidAnchorDeletesMissingOriginalAndPreservesEarlierScope() async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(rows: [1: 100, 2: 160])
    let store = recoveryStore(invalidated: false)
    await query.configure(invalidate: true)
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .archived)
    #expect(await server.deletedIDs == [inventoryID(1)])
    #expect(await server.queries.first?.start == "1970-01-01T00:01:40.000Z")
    #expect(try await store.load().types[.stepCount]?.reconciliationRequired == false)
    #expect(try await store.load().types[.stepCount]?.coverage.intervals == [inventoryInterval])
  }

  @Test(arguments: [true, false])
  func concurrentUploadRestartsWithoutMixedSnapshotDeletion(betweenPages: Bool) async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(
      rows: Dictionary(uniqueKeysWithValues: (1...202).map { ($0, 160.0) }))
    await server.configure(conflictOnPage: betweenPages, conflictOnDelete: !betweenPages)
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .archived)
    #expect(await server.conflicts == 1)
    #expect(await server.accepted.allSatisfy { $0.expectedInventoryRevision != nil })
    #expect(await server.rows.keys.sorted() == [2])
    #expect(try await store.load().pending == nil)
  }

  @Test func moreThanTwoHundredMissingIDsReinventoriesAfterEachReceipt() async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(
      rows: Dictionary(uniqueKeysWithValues: (1...450).map { ($0, 160.0) }))
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .archived)
    #expect(await server.accepted.map { $0.deletions.count } == [200, 200, 49])
    #expect(await server.accepted.compactMap(\.expectedInventoryRevision) == [0, 1, 2])
    // Four comparison snapshots plus a final clean-snapshot revision check.
    #expect(await server.queries.filter { $0.cursor == nil }.count == 5)
  }

  @Test func lostConditionalReceiptRetriesExactJournalBeforeRevisionCheck() async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(rows: [1: 100, 2: 160])
    await server.configure(loseReceipt: true)
    let store = recoveryStore()
    let first = await coordinator(query, server, store).resume()
    #expect(first.failures.first?.category == .connectionLost)
    let pending = try #require(try await store.load().pending)
    #expect(pending.batch.expectedInventoryRevision == 0)
    #expect(try await store.load().types[.stepCount]?.coverage.intervals.isEmpty == true)
    let second = await coordinator(query, server, store).resume()
    #expect(second.archiveState == .archived)
    #expect(await server.attempted.prefix(2).allSatisfy { $0 == pending.batch })
    #expect(await server.revision == 1)
    #expect(try await store.load().archivedDeletions == 1)
  }

  @Test(arguments: ["empty", "nil-boundary", "query-failure", "boundary-moves"])
  func uncertainReadabilityNeverTombstonesOrClaimsCoverage(mode: String) async throws {
    let query = InventoryHealthFixture()
    await query.configure(mode: mode)
    let server = InventoryServerFixture(rows: [1: 100, 2: 160])
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .paused)
    #expect(await server.accepted.isEmpty)
    #expect(try await store.load().types[.stepCount]?.reconciliationRequired == true)
    #expect(try await store.load().types[.stepCount]?.coverage.intervals.isEmpty == true)
  }

  @Test func movedBoundaryClampsComparisonAndExcludesCrossingOriginals() async throws {
    let query = InventoryHealthFixture()
    await query.configure(mode: "crossing", boundary: 150)
    let server = InventoryServerFixture(rows: [1: 100, 2: 160, 3: 170])
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .archived)
    #expect(await server.deletedIDs == [inventoryID(3)])
    #expect(await server.rows.keys.sorted() == [1, 2])
    #expect(
      await server.queries.allSatisfy {
        ArchiveWire.utcDate($0.start)! >= Date(timeIntervalSince1970: 150)
      })
  }

  @Test func sameTimeIDsRemainDistinctAndDenseWindowsSplit() async throws {
    let query = InventoryHealthFixture()
    await query.configure(dense: true)
    let server = InventoryServerFixture(rows: [1: 120, 2: 120])
    let store = recoveryStore()
    let report = await coordinator(query, server, store).resume()
    #expect(report.archiveState == .archived)
    #expect(await server.deletedIDs.isEmpty)
    #expect(await query.requestedIntervals.contains { $0.duration < 100 })
  }

  @Test func unsplittableDensityFailsClosedWithTypedIssue() async throws {
    let query = InventoryHealthFixture()
    await query.configure(dense: true, tied: true)
    let server = InventoryServerFixture(rows: [1: 160, 2: 160])
    let minimum = DateInterval(
      start: Date(timeIntervalSince1970: 160), end: Date(timeIntervalSince1970: 160.001))
    let store = recoveryStore(interval: minimum)
    let report = await coordinator(query, server, store, end: minimum.end).resume()
    #expect(report.failures.first?.issue == .inventoryTooDense)
    #expect(await server.accepted.isEmpty)
    #expect(try await store.load().types[.stepCount]?.reconciliationRequired == true)
  }

  @Test func failedCompletionCheckpointCannotClearReconciliationRequired() async throws {
    let query = InventoryHealthFixture()
    let server = InventoryServerFixture(rows: [2: 160])
    let store = InventoryCompletionFailingStore(state: try await recoveryStore().load())
    let first = await coordinator(query, server, store).resume()
    #expect(first.failures.first?.category == .checkpoint)
    #expect(await store.load().types[.stepCount]?.reconciliationRequired == true)
    #expect(await store.load().types[.stepCount]?.coverage.intervals.isEmpty == true)
    let second = await coordinator(query, server, store).resume()
    #expect(second.archiveState == .archived)
  }

  @Test func emptyRequestedRangeCannotReportUnresolvedReconciliationAsArchived() async throws {
    var state = try await recoveryStore().load()
    state.selection = .init(metrics: [.steps], requestedStart: Date(timeIntervalSince1970: 300))
    let store = InMemoryArchiveCheckpointStore(state: state)
    let server = InventoryServerFixture(rows: [1: 100, 2: 160])
    let report = await coordinator(InventoryHealthFixture(), server, store).resume()
    #expect(report.archiveState == .paused)
    #expect(report.failures.first?.issue == .reconciliationRequired)
    #expect(try await store.load().types[.stepCount]?.reconciliationRequired == true)
    #expect(await server.accepted.isEmpty)
  }

  private func recoveryStore(
    invalidated: Bool = true, interval: DateInterval = inventoryInterval
  ) -> InMemoryArchiveCheckpointStore {
    var state = ArchiveImportCheckpoint()
    state.selection = .init(metrics: [.steps])
    state.destination = "https://example.invalid"
    state.userID = "person-1"
    state.uploaderFingerprint = "0123456789ab"
    state.ownerGeneration = 1
    var type = ArchiveTypeCheckpoint()
    type.anchor = Data([1])
    type.observedAuthorizationBoundary = Date(timeIntervalSince1970: 100)
    type.coverage.insert(interval)
    if invalidated {
      type.reconciliationRequired = true
      type.reconciliationIntervals = type.coverage
      type.coverage = ArchiveIntervals()
      type.scanned.insert(interval)
    }
    state.types[.stepCount] = type
    return InMemoryArchiveCheckpointStore(state: state)
  }

  private func coordinator(
    _ query: InventoryHealthFixture, _ server: InventoryServerFixture,
    _ store: any ArchiveCheckpointStore, end: Date = inventoryInterval.end
  ) -> ArchiveImportCoordinator {
    ArchiveImportCoordinator(
      access: ImportPaidAccessFixture(),
      query: query, checkpointStore: store,
      connection: {
        ArchiveImportConnection(
          baseURL: try NormalizedBaseURL.parse(
            "https://example.invalid", allowConfirmedLocalHTTP: false),
          userID: "person-1", token: "secret", capability: try await server.capability(),
          sender: server, statusFetcher: server,
          uploaderFingerprint: "0123456789ab")
      }, now: { end })
  }
}

private let inventoryInterval = DateInterval(
  start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))

private func inventoryID(_ index: Int) -> String {
  "00000000-0000-4000-8000-\(String(format: "%012d", index))"
}

private actor InventoryCompletionFailingStore: ArchiveCheckpointStore {
  var state: ArchiveImportCheckpoint
  var fail = true
  init(state: ArchiveImportCheckpoint) { self.state = state }
  func load() -> ArchiveImportCheckpoint { state }
  func save(_ value: ArchiveImportCheckpoint) throws {
    if fail && value.types[.stepCount]?.reconciliationRequired == false {
      fail = false
      throw ArchiveCheckpointStoreError.unavailable
    }
    _ = try ArchiveCheckpointCodec.encode(value)
    state = value
  }
  func reset() { state = ArchiveImportCheckpoint() }
}

private actor InventoryHealthFixture: HealthArchiveQuerying {
  var boundary: Double? = 100
  var mode = ""
  var invalidate = false
  var dense = false
  var tied = false
  var discoveries = 0
  var requestedIntervals: [DateInterval] = []
  var insertServer: InventoryServerFixture?
  var extraIDs: [Int] = []

  func insertAfterNextPage(on server: InventoryServerFixture) { insertServer = server }

  func configure(
    mode: String = "", boundary: Double? = 100, invalidate: Bool = false,
    dense: Bool = false, tied: Bool = false
  ) {
    self.mode = mode
    self.boundary = mode == "nil-boundary" ? nil : boundary
    self.invalidate = invalidate
    self.dense = dense
    self.tied = tied
  }

  func discover(types: Set<HealthObjectTypeID>) -> [HealthObjectTypeID: ReadableHistory] {
    discoveries += 1
    let date = (mode == "boundary-moves" && discoveries > 2 ? 170 : boundary)
      .map { Date(timeIntervalSince1970: $0) }
    return [
      .stepCount: mode == "empty"
        ? .noReadableSamples(authorizationBoundary: date)
        : .readable(earliest: Date(timeIntervalSince1970: 160), authorizationBoundary: date)
    ]
  }

  func discover(metrics: [MetricDefinition]) -> ArchiveHistoryDiscovery {
    let types = discover(types: [.stepCount])
    return ArchiveHistoryDiscovery(types: types, metrics: [.steps: types[.stepCount]!])
  }

  func changes(type: HealthObjectTypeID, anchor: Data?) throws -> ArchiveChangePage {
    if invalidate && anchor != nil {
      invalidate = false
      throw ArchiveQueryError.anchorInvalidated
    }
    if mode == "correction" && anchor == Data([1]) {
      return ArchiveChangePage(
        samples: [
          ArchiveSample(
            uuid: inventoryID(2), start: "1970-01-01T00:02:40Z", end: "1970-01-01T00:03:00Z",
            source: ArchiveSource(bundleID: "test", name: "Test", revision: "1"), timeZone: "UTC",
            metadata: [:],
            payload: .quantity(
              .init(rawValue: 9, rawUnit: "count", canonicalValue: 9, canonicalUnit: "count")))
        ],
        deletedSampleIDs: [], candidateAnchor: Data([2]), hasMore: false)
    }
    return ArchiveChangePage(
      samples: [], deletedSampleIDs: [], candidateAnchor: Data([2]), hasMore: false)
  }

  func page(
    type: HealthObjectTypeID, interval: DateInterval, cursor: ArchiveScanCursor?, limit: Int
  ) async throws -> ArchiveSamplePage {
    requestedIntervals.append(interval)
    if mode == "query-failure" { throw ArchiveQueryError.deviceLocked }
    if mode == "fail-second-read" && requestedIntervals.count == 2 {
      throw ArchiveQueryError.deviceLocked
    }
    let indices = dense ? Array(1...20_001) : (mode == "crossing" ? [1, 2] : [2]) + extraIDs
    let eligible = indices.filter {
      if mode == "crossing" && $0 == 1 {
        return interval.start.timeIntervalSince1970 <= 180
          && interval.end.timeIntervalSince1970 > 100
      }
      let time = dense && !tied ? ($0 <= 10_000 ? 120.0 : 160.0) : 160.0
      return time >= interval.start.timeIntervalSince1970
        && time < interval.end.timeIntervalSince1970
    }
    let offset = cursor?.anchor.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
    let upper = min(offset + limit, eligible.count)
    let samples = eligible[offset..<upper].map { index in
      ArchiveSample(
        uuid: inventoryID(index),
        start: mode == "crossing" && index == 1
          ? "1970-01-01T00:01:40Z"
          : (dense && !tied && index <= 10_000 ? "1970-01-01T00:02:00Z" : "1970-01-01T00:02:40Z"),
        end: "1970-01-01T00:03:00Z",
        source: ArchiveSource(bundleID: "test", name: "Test", revision: "1"), timeZone: "UTC",
        metadata: [:],
        payload: .quantity(
          .init(rawValue: 1, rawUnit: "count", canonicalValue: 1, canonicalUnit: "count")))
    }
    if let server = insertServer {
      insertServer = nil
      extraIDs = [3]
      // The returned page remains the earlier local snapshot. Another uploader
      // archives a newly readable original immediately after that enumeration.
      await server.concurrentUpload(id: 3)
    }
    return ArchiveSamplePage(
      samples: samples, deletedSampleIDs: [], coveredInterval: interval,
      isWindowComplete: upper == eligible.count,
      nextCursor: upper == eligible.count
        ? nil
        : ArchiveScanCursor(
          type: type, interval: interval, windowStart: interval.start, windowEnd: interval.end,
          anchor: Data(String(upper).utf8)))
  }
}

private actor InventoryServerFixture: ArchiveBatchSending, ArchiveStatusFetching,
  ArchiveInventoryFetching
{
  var rows: [Int: Double]
  var revision: Int64 = 0
  var queries: [ArchiveInventoryQuery] = []
  var attempted: [ArchiveBatch] = []
  var accepted: [ArchiveBatch] = []
  var receipts: [String: ArchiveAcknowledgement] = [:]
  var conflictOnPage = false
  var conflictOnDelete = false
  var loseReceipt = false
  var conflicts = 0
  var conflictingDeletes = 0
  var transferOnPage = false
  var ownerGeneration = 1
  var deletedIDs: [String] { accepted.flatMap(\.deletions).map(\.uuid) }
  init(rows: [Int: Double]) { self.rows = rows }
  func concurrentUpload(id: Int) {
    rows[id] = 160
    revision += 1
  }
  func configure(
    conflictOnPage: Bool = false, conflictOnDelete: Bool = false, loseReceipt: Bool = false,
    conflictingDeletes: Int = 0, transferOnPage: Bool = false
  ) {
    self.conflictOnPage = conflictOnPage
    self.conflictOnDelete = conflictOnDelete
    self.loseReceipt = loseReceipt
    self.conflictingDeletes = conflictingDeletes
    self.transferOnPage = transferOnPage
  }
  func capability() throws -> ArchiveCapability {
    var fixture =
      try JSONSerialization.jsonObject(with: fixtureData(named: "archive-capability-v2"))
      as! [String: Any]
    var response = fixture["response"] as! [String: Any]
    response["statistics_available"] = false
    response["archive_schema_version"] = 3
    response["ownership_contract_version"] = 1
    response["owner_state"] = "active"
    response["owner_generation"] = 1
    fixture["response"] = response
    return try JSONDecoder().decode(
      ArchiveCapability.self, from: JSONSerialization.data(withJSONObject: response))
  }
  func page(query: ArchiveInventoryQuery, baseURL: NormalizedBaseURL) throws -> ArchiveInventoryPage
  {
    queries.append(query)
    if query.cursor != nil && transferOnPage {
      transferOnPage = false
      ownerGeneration += 1
    }
    if query.cursor != nil && conflictOnPage {
      conflictOnPage = false
      revision += 1
      conflicts += 1
      throw ArchiveClientError.inventoryChanged
    }
    let parts = query.cursor?.split(separator: ":")
    if let parts, Int64(parts[0]) != revision { throw ArchiveClientError.inventoryChanged }
    let offset = parts.flatMap { Int($0[1]) } ?? 0
    let start = ArchiveWire.utcDate(query.start)!.timeIntervalSince1970
    let end = ArchiveWire.utcDate(query.end)!.timeIntervalSince1970
    let ids = rows.filter { $0.value >= start && $0.value < end }.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
    }.map { inventoryID($0.key) }
    let upper = min(offset + query.limit, ids.count)
    let object: [String: Any] = [
      "ok": true, "request_type": "archive_inventory", "protocol_version": 2,
      "request_id": query.requestID, "sample_ids": Array(ids[offset..<upper]), "revision": revision,
      "owner_generation": ownerGeneration,
      "next_cursor": upper == ids.count ? NSNull() : "\(revision):\(upper)",
    ]
    return try JSONDecoder().decode(
      ArchiveInventoryPage.self, from: JSONSerialization.data(withJSONObject: object))
  }
  func send(_ batch: ArchiveBatch, baseURL: NormalizedBaseURL) throws -> ArchiveAcknowledgement {
    attempted.append(batch)
    if let receipt = receipts[batch.batchID] { return receipt }
    if batch.expectedInventoryRevision != nil && (conflictOnDelete || conflictingDeletes > 0) {
      conflictOnDelete = false
      conflictingDeletes = max(0, conflictingDeletes - 1)
      revision += 1
      conflicts += 1
    }
    if let expected = batch.expectedInventoryRevision, expected != revision {
      throw ArchiveClientError.inventoryChanged
    }
    for deletion in batch.deletions {
      rows = rows.filter { inventoryID($0.key) != deletion.uuid }
    }
    for sample in batch.samples {
      rows[Int(sample.uuid.suffix(12))!] = ArchiveWire.utcDate(sample.start)!.timeIntervalSince1970
    }
    if batch.expectedInventoryRevision != nil { accepted.append(batch) }
    revision += 1
    let object: [String: Any] = [
      "ok": true, "archive_commit": "committed", "protocol_version": 2,
      "request_id": batch.requestID, "batch_id": batch.batchID,
      "received_samples": batch.samples.count, "committed_samples": batch.samples.count,
      "received_deletions": batch.deletions.count, "committed_deletions": batch.deletions.count,
      "projection_state": "pending",
    ]
    let receipt = try JSONDecoder().decode(
      ArchiveAcknowledgement.self, from: JSONSerialization.data(withJSONObject: object))
    receipts[batch.batchID] = receipt
    if loseReceipt && batch.expectedInventoryRevision != nil {
      loseReceipt = false
      throw NetworkFailure.connectionLost
    }
    return receipt
  }
  func status(requestID: String, baseURL: NormalizedBaseURL) throws -> ArchiveProjectionStatus {
    throw NetworkFailure.protocolMismatch
  }
}
