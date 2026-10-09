import Foundation
import Testing

@testable import HealthSyncCore

@Suite("ArchiveImport coordinator")
struct ArchiveImportCoordinatorTests {
  @Test func revocationBetweenBatchesRetainsCommittedProgress() async throws {
    let server = ArchiveServerFixture()
    let query = ArchiveQueryFixture()
    await query.setCount(3)
    await server.setLimits(samples: 1, bytes: 100000)
    let store = InMemoryArchiveCheckpointStore()
    let access = ImportCheckpointAccess {
      (try? await store.load().archivedSamples) == 0 ? .unlocked : .locked
    }
    let result = await makeCoordinator(query: query, server: server, store: store, access: access)
      .importHistory(selection: .init(metrics: [.steps]))
    #expect(result.archiveState == .paused)
    #expect(result.failures.first?.issue == .purchaseRequired)
    #expect(await server.batches.count == 1)
    #expect(try await store.load().archivedSamples == 1)
  }
  @Test func lockedImportAndResumePreservePendingCheckpointBytes() async throws {
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let locked = makeCoordinator(
      server: server, store: store, access: ImportPaidAccessFixture(.locked))
    let initial = await locked.importHistory(selection: .init(metrics: [.steps]))
    #expect(initial.archiveState == .paused)
    #expect(await server.batches.isEmpty)
    await server.setFailure(.connectionLost)
    _ = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(try await store.load().pending != nil)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let before = try encoder.encode(await store.load())
    let count = await server.batches.count
    await server.setFailure(nil)
    let result = await locked.resume()
    #expect(result.archiveState == .paused)
    #expect(result.failures.first?.category == .purchaseRequired)
    #expect(await server.batches.count == count)
    #expect(try encoder.encode(await store.load()) == before)
  }

  @Test func archiveRateLimitWaitsAndReplaysTheSameJournaledBatch() async throws {
    let server = ArchiveServerFixture()
    await server.rateLimitNextBatch(retryAfter: 0.01)
    let store = InMemoryArchiveCheckpointStore()

    let report = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))

    #expect(report.archiveState == .archived)
    #expect(report.archivedSamples == 1)
    let batches = await server.batches
    #expect(batches.count == 2)
    if batches.count == 2 { #expect(batches[0] == batches[1]) }
    #expect(try await store.load().pending == nil)
  }

  @Test func pausingDuringArchiveRateLimitWaitPreservesPendingBatch() async throws {
    let server = ArchiveServerFixture()
    await server.rateLimitNextBatch(retryAfter: 30)
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(server: server, store: store)
    let running = Task { await coordinator.importHistory(selection: .init(metrics: [.steps])) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await server.batches.isEmpty && ContinuousClock.now < deadline { await Task.yield() }
    #expect(await server.batches.count == 1)

    await coordinator.pause()
    let report = await running.value
    #expect(report.archiveState == .paused)
    #expect(report.failures.first?.category == .cancelled)
    #expect(await server.batches.count == 1)
    #expect(try await store.load().pending != nil)
  }
  @Test func reapprovedSameCredentialCannotReplayOldGenerationPendingBatch() async throws {
    let server = ArchiveServerFixture()
    await server.setFailure(.connectionLost)
    let store = InMemoryArchiveCheckpointStore()
    _ = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    let before = try await store.load()
    #expect(before.ownerGeneration == 1)
    #expect(before.pending != nil)
    await server.setFailure(nil)
    await server.setOwnerGeneration(3)

    let report = await makeCoordinator(server: server, store: store).resume()
    #expect(report.failures.first?.issue == .checkpointOwnerMismatch)
    #expect(await server.batches.count == 1)
    #expect(try await store.load() == before)
  }

  @Test func legacyPendingBatchWithoutGenerationCannotReplay() async throws {
    let server = ArchiveServerFixture()
    await server.setFailure(.connectionLost)
    let store = InMemoryArchiveCheckpointStore()
    _ = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    var legacy = try await store.load()
    legacy.ownerGeneration = nil
    try await store.save(legacy)
    await server.setFailure(nil)

    let report = await makeCoordinator(server: server, store: store).resume()
    #expect(report.failures.first?.issue == .checkpointOwnerMismatch)
    #expect(await server.batches.count == 1)
    #expect(try await store.load() == legacy)
  }

  @Test func ownerTransferDuringFinalStatusPollPausesCommittedArchive() async throws {
    let server = ArchiveServerFixture()
    await server.setStatusError(.ownerChanged)
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(server: server, store: store)

    let report = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .paused)
    #expect(report.failures.first?.issue == .ownerChanged)
    #expect(report.archivedSamples == 1)
    #expect(try await store.load().pending == nil)

    let refreshed = await coordinator.refreshProjection()
    #expect(refreshed.archiveState == .paused)
    #expect(refreshed.failures.contains { $0.issue == .ownerChanged })
  }
  @Test func migratedPendingBatchCannotReplayWithReplacementCredential() async throws {
    let server = ArchiveServerFixture()
    await server.setFailure(.connectionLost)
    let store = InMemoryArchiveCheckpointStore()
    _ = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    var legacy = try await store.load()
    let pending = try #require(legacy.pending)
    legacy.uploaderFingerprint = nil
    try await store.save(legacy)
    await server.setFailure(nil)

    let report = await makeCoordinator(server: server, store: store).resume()
    #expect(report.failures.first?.issue == .checkpointOwnerMismatch)
    #expect(await server.batches.count == 1)
    #expect(try await store.load().pending == pending)
    #expect(try await store.load().types == legacy.types)
  }

  @Test func ownerRevocationRetainsPendingJournalAndAnchor() async throws {
    let server = ArchiveServerFixture()
    await server.setFailure(.connectionLost)
    let store = InMemoryArchiveCheckpointStore()
    _ = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    let before = try await store.load()
    await server.setFailure(nil)
    await server.setOwnerError(.ownerChanged)

    let report = await makeCoordinator(server: server, store: store).resume()
    #expect(report.failures.first?.issue == .ownerChanged)
    #expect(try await store.load() == before)
  }
  @Test(arguments: [false, true])
  func narrowedSelectionDoesNotLoseAnchoredAdditionOrCorrectionInEarlierCoverage(
    correction: Bool
  ) async throws {
    let query = ArchiveQueryFixture()
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, server: server, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    try await query.addAnchoredSample(start: "1970-01-01T00:02:30Z", correction: correction)
    _ = await coordinator.importHistory(
      selection: .init(metrics: [.steps], requestedStart: Date(timeIntervalSince1970: 180)))
    #expect(await server.batches.flatMap(\.samples).count == 1)
    #expect(try await store.load().types[.stepCount]?.anchor == Data([2]))
    let report = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    #expect(await server.batches.flatMap(\.samples).contains { $0.start == "1970-01-01T00:02:30Z" })
    #expect(await server.batches.flatMap(\.deletions).isEmpty)
  }

  @Test func ordinaryReplayUsesNativeFractionalBoundaryAndRejectsActualRestriction() async throws {
    for restricted in [false, true] {
      let query = ArchiveQueryFixture()
      await query.setHistory(start: 100.0004, boundary: 100.0004)
      let server = ArchiveServerFixture()
      await server.setFailure(.connectionLost)
      let store = InMemoryArchiveCheckpointStore()
      let coordinator = makeCoordinator(query: query, server: server, store: store)
      _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
      let pending = try #require(try await store.load().pending)
      await server.setFailure(nil)
      if restricted { await query.setHistory(start: 100.0006, boundary: 100.0006) }
      let report = await coordinator.resume()
      if restricted {
        #expect(report.failures.first?.issue == .permissionRestricted)
        #expect(await server.batches.count == 1)
        #expect(try await store.load().pending == pending)
      } else {
        #expect(report.archiveState == .archived)
        #expect(await server.batches.count == 2)
        #expect(await server.batches.last == pending.batch)
        #expect(try await store.load().pending == nil)
      }
    }
  }

  @Test func anchoredMicrosecondSampleAboveAuthorizationBoundaryIsUploaded() async throws {
    let query = ArchiveQueryFixture()
    await query.setHistory(start: 100.0004, boundary: 100.0004)
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, server: server, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    try await query.addAnchoredSample(start: "1970-01-01T00:01:40.000600Z")
    let report = await coordinator.resume()
    #expect(report.archiveState == .archived)
    #expect(await server.batches.flatMap(\.samples).contains { $0.start.hasSuffix(".000600Z") })
    #expect(try await store.load().types[.stepCount]?.anchor == Data([2]))
  }

  @Test func deletingLastReadableSampleStillSendsTombstoneAndCommitsAnchor() async throws {
    let query = ArchiveQueryFixture()
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, server: server, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    await query.deleteLastReadableSample()
    let report = await coordinator.resume()
    #expect(report.noReadableMetrics == [.steps])
    #expect(report.failures.isEmpty)
    #expect(report.archiveState == .archived)
    #expect(
      await server.batches.flatMap(\.deletions).map(\.uuid) == [
        "00000000-0000-4000-8000-000000000001"
      ])
    #expect(try await store.load().types[.stepCount]?.anchor == Data([2]))
    #expect(try await store.load().pending == nil)
  }

  @Test func initialGlobalSnapshotDoesNotUploadOriginalsTwice() async throws {
    let query = ArchiveQueryFixture()
    await query.setCount(7)
    await query.setInitialSnapshot()
    let server = ArchiveServerFixture()
    await server.setLimits(samples: 3, bytes: 262144)
    let store = InMemoryArchiveCheckpointStore()
    let report = await makeCoordinator(query: query, server: server, store: store)
      .importHistory(selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    #expect(await server.batches.flatMap(\.samples).count == 7)
    #expect(await server.batches.first?.samples.count == 3)
    #expect(try await store.load().types[.stepCount]?.coverage.intervals == [query.interval])
  }

  @Test func lastDeletionLostAcknowledgementRetriesExactBatchWithoutAdvancingAnchor() async throws {
    let query = ArchiveQueryFixture()
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, server: server, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    await query.deleteLastReadableSample()
    await server.setFailure(.connectionLost)
    let interrupted = await coordinator.resume()
    #expect(interrupted.failures.first?.category == .connectionLost)
    let state = try await store.load()
    #expect(state.types[.stepCount]?.anchor == Data([1]))
    let pending = try #require(state.pending)
    #expect(pending.batch.samples.isEmpty)
    #expect(pending.batch.deletions.count == 1)
    await server.setFailure(nil)
    _ = await makeCoordinator(query: query, server: server, store: store).resume()
    #expect(await server.batches.suffix(2).allSatisfy { $0 == pending.batch })
    #expect(try await store.load().types[.stepCount]?.anchor == Data([2]))
    #expect(try await store.load().pending == nil)
  }

  @Test func emptyDiscoveryWithRestrictedBoundaryDoesNotReconcileOrInferDeletions() async throws {
    let query = ArchiveQueryFixture()
    let server = ArchiveServerFixture()
    let coordinator = makeCoordinator(query: query, server: server)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    let changesBefore = await query.changeCalls
    await query.deleteLastReadableSample()
    await query.setHistory(start: 150, boundary: 150)
    let report = await coordinator.resume()
    #expect(report.failures.first?.issue == .permissionRestricted)
    #expect(await query.changeCalls == changesBefore)
    #expect(await server.batches.flatMap(\.deletions).isEmpty)
  }

  @Test func baselineSurvivesInterruptedUploadWithoutClaimingCommittedAnchor() async throws {
    let query = ArchiveQueryFixture()
    await query.setInitialSnapshot()
    let server = ArchiveServerFixture()
    await server.setFailure(.offline)
    let store = InMemoryArchiveCheckpointStore()
    let first = await makeCoordinator(query: query, server: server, store: store)
      .importHistory(selection: .init(metrics: [.steps]))
    #expect(first.failures.first?.category == .offline)
    let state = try await store.load()
    #expect(state.types[.stepCount]?.baselineAnchor == Data([1]))
    #expect(state.types[.stepCount]?.anchor == nil)
    #expect(state.types[.stepCount]?.coverage.intervals.isEmpty == true)
    await server.setFailure(nil)
    _ = await makeCoordinator(query: query, server: server, store: store).resume()
    #expect(await query.initialSnapshotCalls == 1)
    #expect(try await store.load().types[.stepCount]?.baselineAnchor == nil)
    #expect(try await store.load().types[.stepCount]?.anchor == Data([1]))
  }

  @Test func pauseWaitsForSuspendedSendBeforeResetAndPreventsLateCheckpointWrite() async throws {
    let server = ArchiveServerFixture()
    await server.suspendSend()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(server: server, store: store)
    let importing = Task { await coordinator.importHistory(selection: .init(metrics: [.steps])) }
    defer { Task { await server.releaseSend() } }
    let sendDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await !server.isSendSuspended && ContinuousClock.now < sendDeadline { await Task.yield() }
    let suspended = await server.isSendSuspended
    try #require(suspended)
    #expect(try await store.load().pending != nil)
    let resetting = Task {
      await coordinator.pause()
      await store.reset()
    }
    let cancellationDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await !server.sendWasCancelled && ContinuousClock.now < cancellationDeadline {
      await Task.yield()
    }
    let cancelled = await server.sendWasCancelled
    try #require(cancelled)
    // The sender deliberately ignores cancellation until released, like a delayed callback.
    #expect(try await store.load().pending != nil)
    await server.releaseSend()
    await resetting.value
    let report = await importing.value
    #expect(report.failures.first?.category == .cancelled)
    #expect(try await store.load() == ArchiveImportCheckpoint())
  }

  @Test func crossingSampleCorrectionIsReconciledForNarrowerSelection() async throws {
    let query = ArchiveQueryFixture()
    await query.setCorrections()
    let server = ArchiveServerFixture()
    let report = await makeCoordinator(query: query, server: server).importHistory(
      selection: .init(metrics: [.steps], requestedStart: Date(timeIntervalSince1970: 100.5)))
    #expect(report.archiveState == .archived)
    #expect(await server.batches.flatMap(\.samples).count == 2)
  }

  @Test func lostAcknowledgementRetriesExactJournalBeforeAdvancingCoverage() async throws {
    let query = ArchiveQueryFixture()
    let server = ArchiveServerFixture()
    await server.setFailure(.connectionLost)
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, server: server, store: store)
    let first = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    #expect(first.failures.first?.category == .connectionLost)
    let interrupted = try await store.load()
    let pending = try #require(interrupted.pending)
    #expect(interrupted.types[.stepCount]?.coverage.intervals.isEmpty == true)
    #expect(pending.batch.samples.count == 1)
    await server.setFailure(nil)
    let second = await coordinator.resume()
    #expect(second.archiveState == .archived)
    let finished = try await store.load()
    #expect(finished.pending == nil)
    #expect(finished.types[.stepCount]?.coverage.intervals == [query.interval])
    let sent = await server.batches
    #expect(sent[0] == sent[1])
    #expect(finished.types[.stepCount]?.anchor == Data([1]))
  }

  @Test func mismatchedReceiptCannotAdvanceCursorOrCoverage() async throws {
    let server = ArchiveServerFixture()
    await server.setWrongReceipt()
    let store = InMemoryArchiveCheckpointStore()
    let report = await makeCoordinator(server: server, store: store)
      .importHistory(selection: .init(metrics: [.steps]))
    #expect(report.failures.first?.category == .protocolMismatch)
    let state = try await store.load()
    #expect(state.pending != nil)
    #expect(state.types[.stepCount]?.coverage.intervals.isEmpty == true)
  }

  @Test func completedArchivePollsProjectionWithoutResendingSamples() async throws {
    let query = ArchiveQueryFixture()
    let server = ArchiveServerFixture()
    let coordinator = makeCoordinator(query: query, server: server)
    let report = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    #expect(report.projectionStates[.steps] == .pending)
    let before = await server.batches.count
    await server.setProjection("failed")
    let status = await coordinator.refreshProjection()
    #expect(status.archiveState == .archived)
    #expect(status.projectionStates[.steps] == .failed)
    #expect(await server.batches.count == before)
  }

  @Test func checkpointSaveFailureAfterReceiptRetainsExactBatchAcrossRestart() async throws {
    let store = InterruptingArchiveStore()
    let server = ArchiveServerFixture()
    let first = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(first.failures.first?.category == .checkpoint)
    let pending = try #require(await store.load().pending)
    let second = await makeCoordinator(server: server, store: store).resume()
    #expect(second.archiveState == .archived)
    #expect(await server.batches.prefix(2).allSatisfy { $0 == pending.batch })
    #expect(await store.load().pending == nil)
  }

  @Test func cancellationBetweenSendAndSaveRetainsJournal() async throws {
    let store = InterruptingArchiveStore(cancel: true)
    let server = ArchiveServerFixture()
    let first = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(first.failures.first?.category == .cancelled)
    #expect(await store.load().pending != nil)
    #expect(await makeCoordinator(server: server, store: store).resume().archiveState == .archived)
  }

  @Test func failedGlobalReconciliationKeepsAcknowledgedWindowsTentative() async throws {
    let query = ArchiveQueryFixture()
    await query.setChangeFailure(.deviceLocked)
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, store: store)
    let first = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    #expect(first.failures.first?.category == .deviceLocked)
    let interrupted = try await store.load()
    #expect(interrupted.types[.stepCount]?.scanned.intervals == [query.interval])
    #expect(interrupted.types[.stepCount]?.coverage.intervals.isEmpty == true)
    await query.setChangeFailure(nil)
    #expect(await coordinator.resume().archiveState == .archived)
    #expect(await query.pages.count == 1)
  }

  @Test func expansionFillsOlderGapAndRestrictionPausesWithoutDeletingCoverage() async throws {
    let query = ArchiveQueryFixture()
    await query.setHistory(start: 100, boundary: 100)
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, store: store)
    #expect(
      await coordinator.importHistory(selection: .init(metrics: [.steps])).archiveState == .archived
    )
    await query.setHistory(start: 50, boundary: 50)
    #expect(await coordinator.resume().archiveState == .archived)
    #expect(
      await query.pages.last
        == DateInterval(
          start: Date(timeIntervalSince1970: 50), end: Date(timeIntervalSince1970: 100)))
    await query.setHistory(start: 150, boundary: 150)
    let restricted = await coordinator.resume()
    #expect(restricted.failures.first?.issue == .permissionRestricted)
    #expect(
      try await store.load().types[.stepCount]?.coverage.intervals == [
        DateInterval(start: Date(timeIntervalSince1970: 50), end: Date(timeIntervalSince1970: 200))
      ])
  }

  @Test func sharedSourceQueriesOnceAndRetainsPerMetricEarliestDate() async throws {
    let query = ArchiveQueryFixture()
    await query.setEmpty()
    let report = await makeCoordinator(query: query).importHistory(
      selection: .init(metrics: [.sleepDuration, .sleepREM]))
    #expect(report.archiveState == .archived)
    #expect(await query.pages.count == 1)
    #expect(report.metricEarliestDates[.sleepDuration] == Date(timeIntervalSince1970: 100))
    #expect(report.metricEarliestDates[.sleepREM] == Date(timeIntervalSince1970: 150))
  }

  @Test func densePagesObeyCountAndByteLimitsAndKeepDistinctUUIDs() async throws {
    let query = ArchiveQueryFixture()
    await query.setCount(7)
    let server = ArchiveServerFixture()
    await server.setLimits(samples: 3, bytes: 1100)
    let store = InMemoryArchiveCheckpointStore()
    let report = await makeCoordinator(query: query, server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    let batches = await server.batches
    #expect(Set(batches.flatMap(\.samples).map(\.uuid)).count == 7)
    for batch in batches {
      #expect(batch.samples.count <= 3)
      var object =
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch)) as! [String: Any]
      object["token"] = "fixture-secret"
      #expect(
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).count <= 1100)
    }
    #expect(try await store.load().types[.stepCount]?.coverage.intervals == [query.interval])
  }

  @Test func schemaOneInvalidAnchorRescansButCannotClaimInventoryReconciliation() async throws {
    let query = ArchiveQueryFixture()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    await query.setChangeFailure(.anchorInvalidated)
    let report = await coordinator.resume()
    #expect(report.failures.first?.issue == .reconciliationRequired)
    #expect(report.archiveState == .paused)
    #expect(try await store.load().types[.stepCount]?.coverage.intervals.isEmpty == true)
    #expect(
      try await store.load().types[.stepCount]?.reconciliationIntervals?.intervals == [
        query.interval
      ])
    #expect(await query.pages.count == 2)
  }

  @Test func correctionsAndDeletionsAdvanceAnchorOnlyAfterReceipt() async throws {
    let query = ArchiveQueryFixture()
    await query.setCorrections()
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let report = await makeCoordinator(query: query, server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    let batches = await server.batches
    #expect(batches.count == 2)
    #expect(batches.last?.samples.first?.payload != batches.first?.samples.first?.payload)
    #expect(batches.last?.deletions.count == 1)
    #expect(try await store.load().types[.stepCount]?.anchor == Data([1]))
  }

  @Test func changingSelectionCannotOverwriteAnUnresolvedJournal() async throws {
    let server = ArchiveServerFixture()
    await server.setFailure(.offline)
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(server: server, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    let pending = try #require(try await store.load().pending)
    await server.setFailure(nil)
    let report = await coordinator.importHistory(selection: .init(metrics: [.sleepDuration]))
    #expect(report.archiveState == .paused)
    #expect(try await store.load().pending == pending)
    #expect(try await store.load().selection?.metrics == [.steps])
  }

  @Test func anotherTypesOlderGapCannotReplacePendingBatch() async throws {
    let server = ArchiveServerFixture()
    await server.setFailure(.offline, type: .stepCount)
    let query = ArchiveQueryFixture()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, server: server, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.bodyMass, .steps]))
    let pending = try #require(try await store.load().pending)
    let sentCount = await server.batches.count
    await query.setHistory(start: 50, boundary: nil)
    await server.setFailure(nil)
    _ = await coordinator.resume()
    #expect(await server.batches[sentCount] == pending.batch)
  }

  @Test func restrictionCannotReplayPendingCursorBelowNewBoundary() async throws {
    let server = ArchiveServerFixture()
    await server.setFailure(.offline)
    let query = ArchiveQueryFixture()
    let store = InMemoryArchiveCheckpointStore()
    let coordinator = makeCoordinator(query: query, server: server, store: store)
    _ = await coordinator.importHistory(selection: .init(metrics: [.steps]))
    let pending = try #require(try await store.load().pending)
    await query.setHistory(start: 150, boundary: 150)
    await server.setFailure(nil)
    _ = await coordinator.resume()
    let report = await coordinator.resume()
    #expect(report.failures.first?.issue == .permissionRestricted)
    #expect(await server.batches.count == 1)
    #expect(try await store.load().pending == pending)
  }

  @Test func sparseDecadeUsesBoundedWindowsWithoutFabricatingArchiveWrites() async throws {
    let query = ArchiveQueryFixture()
    await query.setEmpty()
    await query.setHistory(start: -365 * 86400 * 10, boundary: nil)
    await query.setWindowing()
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let report = await makeCoordinator(query: query, server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    #expect(await query.windows.count == 122)
    #expect(await query.windows.allSatisfy { $0.duration <= 30 * 86400 })
    #expect(await server.batches.isEmpty)
    #expect(try await store.load().types[.stepCount]?.coverage.intervals.count == 1)
  }

  @Test func overlapDuplicatesAreNotUploadedAgainAndDistinctSameTimeSamplesSurvive() async throws {
    let query = ArchiveQueryFixture()
    await query.setCount(7)
    await query.setOverlap()
    let server = ArchiveServerFixture()
    await server.setLimits(samples: 3, bytes: 262144)
    let report = await makeCoordinator(query: query, server: server).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    #expect(await server.batches.flatMap(\.samples).count == 7)
  }

  @Test func oversizedSingleSampleFailsWithoutJournalOrCoverage() async throws {
    let server = ArchiveServerFixture()
    await server.setLimits(samples: 200, bytes: 100)
    let store = InMemoryArchiveCheckpointStore()
    let report = await makeCoordinator(server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(report.failures.first?.category == .validation)
    #expect(await server.batches.isEmpty)
    #expect(try await store.load().pending == nil)
    #expect(try await store.load().types[.stepCount]?.coverage.intervals.isEmpty == true)
  }

  @Test func deletionDuringInitialScanIsCaughtByPreexistingGlobalAnchor() async throws {
    let query = ArchiveQueryFixture()
    await query.setDeletionDuringScan()
    let server = ArchiveServerFixture()
    let store = InMemoryArchiveCheckpointStore()
    let report = await makeCoordinator(query: query, server: server, store: store).importHistory(
      selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    #expect(
      await server.batches.flatMap(\.deletions).map(\.uuid) == [
        "00000000-0000-4000-8000-000000000001"
      ])
    #expect(try await store.load().types[.stepCount]?.coverage.intervals == [query.interval])
  }

  @Test func phasesRunFromPreparingThroughArchivingAndCheckingToIdle() async throws {
    let recorder = ArchiveProgressRecorder()
    let report = await makeCoordinator(progress: { await recorder.record($0) })
      .importHistory(selection: .init(metrics: [.steps]))
    let phases = await recorder.phases
    #expect(phases.first == .preparing)
    let archiving = try #require(phases.firstIndex(of: .archiving(.stepCount)))
    let checking = try #require(phases.firstIndex(of: .checking(.stepCount)))
    #expect(archiving < checking)
    #expect(phases.last == .idle)
    #expect(report.phase == .idle)
    #expect(report.typeProgress[.stepCount]?.fraction == 1)
    #expect(report.typeProgress[.stepCount]?.isComplete == true)
  }

  @Test func rateLimitWaitIsReportedWithItsResumeTime() async throws {
    let server = ArchiveServerFixture()
    await server.rateLimitNextBatch(retryAfter: 0.01)
    let recorder = ArchiveProgressRecorder()
    _ = await makeCoordinator(server: server, progress: { await recorder.record($0) })
      .importHistory(selection: .init(metrics: [.steps]))
    let phases = await recorder.phases
    let waitIndex = try #require(
      phases.firstIndex {
        if case .waiting = $0 { return true }
        return false
      })
    guard case .waiting(let until) = phases[waitIndex] else { return }
    #expect(abs(until.timeIntervalSince1970 - 200.01) < 0.001)
    #expect(phases[waitIndex + 1] == .archiving(.stepCount))
  }

  @Test func pauseDuringWaitEndsIdle() async throws {
    let server = ArchiveServerFixture()
    await server.rateLimitNextBatch(retryAfter: 30)
    let recorder = ArchiveProgressRecorder()
    let coordinator = makeCoordinator(server: server, progress: { await recorder.record($0) })
    let run = Task { await coordinator.importHistory(selection: .init(metrics: [.steps])) }
    var yields = 0
    while await !recorder.phases.contains(where: {
      if case .waiting = $0 { return true }
      return false
    }) {
      yields += 1
      try #require(yields < 100_000, "the import never reported a rate-limit wait")
      await Task.yield()
    }
    await coordinator.pause()
    let report = await run.value
    #expect(report.phase == .idle)
    #expect(await recorder.reports.last?.phase == .idle)
  }

  @Test func finishedTypeIsCompleteEvenThoughTheClockKeepsMoving() async throws {
    let clock = ArchiveTickingClock()
    let report = await makeCoordinator(now: { clock.next() })
      .importHistory(selection: .init(metrics: [.steps]))
    #expect(report.archiveState == .archived)
    #expect(report.typeProgress[.stepCount]?.fraction == 1)
    #expect(report.typeProgress[.stepCount]?.isComplete == true)
  }

  @Test func resumedImportReportsEarlierProgressFirst() async throws {
    var state = ArchiveImportCheckpoint()
    state.uploaderFingerprint = "0123456789ab"
    state.ownerGeneration = 1
    state.selection = .init(metrics: [.steps])
    state.metricEarliestDates = [.steps: Date(timeIntervalSince1970: 100)]
    var steps = ArchiveTypeCheckpoint()
    steps.coverage.insert(
      DateInterval(
        start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 150)))
    steps.scanInterval = DateInterval(
      start: Date(timeIntervalSince1970: 150), end: Date(timeIntervalSince1970: 200))
    state.types[.stepCount] = steps
    state.archivedSamples = 7
    let recorder = ArchiveProgressRecorder()
    let report = await makeCoordinator(
      store: InMemoryArchiveCheckpointStore(state: state),
      progress: { await recorder.record($0) }
    ).importHistory(selection: .init(metrics: [.steps]))
    // The very first emission already shows the saved progress; nothing flickers to empty.
    let first = await recorder.reports.first
    #expect(first?.phase == .preparing)
    #expect(first?.typeProgress[.stepCount]?.fraction == 0.5)
    #expect(first?.archivedSamples == 7)
    #expect(report.typeProgress[.stepCount]?.fraction == 1)
  }

  private func makeCoordinator(
    query: ArchiveQueryFixture = ArchiveQueryFixture(),
    server: ArchiveServerFixture = ArchiveServerFixture(),
    store: any ArchiveCheckpointStore = InMemoryArchiveCheckpointStore(),
    access: any PaidFeatureAccessing = ImportPaidAccessFixture(),
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 200) },
    progress: @escaping @Sendable (ArchiveImportReport) async -> Void = { _ in }
  ) -> ArchiveImportCoordinator {
    ArchiveImportCoordinator(
      access: access,
      query: query, checkpointStore: store,
      connection: {
        ArchiveImportConnection(
          baseURL: try NormalizedBaseURL.parse(
            "https://example.invalid", allowConfirmedLocalHTTP: false),
          userID: "fixture-user", token: "fixture-secret",
          capability: try await server.capability(),
          sender: server, statusFetcher: server,
          uploaderFingerprint: "0123456789ab")
      }, now: now, progress: progress)
  }
}

private actor ArchiveQueryFixture: HealthArchiveQuerying {
  nonisolated let interval = DateInterval(
    start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
  var start = 100.0
  var boundary: Date?
  var count = 1
  var pages: [DateInterval] = []
  var windows: [DateInterval] = []
  var windowing = false
  var overlap = false
  var changeFailure: ArchiveQueryError?
  var corrections = false
  var deletionDuringScan = false
  var noReadable = false
  var deletedLast = false
  var initialSnapshot = false
  var changeCalls = 0
  var initialSnapshotCalls = 0
  var anchoredSample: ArchiveSample?
  func addAnchoredSample(start: String, correction: Bool = false) throws {
    let original = try sample(index: correction ? 0 : 1)
    anchoredSample = ArchiveSample(
      uuid: original.uuid, start: start, end: start, source: original.source,
      timeZone: original.timeZone, metadata: original.metadata, payload: original.payload)
  }
  func deleteLastReadableSample() {
    noReadable = true
    deletedLast = true
    count = 0
  }
  func setInitialSnapshot() { initialSnapshot = true }
  func setHistory(start: Double, boundary: Double?) {
    self.start = start
    self.boundary = boundary.map { Date(timeIntervalSince1970: $0) }
  }
  func setChangeFailure(_ error: ArchiveQueryError?) { changeFailure = error }
  func setEmpty() { count = 0 }
  func setCount(_ value: Int) { count = value }
  func setCorrections() { corrections = true }
  func setDeletionDuringScan() { deletionDuringScan = true }
  func setWindowing() { windowing = true }
  func setOverlap() { overlap = true }
  func discover(types: Set<HealthObjectTypeID>) -> [HealthObjectTypeID: ReadableHistory] {
    Dictionary(
      uniqueKeysWithValues: types.map {
        (
          $0,
          noReadable
            ? .noReadableSamples(authorizationBoundary: boundary)
            : .readable(
              earliest: Date(timeIntervalSince1970: start), authorizationBoundary: boundary)
        )
      })
  }
  func discover(metrics: [MetricDefinition]) -> ArchiveHistoryDiscovery {
    ArchiveHistoryDiscovery(
      types: discover(types: Set(metrics.map(\.healthObjectType))),
      metrics: Dictionary(
        uniqueKeysWithValues: metrics.map {
          (
            $0.id,
            noReadable
              ? .noReadableSamples(authorizationBoundary: boundary)
              : .readable(
                earliest: Date(timeIntervalSince1970: $0.id == .sleepREM ? 150 : start),
                authorizationBoundary: boundary)
          )
        }))
  }
  func page(
    type: HealthObjectTypeID, interval: DateInterval, cursor: ArchiveScanCursor?, limit: Int
  ) throws -> ArchiveSamplePage {
    pages.append(interval)
    if windowing {
      let start = cursor?.windowStart ?? interval.start
      let end = min(start.addingTimeInterval(30 * 86400), interval.end)
      let window = DateInterval(start: start, end: end)
      windows.append(window)
      return ArchiveSamplePage(
        samples: [], deletedSampleIDs: [], coveredInterval: window,
        isWindowComplete: true,
        nextCursor: end == interval.end
          ? nil
          : ArchiveScanCursor(
            type: type, interval: interval, windowStart: end,
            windowEnd: min(end.addingTimeInterval(30 * 86400), interval.end), anchor: nil))
    }
    let offset = Int(cursor?.anchor?.first ?? 0)
    let upper = min(count, offset + limit)
    let complete = upper >= count
    let added =
      anchoredSample.map { sample in
        ArchiveWire.utcDate(sample.start).map { $0 >= interval.start && $0 < interval.end } == true
          ? [sample] : []
      } ?? []
    return ArchiveSamplePage(
      samples: try ((overlap ? max(0, offset - 1) : offset)..<upper).map { try sample(index: $0) }
        + added,
      deletedSampleIDs: [], coveredInterval: interval,
      isWindowComplete: complete,
      nextCursor: complete
        ? nil
        : ArchiveScanCursor(
          type: type, interval: interval, windowStart: interval.start, windowEnd: interval.end,
          anchor: Data([UInt8(upper)])))
  }
  func changes(type: HealthObjectTypeID, anchor: Data?) throws -> ArchiveChangePage {
    changeCalls += 1
    if let anchoredSample {
      return ArchiveChangePage(
        samples: anchor == Data([2]) ? [] : [anchoredSample], deletedSampleIDs: [],
        candidateAnchor: Data([2]), hasMore: false)
    }
    if initialSnapshot && anchor == nil {
      initialSnapshotCalls += 1
      let upper = min(count, 3)
      return ArchiveChangePage(
        samples: try (0..<upper).map { try sample(index: $0) }, deletedSampleIDs: [],
        candidateAnchor: Data([upper < count ? 20 : 1]), hasMore: upper < count)
    }
    if initialSnapshot && anchor == Data([20]) {
      return ArchiveChangePage(
        samples: try (3..<count).map { try sample(index: $0) }, deletedSampleIDs: [],
        candidateAnchor: Data([1]), hasMore: false)
    }
    if deletedLast {
      return ArchiveChangePage(
        samples: [],
        deletedSampleIDs: anchor == Data([1])
          ? [UUID(uuidString: "00000000-0000-4000-8000-000000000001")!] : [],
        candidateAnchor: Data([2]), hasMore: false)
    }
    if let error = changeFailure, !pages.isEmpty {
      changeFailure = nil
      throw error
    }
    let hasCorrections = corrections && !pages.isEmpty && anchor != nil
    let deleted: [UUID]
    if deletionDuringScan && !pages.isEmpty && anchor != nil {
      deleted = [UUID(uuidString: "00000000-0000-4000-8000-000000000001")!]
    } else {
      deleted = hasCorrections ? [UUID(uuidString: "00000000-0000-4000-8000-000000000099")!] : []
    }
    return ArchiveChangePage(
      samples: hasCorrections ? [try sample(value: 9)] : [],
      deletedSampleIDs: deleted, candidateAnchor: Data([1]), hasMore: false)
  }
  func sample(index: Int = 0, value: Int = 1) throws -> ArchiveSample {
    try JSONDecoder().decode(
      ArchiveSample.self,
      from: Data(
        """
        {"uuid":"00000000-0000-4000-8000-\(String(format: "%012d", index + 1))","start":"1970-01-01T00:01:40Z","end":"1970-01-01T00:01:41Z","source":{"bundle_id":"fixture.source","name":"Fixture","revision":"1"},"time_zone":"UTC","metadata":{},"payload":{"kind":"quantity","schema_version":1,"raw_value":\(value),"raw_unit":"count","canonical_value":\(value),"canonical_unit":"count"}}
        """.utf8))
  }
}

private actor ArchiveServerFixture: ArchiveBatchSending, ArchiveStatusFetching {
  var batches: [ArchiveBatch] = []
  var failure: NetworkFailure?
  var ownerError: ArchiveClientError?
  var statusError: ArchiveClientError?
  var ownerGeneration = 1
  var failureType: HealthObjectTypeID?
  var wrongReceipt = false
  var projection = "pending"
  var maxSamples = 200
  var maxBytes = 262144
  var shouldSuspend = false
  var isSendSuspended = false
  var sendWasCancelled = false
  var nextRateLimitDelay: TimeInterval?
  var sendContinuation: CheckedContinuation<Void, Never>?
  func suspendSend() { shouldSuspend = true }
  func rateLimitNextBatch(retryAfter: TimeInterval) { nextRateLimitDelay = retryAfter }
  func markSendCancelled() { sendWasCancelled = true }
  func releaseSend() {
    sendContinuation?.resume()
    sendContinuation = nil
    isSendSuspended = false
  }
  func setLimits(samples: Int, bytes: Int) {
    maxSamples = samples
    maxBytes = bytes
  }
  func setFailure(_ value: NetworkFailure?, type: HealthObjectTypeID? = nil) {
    failure = value
    failureType = type
  }
  func setOwnerError(_ value: ArchiveClientError?) { ownerError = value }
  func setStatusError(_ value: ArchiveClientError?) { statusError = value }
  func setOwnerGeneration(_ value: Int) { ownerGeneration = value }
  func setWrongReceipt() { wrongReceipt = true }
  func setProjection(_ value: String) { projection = value }
  func capability() throws -> ArchiveCapability {
    try decode(
      """
      {"ok":true,"request_type":"archive_capability","protocol_version":2,"request_id":"capability.fixture","archive_schema_version":3,"ownership_contract_version":1,"owner_state":"active","owner_generation":\(ownerGeneration),"max_batch_bytes":\(maxBytes),"max_samples_per_batch":\(maxSamples),"max_deletions_per_batch":200,"supported_sample_types":["HKQuantityTypeIdentifierStepCount","HKQuantityTypeIdentifierBodyMass","HKCategoryTypeIdentifierSleepAnalysis"],"supported_metrics":["steps","body_mass","sleep_duration","sleep_rem_hours"],"archive_available":true,"statistics_available":true}
      """)
  }
  func send(_ batch: ArchiveBatch, baseURL: NormalizedBaseURL) async throws
    -> ArchiveAcknowledgement
  {
    batches.append(batch)
    if let ownerError { throw ownerError }
    if let nextRateLimitDelay {
      self.nextRateLimitDelay = nil
      throw NetworkFailure.rateLimited(retryAfter: nextRateLimitDelay)
    }
    if shouldSuspend {
      shouldSuspend = false
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          sendContinuation = continuation
          isSendSuspended = true
        }
      } onCancel: {
        Task { await self.markSendCancelled() }
      }
    }
    if let failure, failureType == nil || batch.sampleType == failureType?.rawValue {
      throw failure
    }
    return try decode(
      """
      {"ok":true,"archive_commit":"committed","protocol_version":2,"request_id":"\(batch.requestID)","batch_id":"\(wrongReceipt ? "wrong.batch" : batch.batchID)","received_samples":\(batch.samples.count),"committed_samples":\(batch.samples.count),"received_deletions":\(batch.deletions.count),"committed_deletions":\(batch.deletions.count),"projection_state":"pending"}
      """)
  }
  func status(requestID: String, baseURL: NormalizedBaseURL) throws -> ArchiveProjectionStatus {
    if let statusError { throw statusError }
    return try decode(
      """
      {"ok":true,"request_type":"archive_status","protocol_version":2,"request_id":"\(requestID)","metrics":[{"metric":"steps","state":"\(projection)","last_error":null}]}
      """)
  }
  private func decode<Value: Decodable>(_ text: String) throws -> Value {
    try JSONDecoder().decode(Value.self, from: Data(text.utf8))
  }
}

private actor InterruptingArchiveStore: ArchiveCheckpointStore {
  var state = ArchiveImportCheckpoint()
  var interrupt = true
  let cancel: Bool
  init(cancel: Bool = false) { self.cancel = cancel }
  func load() -> ArchiveImportCheckpoint { state }
  func save(_ value: ArchiveImportCheckpoint) throws {
    if interrupt && state.pending != nil && value.pending == nil {
      interrupt = false
      if cancel { throw CancellationError() }
      throw ArchiveCheckpointStoreError.unavailable
    }
    _ = try ArchiveCheckpointCodec.encode(value)
    state = value
  }
  func reset() { state = ArchiveImportCheckpoint() }
}

private actor ArchiveProgressRecorder {
  var reports: [ArchiveImportReport] = []
  func record(_ report: ArchiveImportReport) { reports.append(report) }
  /// Phases with consecutive duplicates removed.
  var phases: [ArchiveImportPhase] {
    reports.map(\.phase).reduce(into: []) { result, phase in
      if result.last != phase { result.append(phase) }
    }
  }
}

/// A clock that advances 1 ms on every read, like a real one during an import.
private final class ArchiveTickingClock: @unchecked Sendable {
  private let lock = NSLock()
  private var seconds = 200.0
  func next() -> Date {
    lock.lock()
    defer { lock.unlock() }
    seconds += 0.001
    return Date(timeIntervalSince1970: seconds)
  }
}
