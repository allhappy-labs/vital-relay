import Foundation

public actor ArchiveImportCoordinator: ArchiveImportCoordinating {
  private let access: any PaidFeatureAccessing
  private let query: any HealthArchiveQuerying
  private let checkpointStore: any ArchiveCheckpointStore
  private let connection: @Sendable () async throws -> ArchiveImportConnection
  private let now: @Sendable () -> Date
  private let progress: @Sendable (ArchiveImportReport) async -> Void
  private var activeTask: Task<ArchiveImportReport, Never>?
  private var report = ArchiveImportReport()

  public init(
    access: any PaidFeatureAccessing,
    query: any HealthArchiveQuerying, checkpointStore: any ArchiveCheckpointStore,
    connection: @escaping @Sendable () async throws -> ArchiveImportConnection,
    now: @escaping @Sendable () -> Date = { Date() },
    progress: @escaping @Sendable (ArchiveImportReport) async -> Void = { _ in }
  ) {
    self.access = access
    self.query = query
    self.checkpointStore = checkpointStore
    self.connection = connection
    self.now = now
    self.progress = progress
  }

  public func importHistory(selection: ArchiveImportSelection) async -> ArchiveImportReport {
    if let activeTask { return await activeTask.value }
    let task = Task { await self.perform(selection: selection) }
    activeTask = task
    let result = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    activeTask = nil
    return result
  }

  public func pause() async {
    guard let task = activeTask else { return }
    task.cancel()
    _ = await task.value
  }

  public func resume() async -> ArchiveImportReport {
    if let activeTask { return await activeTask.value }
    do {
      guard let selection = try await checkpointStore.load().selection else { return report }
      return await importHistory(selection: selection)
    } catch {
      report.failures = [Self.failure(error, fallback: .checkpoint)]
      report.archiveState = .paused
      return report
    }
  }

  /// Can be called repeatedly by UI refresh; never reads or uploads HealthKit samples.
  public func refreshProjection() async -> ArchiveImportReport {
    do { try await pollProjection(connection()) } catch {
      report.failures.append(Self.failure(error, fallback: .transport))
      if Self.isOwnershipFailure(error) { report.archiveState = .paused }
    }
    await progress(report)
    return report
  }

  private func perform(selection: ArchiveImportSelection) async -> ArchiveImportReport {
    report = ArchiveImportReport()
    report.archiveState = .importing
    var currentType: HealthObjectTypeID?
    var fallback = SyncFailureCategory.configuration
    do {
      try await requireAccess()
      let connection = try await connection()
      try connection.capability.validate(requestID: connection.capability.requestID)
      guard connection.capability.archiveAvailable,
        connection.capability.supportsOwnershipContract,
        let fingerprint = connection.uploaderFingerprint,
        let ownerGeneration = connection.capability.ownerGeneration,
        ownerGeneration > 0
      else { throw NetworkFailure.protocolMismatch }
      switch connection.capability.ownerState {
      case .active: break
      case .pending: throw ArchiveClientError.ownerPending
      case .unbound: throw ArchiveClientError.ownerRequired
      case .notOwner: throw ArchiveClientError.ownerChanged
      case nil: throw NetworkFailure.protocolMismatch
      }
      fallback = .checkpoint
      var state = try await checkpointStore.load()
      guard
        !state.hasPreviousWork
          || (state.uploaderFingerprint == fingerprint && state.ownerGeneration == ownerGeneration)
      else {
        throw ArchiveImportIssue.checkpointOwnerMismatch
      }
      state.uploaderFingerprint = fingerprint
      state.ownerGeneration = ownerGeneration
      report.archivedSamples = state.archivedSamples
      report.archivedDeletions = state.archivedDeletions
      let destination = connection.baseURL.url.absoluteString
      guard
        state.destination == nil
          || (state.destination == destination && state.userID == connection.userID)
      else {
        report.failures = [.init(category: .configuration, issue: .destinationChanged)]
        report.archiveState = .paused
        return report
      }
      state.destination = destination
      state.userID = connection.userID
      guard state.pending == nil || state.selection == selection else {
        report.failures = [.init(category: .configuration)]
        report.archiveState = .paused
        return report
      }
      if state.selection != selection {
        for type in state.types.keys {
          state.types[type]?.scanInterval = nil
          state.types[type]?.cursor = nil
          state.types[type]?.scanned = ArchiveIntervals()
        }
      }
      state.selection = selection
      let definitions = selection.metrics.compactMap { MetricRegistry[$0] }
      guard definitions.count == selection.metrics.count,
        definitions.allSatisfy({
          $0.availability == .available
            && connection.capability.supportedMetrics.contains($0.id.rawValue)
            && connection.capability.supportedSampleTypes.contains($0.healthObjectType.rawValue)
        })
      else { throw NetworkFailure.protocolMismatch }
      try await save(state)
      fallback = .healthKit
      let discovery = try await query.discover(metrics: definitions)
      state.metricEarliestDates = discovery.metrics.compactMapValues {
        if case .readable(let date, _) = $0 { return date }
        return nil
      }
      report.metricEarliestDates = state.metricEarliestDates
      report.noReadableMetrics = Set(
        discovery.metrics.compactMap {
          if case .noReadableSamples = $0.value { return $0.key }
          return nil
        })
      // Resolve the one durable journal before any other type can create a batch.
      if let pending = state.pending {
        currentType = pending.type
        let boundary: Date?
        switch discovery.types[pending.type] {
        case .readable(_, let value), .noReadableSamples(let value): boundary = value
        case nil: throw ArchiveValidationError.invalidResponse
        }
        if pending.batch.expectedInventoryRevision != nil {
          // The wire date has millisecond precision; the journal retains the
          // native proof so unchanged fractional boundaries can retry exactly.
          guard case .readable = discovery.types[pending.type], let boundary,
            pending.nextCheckpoint.observedAuthorizationBoundary == boundary
          else { throw ArchiveReconciliationError.authorizationUnproven }
        }
        let replayLowerBound =
          pending.nextCheckpoint.observedAuthorizationBoundary
          ?? pending.batch.coverage.start.flatMap(ArchiveWire.utcDate)
        if let boundary, let start = replayLowerBound,
          boundary > start
        {
          report.failures = [
            .init(type: pending.type, category: .healthKit, issue: .permissionRestricted)
          ]
          report.archiveState = .paused
          return report
        }
        do {
          try await sendPending(state: &state, connection: connection)
        } catch ArchiveClientError.inventoryChanged
          where pending.batch.expectedInventoryRevision != nil
        {
          // A rejected conditional transaction has no receipt or mutations. Rebuild its proof.
          state.pending = nil
          state.types[pending.type]?.inventoryComparison = nil
          try await save(state)
        }
      }
      let end = now()
      for type in Set(definitions.map(\.healthObjectType)).sorted(by: { $0.rawValue < $1.rawValue })
      {
        currentType = type
        try Task.checkCancellation()
        guard let history = discovery.types[type] else {
          throw ArchiveValidationError.invalidResponse
        }
        var checkpoint = state.types[type] ?? ArchiveTypeCheckpoint()
        let earliest: Date?
        let boundary: Date?
        switch history {
        case .readable(let date, let value):
          earliest = date
          boundary = value
        case .noReadableSamples(let value):
          earliest = nil
          boundary = value
        }
        let priorLower =
          checkpoint.observedAuthorizationBoundary
          ?? checkpoint.scanInterval?.start ?? checkpoint.coverage.intervals.first?.start
          ?? checkpoint.scanned.intervals.first?.start
        checkpoint.observedAuthorizationBoundary = boundary
        if let boundary, let priorLower, boundary > priorLower, !checkpoint.reconciliationRequired {
          checkpoint.cursor = nil
          checkpoint.scanInterval = nil
          checkpoint.scanned = ArchiveIntervals()
          state.types[type] = checkpoint
          try await save(state)
          report.failures.append(
            .init(type: type, category: .healthKit, issue: .permissionRestricted))
          continue
        }
        state.types[type] = checkpoint
        try await save(state)
        guard let earliest else {
          // No readable originals does not mean there are no deletion events. Only
          // actual anchored events can remove remote rows; absence alone cannot.
          if checkpoint.anchor != nil || checkpoint.baselineAnchor != nil,
            let priorStart =
              ([checkpoint.scanInterval].compactMap { $0 }
              + checkpoint.coverage.intervals + checkpoint.scanned.intervals).map(\.start).min()
          {
            let start = max(priorStart, boundary ?? priorStart)
            if start < end {
              do {
                try await reconcile(
                  type: type, interval: DateInterval(start: start, end: end),
                  state: &state, connection: connection)
              } catch ArchiveQueryError.anchorInvalidated {
                try await invalidate(type: type, state: &state)
              }
            }
          }
          if state.types[type]?.reconciliationRequired == true {
            report.failures.append(
              .init(type: type, category: .healthKit, issue: .reconciliationRequired))
          }
          report.failures.append(.init(type: type, category: .healthKit, issue: .noReadableSamples))
          continue
        }
        let start = max(earliest, selection.requestedStart ?? earliest, boundary ?? earliest)
        guard start < end else {
          if checkpoint.reconciliationRequired {
            report.failures.append(
              .init(type: type, category: .healthKit, issue: .reconciliationRequired))
          }
          continue
        }
        let interval = DateInterval(start: start, end: end)
        fallback = .healthKit
        var beforeReconciliation = state.types[type]
        do {
          if state.types[type]?.anchor == nil && state.types[type]?.baselineAnchor == nil {
            try await establishBaseline(type: type, interval: interval, state: &state)
          }
          try await scan(type: type, interval: interval, state: &state, connection: connection)
          beforeReconciliation = state.types[type]
          try await reconcile(type: type, interval: interval, state: &state, connection: connection)
        } catch ArchiveQueryError.anchorInvalidated {
          try await invalidate(type: type, state: &state)
          try await establishBaseline(type: type, interval: interval, state: &state)
          try await scan(type: type, interval: interval, state: &state, connection: connection)
          beforeReconciliation = state.types[type]
          try await reconcile(type: type, interval: interval, state: &state, connection: connection)
        }
        if state.types[type]?.reconciliationRequired == true {
          do {
            try await reconcileInventory(
              type: type, interval: interval, state: &state, connection: connection)
          } catch ArchiveClientError.ownerChanged {
            state.types[type]?.anchor = beforeReconciliation?.anchor
            state.types[type]?.coverage = beforeReconciliation?.coverage ?? ArchiveIntervals()
            try await save(state)
            throw ArchiveClientError.ownerChanged
          } catch ArchiveClientError.ownerPending {
            state.types[type]?.anchor = beforeReconciliation?.anchor
            state.types[type]?.coverage = beforeReconciliation?.coverage ?? ArchiveIntervals()
            try await save(state)
            throw ArchiveClientError.ownerPending
          } catch ArchiveClientError.ownerRequired {
            state.types[type]?.anchor = beforeReconciliation?.anchor
            state.types[type]?.coverage = beforeReconciliation?.coverage ?? ArchiveIntervals()
            try await save(state)
            throw ArchiveClientError.ownerRequired
          }
        }
        if state.types[type]?.reconciliationRequired == true {
          report.failures.append(
            .init(type: type, category: .healthKit, issue: .reconciliationRequired))
        }
        report.archivedSamples = state.archivedSamples
        report.archivedDeletions = state.archivedDeletions
        await progress(report)
      }
      report.archiveState = report.failures.isEmpty ? .archived : .paused
      fallback = .transport
      try await pollProjection(connection)
    } catch {
      report.failures.append(Self.failure(error, type: currentType, fallback: fallback))
      // A projection failure must not roll back an already committed archive.
      if report.archiveState != .archived || Self.isOwnershipFailure(error) {
        report.archiveState = .paused
      }
    }
    await progress(report)
    return report
  }

  private func invalidate(type: HealthObjectTypeID, state: inout ArchiveImportCheckpoint)
    async throws
  {
    var checkpoint = state.types[type]!
    var scope = checkpoint.reconciliationIntervals ?? ArchiveIntervals()
    for interval in checkpoint.coverage.intervals + checkpoint.scanned.intervals
      + [checkpoint.scanInterval].compactMap({ $0 })
    {
      scope.insert(interval)
    }
    checkpoint.reconciliationIntervals = scope
    checkpoint.inventoryComparison = nil
    checkpoint.coverage = ArchiveIntervals()
    checkpoint.scanned = ArchiveIntervals()
    checkpoint.cursor = nil
    checkpoint.scanInterval = nil
    checkpoint.anchor = nil
    checkpoint.baselineAnchor = nil
    checkpoint.reconciliationRequired = true
    state.types[type] = checkpoint
    try await save(state)
  }

  private func establishBaseline(
    type: HealthObjectTypeID, interval: DateInterval,
    state: inout ArchiveImportCheckpoint
  ) async throws {
    // Nil-anchor enumeration returns the existing originals. Observe its final
    // position without uploading them: bounded interval scans own those uploads.
    // A distinct persisted baseline preserves subsequent changes across restarts
    // without claiming these observed originals have been acknowledged.
    var anchor: Data?
    while true {
      try Task.checkCancellation()
      let page = try await query.changes(type: type, anchor: anchor)
      guard !page.hasMore || page.candidateAnchor != anchor else {
        throw ArchiveValidationError.invalidResponse
      }
      anchor = page.candidateAnchor
      if !page.hasMore {
        state.types[type]?.baselineAnchor = anchor
        // Preserve the intended range if discovery becomes empty before scanning.
        if state.types[type]?.scanInterval == nil { state.types[type]?.scanInterval = interval }
        try await save(state)
        return
      }
    }
  }

  private func scan(
    type: HealthObjectTypeID, interval: DateInterval,
    state: inout ArchiveImportCheckpoint, connection: ArchiveImportConnection
  ) async throws {
    var seen: [String: ArchiveSample] = [:]
    while true {
      try Task.checkCancellation()
      var checkpoint = state.types[type]!
      if checkpoint.scanInterval == nil {
        var scanned = checkpoint.coverage
        for window in checkpoint.scanned.intervals { scanned.insert(window) }
        guard let gap = scanned.gaps(in: interval).first else { return }
        checkpoint.scanInterval = gap
        checkpoint.cursor = nil
        state.types[type] = checkpoint
        try await save(state)
      }
      let scanInterval = checkpoint.scanInterval!
      let page = try await query.page(
        type: type, interval: scanInterval, cursor: checkpoint.cursor,
        limit: connection.capability.maxSamplesPerBatch)
      guard page.coveredInterval.start >= scanInterval.start,
        page.coveredInterval.end <= scanInterval.end,
        page.coveredInterval.duration > 0,
        page.isWindowComplete || page.nextCursor != nil,
        page.nextCursor == nil || page.nextCursor != checkpoint.cursor
      else { throw ArchiveValidationError.invalidResponse }
      var next = checkpoint
      if page.isWindowComplete { next.scanned.insert(page.coveredInterval) }
      next.cursor = page.nextCursor
      if page.nextCursor == nil { next.scanInterval = nil }
      let samples = page.samples.filter { seen[$0.uuid.lowercased()] != $0 }
      try await upload(
        samples: samples, deletions: page.deletedSampleIDs, type: type,
        interval: page.coveredInterval, next: next, state: &state, connection: connection)
      // Bound overlap dedup memory independently of historical duration.
      if seen.count + page.samples.count > 1000 { seen.removeAll(keepingCapacity: true) }
      for sample in page.samples { seen[sample.uuid.lowercased()] = sample }
    }
  }

  private func reconcile(
    type: HealthObjectTypeID, interval: DateInterval,
    state: inout ArchiveImportCheckpoint, connection: ArchiveImportConnection
  ) async throws {
    while true {
      try Task.checkCancellation()
      let checkpoint = state.types[type]!
      let anchor = checkpoint.anchor ?? checkpoint.baselineAnchor
      let page = try await query.changes(type: type, anchor: anchor)
      guard !page.hasMore || page.candidateAnchor != anchor else {
        throw ArchiveValidationError.invalidResponse
      }
      var next = checkpoint
      next.anchor = page.candidateAnchor
      next.baselineAnchor = nil
      if !page.hasMore && !next.reconciliationRequired {
        for window in next.scanned.intervals { next.coverage.insert(window) }
        next.scanned = ArchiveIntervals()
      }
      let samples = try page.samples.filter {
        guard let start = ArchiveWire.utcDate($0.start), let end = ArchiveWire.utcDate($0.end)
        else {
          throw ArchiveValidationError.invalidSample
        }
        // Match the overlapping historical predicate for corrections to crossing intervals.
        let included =
          start < interval.end && end >= interval.start
          && (checkpoint.observedAuthorizationBoundary.map { start >= $0 } ?? true)
        if !included {
          // The global anchor consumes this event even outside the selected range.
          // A correction can move an existing UUID from an unknown older interval,
          // so discard coverage proof and let a later wider scan revisit originals.
          // This never infers a deletion from missing or inaccessible samples.
          next.coverage = ArchiveIntervals()
          next.scanned = ArchiveIntervals()
        }
        return included
      }
      try await upload(
        samples: samples, deletions: page.deletedSampleIDs, type: type,
        interval: interval, next: next, state: &state, connection: connection)
      if !page.hasMore { return }
    }
  }

  private func upload(
    samples: [ArchiveSample], deletions: [UUID], type: HealthObjectTypeID,
    interval: DateInterval, next: ArchiveTypeCheckpoint, state: inout ArchiveImportCheckpoint,
    connection: ArchiveImportConnection, expectedInventoryRevision: Int64? = nil,
    expectedOwnerGeneration: Int? = nil
  ) async throws {
    let deleted = Set(deletions.map { $0.uuidString.lowercased() })
    var unique: [String: ArchiveSample] = [:]
    for sample in samples where !deleted.contains(sample.uuid.lowercased()) {
      unique[sample.uuid.lowercased()] = sample
    }
    let samples = unique.values.sorted { $0.uuid < $1.uuid }
    let deletions = deleted.sorted().map { ArchiveDeletion(uuid: $0) }
    var sampleIndex = 0
    var deletionIndex = 0
    while sampleIndex < samples.count || deletionIndex < deletions.count {
      try Task.checkCancellation()
      let id = "archive.\(UUID().uuidString.lowercased())"
      var count = min(connection.capability.maxSamplesPerBatch, samples.count - sampleIndex)
      var deletionCount = min(
        connection.capability.maxDeletionsPerBatch, deletions.count - deletionIndex)
      var batch: ArchiveBatch
      while true {
        batch = ArchiveBatch(
          requestID: id, userID: connection.userID, batchID: id,
          sampleType: type.rawValue,
          coverage: ArchiveCoverage(
            kind: "interval", start: Self.utc(interval.start), end: Self.utc(interval.end),
            authorizationStart: state.types[type]?.observedAuthorizationBoundary.map(Self.utc)),
          samples: Array(samples[sampleIndex..<(sampleIndex + count)]),
          deletions: Array(deletions[deletionIndex..<(deletionIndex + deletionCount)]),
          expectedInventoryRevision: expectedInventoryRevision,
          expectedOwnerGeneration: expectedOwnerGeneration)
        if try Self.requestBytes(batch, token: connection.token)
          <= connection.capability.maxBatchBytes
        {
          break
        }
        guard count + deletionCount > 1 else { throw ArchiveClientError.requestTooLarge }
        if count >= deletionCount && count > 0 {
          count = max(0, count / 2)
        } else {
          deletionCount /= 2
        }
      }
      try batch.validate(
        maxBytes: connection.capability.maxBatchBytes,
        maxSamples: connection.capability.maxSamplesPerBatch,
        maxDeletions: connection.capability.maxDeletionsPerBatch)
      let final =
        sampleIndex + count == samples.count && deletionIndex + deletionCount == deletions.count
      state.pending = ArchivePendingBatch(
        type: type, batch: batch,
        nextCheckpoint: final ? next : state.types[type]!)
      try await save(state)
      try await sendPending(state: &state, connection: connection)
      // Each conditional receipt invalidates the comparison revision. Re-inventory
      // rather than sending the remainder under an already consumed revision.
      if expectedInventoryRevision != nil { return }
      sampleIndex += count
      deletionIndex += deletionCount
    }
    if samples.isEmpty && deletions.isEmpty {
      // The wire protocol has no empty batch; no remote mutation needs acknowledging.
      state.types[type] = next
      try await save(state)
    }
  }

  private func sendPending(
    state: inout ArchiveImportCheckpoint, connection: ArchiveImportConnection
  ) async throws {
    guard let pending = state.pending else { return }
    try await requireAccess()
    try Task.checkCancellation()
    try pending.batch.validate(
      maxBytes: connection.capability.maxBatchBytes,
      maxSamples: connection.capability.maxSamplesPerBatch,
      maxDeletions: connection.capability.maxDeletionsPerBatch)
    guard
      try Self.requestBytes(pending.batch, token: connection.token)
        <= connection.capability.maxBatchBytes
    else {
      throw ArchiveClientError.requestTooLarge
    }
    let receipt = try await connection.sender.send(pending.batch, baseURL: connection.baseURL)
    do {
      try receipt.validate(
        requestID: pending.batch.requestID, batchID: pending.batch.batchID,
        samples: pending.batch.samples.count, deletions: pending.batch.deletions.count)
    } catch { throw NetworkFailure.protocolMismatch }
    // Save atomically with journal removal. Failure/cancellation leaves the exact pending batch on disk.
    var committed = state
    committed.types[pending.type] = pending.nextCheckpoint
    committed.types[pending.type]?.lastCommittedBatchID = receipt.batchID
    committed.archivedSamples += receipt.committedSamples
    committed.archivedDeletions += receipt.committedDeletions
    committed.pending = nil
    try await save(committed)
    state = committed
    report.archivedSamples = state.archivedSamples
    report.archivedDeletions = state.archivedDeletions
    await progress(report)
  }

  private func requireAccess() async throws {
    guard await access.accessState() == .unlocked else {
      throw ArchiveImportIssue.purchaseRequired
    }
  }

  private func reconcileInventory(
    type: HealthObjectTypeID, interval: DateInterval,
    state: inout ArchiveImportCheckpoint, connection: ArchiveImportConnection
  ) async throws {
    guard connection.capability.supportsOwnershipContract, connection.inventoryFetcher != nil else {
      throw ArchiveReconciliationError.inventoryUnavailable
    }
    let originalCheckpoint = state.types[type]
    var scope = state.types[type]?.reconciliationIntervals ?? ArchiveIntervals()
    scope.insert(interval)
    for scanned in state.types[type]?.scanned.intervals ?? [] { scope.insert(scanned) }
    state.types[type]?.reconciliationIntervals = scope
    state.types[type]?.coverage = ArchiveIntervals()
    state.types[type]?.inventoryComparison = nil
    try await save(state)
    // Never restore an in-memory UUID set or trust a persisted cursor after interruption.
    let boundary = try await readableBoundary(type: type)
    state.types[type]?.observedAuthorizationBoundary = boundary
    var completed = ArchiveIntervals()
    do {
      for original in scope.intervals {
        // Enclose the historical wire extent so rounding cannot discard an
        // archived edge UUID. Authorization is a separate, inward-only floor.
        let historicalStart = Date(
          timeIntervalSince1970: (original.start.timeIntervalSince1970 * 1000).rounded(.down) / 1000
        )
        let authorizationStart = Date(
          timeIntervalSince1970: (boundary.timeIntervalSince1970 * 1000).rounded(.up) / 1000)
        let start = max(historicalStart, authorizationStart)
        let end = Date(
          timeIntervalSince1970: (original.end.timeIntervalSince1970 * 1000).rounded(.up) / 1000)
        guard start < end else { continue }
        let readable = DateInterval(start: start, end: end)
        try await compareInventory(
          type: type, interval: readable, boundary: boundary, state: &state, connection: connection)
        completed.insert(readable)
      }
      guard !completed.intervals.isEmpty else {
        throw ArchiveReconciliationError.authorizationUnproven
      }
      guard try await readableBoundary(type: type) == boundary else {
        throw ArchiveReconciliationError.authorizationUnproven
      }
      var committed = state
      committed.types[type]?.coverage = completed
      committed.types[type]?.scanned = ArchiveIntervals()
      committed.types[type]?.reconciliationRequired = false
      committed.types[type]?.reconciliationIntervals = nil
      committed.types[type]?.inventoryComparison = nil
      try await save(committed)
      state = committed
    } catch ArchiveClientError.ownerChanged {
      // Ownership rejection must retain the journal and the last durable local proof.
      state.types[type] = originalCheckpoint
      try await save(state)
      throw ArchiveClientError.ownerChanged
    } catch ArchiveClientError.ownerPending {
      state.types[type] = originalCheckpoint
      try await save(state)
      throw ArchiveClientError.ownerPending
    } catch ArchiveClientError.ownerRequired {
      state.types[type] = originalCheckpoint
      try await save(state)
      throw ArchiveClientError.ownerRequired
    } catch {
      state.types[type]?.inventoryComparison = nil
      // Partial comparisons never become durable coverage, even if a sibling window succeeded.
      state.types[type]?.coverage = ArchiveIntervals()
      try await save(state)
      throw error
    }
  }

  private func readableBoundary(type: HealthObjectTypeID) async throws -> Date {
    guard case .readable(_, let boundary) = try await query.discover(types: [type])[type],
      let boundary, boundary.timeIntervalSince1970.isFinite
    else { throw ArchiveReconciliationError.authorizationUnproven }
    return boundary
  }

  private func compareInventory(
    type: HealthObjectTypeID, interval: DateInterval, boundary: Date,
    state: inout ArchiveImportCheckpoint, connection: ArchiveImportConnection
  ) async throws {
    var conflicts = 0
    while true {
      try Task.checkCancellation()
      guard try await readableBoundary(type: type) == boundary else {
        throw ArchiveReconciliationError.authorizationUnproven
      }
      state.types[type]?.inventoryComparison = ArchiveInventoryComparison(interval: interval)
      try await save(state)
      do {
        // Pin the remote snapshot before reading local UUIDs. A concurrent uploader
        // during enumeration must invalidate this revision, not add "missing" IDs
        // to a newer remote snapshot compared with the older local enumeration.
        let firstRequest = ArchiveInventoryQuery(
          requestID: "inventory.\(UUID().uuidString.lowercased())", userID: connection.userID,
          sampleType: type.rawValue, start: Self.utc(interval.start), end: Self.utc(interval.end),
          limit: 200, cursor: nil)
        let firstPage = try await connection.inventoryFetcher!.page(
          query: firstRequest, baseURL: connection.baseURL)
        try firstPage.validate(query: firstRequest)
        let revision = firstPage.revision
        guard let generation = firstPage.ownerGeneration,
          generation == connection.capability.ownerGeneration
        else { throw ArchiveClientError.ownerChanged }
        state.types[type]?.inventoryComparison = ArchiveInventoryComparison(
          interval: interval, revision: revision)
        try await save(state)
        guard let readableIDs = try await readableIDs(type: type, interval: interval) else {
          // Millisecond wire precision is the smallest interval we can represent safely.
          let midpoint = Date(
            timeIntervalSince1970: ((interval.start.timeIntervalSince1970 + interval.duration / 2)
              * 1000).rounded(.down) / 1000)
          guard midpoint > interval.start, midpoint < interval.end else {
            throw ArchiveReconciliationError.intervalTooDense
          }
          try await compareInventory(
            type: type, interval: DateInterval(start: interval.start, end: midpoint),
            boundary: boundary,
            state: &state, connection: connection)
          try await compareInventory(
            type: type, interval: DateInterval(start: midpoint, end: interval.end),
            boundary: boundary,
            state: &state, connection: connection)
          return
        }
        var cursor: String?
        var missing: [UUID] = []
        repeat {
          try Task.checkCancellation()
          let request =
            cursor == nil
            ? firstRequest
            : ArchiveInventoryQuery(
              requestID: "inventory.\(UUID().uuidString.lowercased())", userID: connection.userID,
              sampleType: type.rawValue, start: Self.utc(interval.start),
              end: Self.utc(interval.end),
              limit: 200, cursor: cursor)
          let page =
            cursor == nil
            ? firstPage
            : try await connection.inventoryFetcher!.page(
              query: request, baseURL: connection.baseURL)
          try page.validate(query: request)
          if page.ownerGeneration != generation { throw ArchiveClientError.ownerChanged }
          if page.revision != revision { throw ArchiveClientError.inventoryChanged }
          for id in page.sampleIDs where !readableIDs.contains(id.lowercased()) {
            if missing.count < connection.capability.maxDeletionsPerBatch,
              let uuid = UUID(uuidString: id), !missing.contains(uuid)
            {
              missing.append(uuid)
            }
          }
          cursor = page.nextCursor
          state.types[type]?.inventoryComparison = ArchiveInventoryComparison(
            interval: interval, revision: revision, cursor: cursor)
          try await save(state)
          // A full missing batch can be conditionally committed without retaining
          // the remaining inventory. Coverage still requires a complete clean pass.
          if missing.count == connection.capability.maxDeletionsPerBatch { break }
        } while cursor != nil
        guard try await readableBoundary(type: type) == boundary else {
          throw ArchiveReconciliationError.authorizationUnproven
        }
        if missing.isEmpty {
          // A clean single-page snapshot has no conditional write to reject a
          // race. Recheck its revision after enumeration before accepting it.
          let verificationRequest = ArchiveInventoryQuery(
            requestID: "inventory.\(UUID().uuidString.lowercased())", userID: connection.userID,
            sampleType: type.rawValue, start: Self.utc(interval.start), end: Self.utc(interval.end),
            limit: 200, cursor: nil)
          let verification = try await connection.inventoryFetcher!.page(
            query: verificationRequest, baseURL: connection.baseURL)
          try verification.validate(query: verificationRequest)
          guard verification.ownerGeneration == generation else {
            throw ArchiveClientError.ownerChanged
          }
          guard verification.revision == revision else { throw ArchiveClientError.inventoryChanged }
          return
        }
        var next = state.types[type]!
        next.inventoryComparison = nil
        try await upload(
          samples: [], deletions: missing, type: type, interval: interval, next: next,
          state: &state, connection: connection, expectedInventoryRevision: revision,
          expectedOwnerGeneration: generation)
      } catch ArchiveClientError.inventoryChanged {
        // Rejected transactions made no mutation, and stale clean snapshots
        // prove no coverage. Neither may retain a journal or comparison cursor.
        state.pending = nil
        state.types[type]?.inventoryComparison = nil
        try await save(state)
        conflicts += 1
        guard conflicts < 8 else { throw ArchiveReconciliationError.inventoryUnstable }
      }
    }
  }

  /// Returns nil for a dense interval, retaining no more than 20,000 UUIDs.
  private func readableIDs(type: HealthObjectTypeID, interval: DateInterval) async throws -> Set<
    String
  >? {
    var result: Set<String> = []
    var cursor: ArchiveScanCursor?
    var complete = ArchiveIntervals()
    repeat {
      try Task.checkCancellation()
      let page = try await query.page(type: type, interval: interval, cursor: cursor, limit: 200)
      guard page.samples.count <= 200, page.coveredInterval.start >= interval.start,
        page.coveredInterval.end <= interval.end, page.coveredInterval.duration > 0,
        page.isWindowComplete || page.nextCursor != nil,
        page.nextCursor == nil || page.nextCursor != cursor
      else { throw ArchiveValidationError.invalidResponse }
      for sample in page.samples {
        guard ArchiveWire.validUUID(sample.uuid), let start = ArchiveWire.utcDate(sample.start)
        else {
          throw ArchiveValidationError.invalidSample
        }
        // Membership deliberately matches the server's start-based half-open range,
        // even though HealthKit's historical query returns overlapping samples.
        if start >= interval.start && start < interval.end {
          let id = sample.uuid.lowercased()
          if !result.contains(id) && result.count == 20_000 { return nil }
          result.insert(id)
        }
      }
      for deleted in page.deletedSampleIDs { result.remove(deleted.uuidString.lowercased()) }
      if page.isWindowComplete { complete.insert(page.coveredInterval) }
      cursor = page.nextCursor
    } while cursor != nil
    guard complete.gaps(in: interval).isEmpty else { throw ArchiveValidationError.invalidResponse }
    return result
  }

  private func save(_ state: ArchiveImportCheckpoint) async throws {
    do { try await checkpointStore.save(state) } catch is CancellationError {
      throw CancellationError()
    } catch let error as ArchiveQueryError { throw error } catch {
      throw ArchiveCheckpointStoreError.unavailable
    }
  }

  private func pollProjection(_ connection: ArchiveImportConnection) async throws {
    guard connection.capability.statisticsAvailable else { return }
    let id = "status.\(UUID().uuidString.lowercased())"
    let status = try await connection.statusFetcher.status(
      requestID: id, baseURL: connection.baseURL)
    try status.validate(requestID: id)
    report.projectionStates = Dictionary(
      uniqueKeysWithValues: status.metrics.compactMap {
        guard let metric = MetricID(rawValue: $0.metric),
          let state = ArchiveProjectionState(rawValue: $0.state)
        else { return nil }
        return (metric, state)
      })
  }

  private static func requestBytes(_ batch: ArchiveBatch, token: String) throws -> Int {
    var object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch)) as! [String: Any]
    object["token"] = token
    // A device credential is always 43 base64url bytes; its value cannot affect JSON size.
    object["uploader_credential"] = String(repeating: "A", count: 43)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).count
  }

  private static func utc(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func failure(
    _ error: any Error, type: HealthObjectTypeID? = nil,
    fallback: SyncFailureCategory
  ) -> ArchiveImportFailure {
    let category: SyncFailureCategory
    if error as? ArchiveImportIssue == .purchaseRequired {
      return .init(type: type, category: .purchaseRequired, issue: .purchaseRequired)
    } else if error is CancellationError {
      category = .cancelled
    } else if let error = error as? ArchiveReconciliationError {
      let issue: ArchiveImportIssue
      switch error {
      case .inventoryUnavailable: issue = .reconciliationRequired
      case .authorizationUnproven: issue = .authorizationUnproven
      case .intervalTooDense: issue = .inventoryTooDense
      case .inventoryUnstable: issue = .inventoryUnstable
      }
      return .init(type: type, category: .healthKit, issue: issue)
    } else if error is ArchiveCheckpointStoreError {
      category = .checkpoint
    } else if let error = error as? ArchiveQueryError {
      switch error {
      case .deviceLocked: category = .deviceLocked
      case .anchorInvalidated:
        return .init(type: type, category: .healthKit, issue: .reconciliationRequired)
      case .permissionRestricted:
        return .init(type: type, category: .healthKit, issue: .permissionRestricted)
      }
    } else if let error = error as? NetworkFailure {
      switch error {
      case .cancelled: category = .cancelled
      case .timeout: category = .timeout
      case .dnsFailure: category = .dnsFailure
      case .offline: category = .offline
      case .connectionLost: category = .connectionLost
      case .tlsFailure: category = .tlsFailure
      case .unauthorized: category = .unauthorized
      case .forbidden: category = .forbidden
      case .notFound: category = .notFound
      case .validation: category = .validation
      case .rateLimited: category = .rateLimited
      case .server: category = .server
      case .malformedResponse: category = .malformedResponse
      case .protocolMismatch: category = .protocolMismatch
      case .unexpectedStatus, .transport: category = .transport
      }
    } else if let error = error as? ArchiveClientError {
      switch error {
      case .ownerRequired: return .init(type: type, category: .configuration, issue: .ownerRequired)
      case .ownerPending: return .init(type: type, category: .configuration, issue: .ownerPending)
      case .ownerChanged: return .init(type: type, category: .configuration, issue: .ownerChanged)
      default: category = .validation
      }
    } else if let issue = error as? ArchiveImportIssue {
      return .init(type: type, category: .checkpoint, issue: issue)
    } else if error is ArchiveValidationError {
      category = .validation
    } else {
      category = fallback
    }
    return .init(type: type, category: category)
  }

  private static func isOwnershipFailure(_ error: any Error) -> Bool {
    guard let error = error as? ArchiveClientError else { return false }
    switch error {
    case .ownerRequired, .ownerPending, .ownerChanged: return true
    default: return false
    }
  }
}
