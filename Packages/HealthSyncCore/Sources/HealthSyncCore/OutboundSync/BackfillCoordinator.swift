import Foundation

public protocol BackfillPointQuerying: Sendable {
  func points(
    for definition: MetricDefinition,
    interval: DateInterval,
    calendar: Calendar
  ) async throws -> [BackfillPoint]
}

public protocol BackfillCoordinating: Sendable {
  func importHistory(
    metrics: Set<MetricID>,
    requestedStart: Date
  ) async -> BackfillReport
}

public struct BackfillFailure: Codable, Sendable, Equatable {
  public let metricID: MetricID?
  public let category: SyncFailureCategory

  public init(metricID: MetricID?, category: SyncFailureCategory) {
    self.metricID = metricID
    self.category = category
  }
}

public struct BackfillReport: Codable, Sendable, Equatable {
  public var requiresPurchase: Bool { failures.contains { $0.category == .purchaseRequired } }
  public let attemptedMetrics: Int
  public let committedMetrics: Int
  public let skippedMetrics: Int
  public let committedPoints: Int
  public let capability: BackfillCapability
  public let failures: [BackfillFailure]

  public init(
    attemptedMetrics: Int,
    committedMetrics: Int,
    skippedMetrics: Int = 0,
    committedPoints: Int,
    capability: BackfillCapability,
    failures: [BackfillFailure]
  ) {
    self.attemptedMetrics = attemptedMetrics
    self.committedMetrics = committedMetrics
    self.skippedMetrics = skippedMetrics
    self.committedPoints = committedPoints
    self.capability = capability
    self.failures = failures
  }
}

public actor BackfillCoordinator: BackfillCoordinating {
  private struct Dependencies: Sendable {
    let access: any PaidFeatureAccessing
    let configurationStore: any ConfigurationStore
    let credentialStore: any CredentialStore
    let liveCoordinator: any SyncCoordinating
    let pointQuery: any BackfillPointQuerying
    let sender: any HealthBridgeBackfillSending
    let checkpointStore: any BackfillCheckpointStore
    let requestIDGenerator: RequestIDGenerator
    let calendar: Calendar
    let now: @Sendable () -> Date
    let retryPolicy: RetryPolicy
    let sleeper: any SyncSleeper
    let jitterSource: any JitterSource
  }

  private enum SendOutcome: Sendable {
    case committed(BackfillAcknowledgement)
    case incompatible
    case failure(SyncFailureCategory)
  }

  private let dependencies: Dependencies
  private var activeTask: Task<BackfillReport, Never>?

  public init(
    access: any PaidFeatureAccessing,
    configurationStore: any ConfigurationStore,
    credentialStore: any CredentialStore,
    liveCoordinator: any SyncCoordinating,
    pointQuery: any BackfillPointQuerying,
    sender: any HealthBridgeBackfillSending,
    checkpointStore: any BackfillCheckpointStore,
    requestIDGenerator: RequestIDGenerator = RequestIDGenerator(),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() },
    retryPolicy: RetryPolicy = .default,
    sleeper: any SyncSleeper = ContinuousSyncSleeper(),
    jitterSource: any JitterSource = SystemJitterSource()
  ) {
    dependencies = Dependencies(
      access: access,
      configurationStore: configurationStore,
      credentialStore: credentialStore,
      liveCoordinator: liveCoordinator,
      pointQuery: pointQuery,
      sender: sender,
      checkpointStore: checkpointStore,
      requestIDGenerator: requestIDGenerator,
      calendar: calendar,
      now: now,
      retryPolicy: retryPolicy,
      sleeper: sleeper,
      jitterSource: jitterSource
    )
  }

  public func importHistory(
    metrics: Set<MetricID>,
    requestedStart: Date
  ) async -> BackfillReport {
    if let activeTask { return await activeTask.value }
    let dependencies = dependencies
    let task = Task {
      await Self.perform(
        metrics: metrics, requestedStart: requestedStart, dependencies: dependencies)
    }
    activeTask = task
    let report = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    activeTask = nil
    return report
  }

  private static func perform(
    metrics: Set<MetricID>,
    requestedStart: Date,
    dependencies: Dependencies
  ) async -> BackfillReport {
    guard await dependencies.access.accessState() == .unlocked else {
      return report(
        metrics: metrics, capability: .temporarilyUnavailable, category: .purchaseRequired)
    }
    let configuration: AppConfiguration
    let baseURL: NormalizedBaseURL
    let secret: String
    var state: BackfillState
    do {
      configuration = try await dependencies.configurationStore.load()
      guard configuration.experimentalBackfillEnabled else {
        return report(metrics: metrics, capability: .disabledByUser)
      }
      baseURL = try NormalizedBaseURL.parse(
        configuration.baseURL,
        allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP
      )
      guard let storedSecret = try await dependencies.credentialStore.read(.webhookSecret),
        !storedSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { throw CredentialStoreError.blankValue }
      secret = storedSecret
      state = try await dependencies.checkpointStore.load()
    } catch is CancellationError {
      return report(metrics: metrics, capability: .temporarilyUnavailable, category: .cancelled)
    } catch let error as CredentialStoreError {
      _ = error
      return report(metrics: metrics, capability: .temporarilyUnavailable, category: .credential)
    } catch {
      return report(metrics: metrics, capability: .temporarilyUnavailable, category: .configuration)
    }

    if case .incompatible = state.capability {
      return report(metrics: metrics, capability: state.capability, category: .compatibility)
    }

    let now = dependencies.now()
    let earliestAllowed = now.addingTimeInterval(-BackfillRequest.maximumAge)
    let start = max(requestedStart, earliestAllowed)
    guard start < now else {
      return report(metrics: metrics, capability: state.capability, category: .validation)
    }

    var committedMetrics = 0
    var skippedMetrics = 0
    var committedPoints = 0
    var failures: [BackfillFailure] = []
    for metricID in metrics.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard await dependencies.access.accessState() == .unlocked else {
        failures.append(.init(metricID: metricID, category: .purchaseRequired))
        break
      }
      guard !Task.isCancelled else {
        failures.append(.init(metricID: metricID, category: .cancelled))
        break
      }
      guard let definition = MetricRegistry[metricID],
        MetricRegistry.backfillEligible.contains(where: { $0.id == metricID })
      else {
        failures.append(.init(metricID: metricID, category: .compatibility))
        continue
      }

      let priorCheckpoint = state.checkpoints[metricID]
      if priorCheckpoint == nil {
        let live = await dependencies.liveCoordinator.sync(trigger: .manual, metrics: [metricID])
        guard live.failures.isEmpty, live.attemptedMetrics == 1,
          live.synchronizedMetrics + live.skippedMetrics == 1
        else {
          failures.append(
            .init(metricID: metricID, category: live.failures.first?.category ?? .compatibility)
          )
          continue
        }
      }

      let points: [BackfillPoint]
      do {
        let queryStart = max(start, priorCheckpoint?.committedThrough ?? start)
        points = try await dependencies.pointQuery.points(
          for: definition,
          interval: DateInterval(start: queryStart, end: now),
          calendar: dependencies.calendar
        ).sorted { $0.timestamp < $1.timestamp }
      } catch is CancellationError {
        failures.append(.init(metricID: metricID, category: .cancelled))
        break
      } catch {
        failures.append(.init(metricID: metricID, category: .healthKit))
        continue
      }
      guard let livePoint = points.last else {
        skippedMetrics += 1
        continue
      }

      let historicalPoints = points.dropLast().filter {
        guard let priorCheckpoint else { return true }
        return $0.timestamp > priorCheckpoint.committedThrough
      }
      guard !historicalPoints.isEmpty else {
        skippedMetrics += 1
        continue
      }

      var metricCommitted = true
      var sentChunk = false
      for historicalChunk in historicalPoints.chunked(maximumCount: 720) {
        sentChunk = true
        let requestID = dependencies.requestIDGenerator.backfill()
        let request: BackfillRequest
        do {
          request = try BackfillRequest(
            token: secret,
            userID: configuration.healthBridgeUserID,
            requestID: requestID,
            series: [
              BackfillSeries(metricID: metricID, points: historicalChunk + [livePoint])
            ],
            now: now
          )
        } catch {
          failures.append(.init(metricID: metricID, category: .validation))
          metricCommitted = false
          break
        }

        let outcome = await sendWithRetry(request, baseURL: baseURL, dependencies: dependencies)
        switch outcome {
        case .committed(let acknowledgement):
          guard let committedThrough = historicalChunk.last?.timestamp else {
            failures.append(.init(metricID: metricID, category: .validation))
            metricCommitted = false
            break
          }
          let checkpoint = BackfillCheckpoint(
            metricID: metricID,
            windowStart: priorCheckpoint?.windowStart ?? start,
            committedThrough: committedThrough,
            requestID: requestID
          )
          var candidateState = state
          candidateState.capability = .available(protocolVersion: 1)
          candidateState.checkpoints[metricID] = checkpoint
          do {
            try await dependencies.checkpointStore.save(candidateState)
            state = candidateState
            committedPoints += acknowledgement.received
          } catch is CancellationError {
            failures.append(.init(metricID: metricID, category: .cancelled))
            metricCommitted = false
          } catch {
            failures.append(.init(metricID: metricID, category: .checkpoint))
            metricCommitted = false
          }
        case .incompatible:
          state.capability = .incompatible(reason: .unsupportedRecorder)
          try? await dependencies.checkpointStore.save(state)
          failures.append(.init(metricID: metricID, category: .compatibility))
          metricCommitted = false
        case .failure(.purchaseRequired):
          // Entitlement loss says nothing about server compatibility or availability.
          // Keep the complete state from the last acknowledged batch unchanged.
          failures.append(.init(metricID: metricID, category: .purchaseRequired))
          metricCommitted = false
        case .failure(let category):
          state.capability = .temporarilyUnavailable
          try? await dependencies.checkpointStore.save(state)
          failures.append(.init(metricID: metricID, category: category))
          metricCommitted = false
        }
        if !metricCommitted { break }
      }
      if metricCommitted, sentChunk { committedMetrics += 1 }
    }

    return BackfillReport(
      attemptedMetrics: metrics.count,
      committedMetrics: committedMetrics,
      skippedMetrics: skippedMetrics,
      committedPoints: committedPoints,
      capability: state.capability,
      failures: failures
    )
  }

  private static func sendWithRetry(
    _ request: BackfillRequest,
    baseURL: NormalizedBaseURL,
    dependencies: Dependencies
  ) async -> SendOutcome {
    var attempts = 0
    while true {
      do {
        try Task.checkCancellation()
        guard await dependencies.access.accessState() == .unlocked else {
          return .failure(.purchaseRequired)
        }
        attempts += 1
        return .committed(try await dependencies.sender.send(request, baseURL: baseURL))
      } catch is CancellationError {
        return .failure(.cancelled)
      } catch let error as BackfillClientError {
        if error == .unsupportedRecorder { return .incompatible }
        if error == .invalidBackfill { return .failure(.validation) }
        let failure = NetworkFailure.server(statusCode: error == .commitFailed ? 500 : 503)
        guard
          let delay = dependencies.retryPolicy.delay(
            after: failure,
            completedAttempts: attempts,
            jitterUnit: await dependencies.jitterSource.nextUnit()
          )
        else { return .failure(.server) }
        do { try await dependencies.sleeper.sleep(for: delay) } catch {
          return .failure(.cancelled)
        }
      } catch let failure as NetworkFailure {
        guard
          let delay = dependencies.retryPolicy.delay(
            after: failure,
            completedAttempts: attempts,
            jitterUnit: await dependencies.jitterSource.nextUnit()
          )
        else { return .failure(category(for: failure)) }
        do { try await dependencies.sleeper.sleep(for: delay) } catch {
          return .failure(.cancelled)
        }
      } catch {
        return .failure(.unknown)
      }
    }
  }

  private static func report(
    metrics: Set<MetricID>,
    capability: BackfillCapability,
    category: SyncFailureCategory? = nil
  ) -> BackfillReport {
    BackfillReport(
      attemptedMetrics: metrics.count,
      committedMetrics: 0,
      skippedMetrics: 0,
      committedPoints: 0,
      capability: capability,
      failures: category.map { [BackfillFailure(metricID: nil, category: $0)] } ?? []
    )
  }

  private static func category(for failure: NetworkFailure) -> SyncFailureCategory {
    switch failure {
    case .cancelled: .cancelled
    case .timeout: .timeout
    case .dnsFailure: .dnsFailure
    case .offline: .offline
    case .connectionLost: .connectionLost
    case .tlsFailure: .tlsFailure
    case .unauthorized: .unauthorized
    case .forbidden: .forbidden
    case .notFound: .notFound
    case .validation: .validation
    case .rateLimited: .rateLimited
    case .server: .server
    case .malformedResponse: .malformedResponse
    case .protocolMismatch: .protocolMismatch
    case .unexpectedStatus, .transport: .transport
    }
  }
}

extension Collection {
  fileprivate func chunked(maximumCount: Int) -> [[Element]] {
    guard maximumCount > 0 else { return [] }
    var chunks: [[Element]] = []
    var index = startIndex
    while index != endIndex {
      let next = self.index(index, offsetBy: maximumCount, limitedBy: endIndex) ?? endIndex
      chunks.append(Array(self[index..<next]))
      index = next
    }
    return chunks
  }
}
