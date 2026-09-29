import Foundation

public actor InboundSyncCoordinator: InboundSyncCoordinating {
  private struct Dependencies: Sendable {
    let pairingStore: any PairingStore
    let configurationStore: any ConfigurationStore
    let credentialStore: any CredentialStore
    let stateFetcher: any HomeAssistantStateFetching
    let writer: any HealthSampleWriting
    let checkpointStore: any PairingCheckpointStore
    let now: @Sendable () -> Date
  }

  private struct ActiveTransaction {
    let token: UUID
    let task: Task<TransactionOutcome, Never>
  }

  private enum TransactionOutcome: Sendable {
    case saved
    case skipped
    case failed(SyncFailureCategory)
  }

  private let dependencies: Dependencies
  private var activeTransactions: [UUID: ActiveTransaction] = [:]

  public init(
    pairingStore: any PairingStore,
    configurationStore: any ConfigurationStore,
    credentialStore: any CredentialStore,
    stateFetcher: any HomeAssistantStateFetching,
    writer: any HealthSampleWriting,
    checkpointStore: any PairingCheckpointStore,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    dependencies = Dependencies(
      pairingStore: pairingStore,
      configurationStore: configurationStore,
      credentialStore: credentialStore,
      stateFetcher: stateFetcher,
      writer: writer,
      checkpointStore: checkpointStore,
      now: now
    )
  }

  public func sync(trigger: SyncTrigger) async -> InboundSyncReport {
    await sync(trigger: trigger, deadline: nil)
  }

  public func sync(trigger: SyncTrigger, deadline: ExecutionDeadline?) async -> InboundSyncReport {
    let startedAt = dependencies.now()
    let pairings: [Pairing]
    do {
      pairings = try await dependencies.pairingStore.all().filter(\.isEnabled)
    } catch is CancellationError {
      return setupFailureReport(trigger: trigger, category: .cancelled, startedAt: startedAt)
    } catch {
      return setupFailureReport(trigger: trigger, category: .configuration, startedAt: startedAt)
    }

    let configuration: AppConfiguration
    let baseURL: NormalizedBaseURL
    do {
      configuration = try await dependencies.configurationStore.load()
      try configuration.validate()
      baseURL = try NormalizedBaseURL.parse(
        configuration.baseURL,
        allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP
      )
    } catch is CancellationError {
      return setupFailureReport(
        trigger: trigger,
        pairings: pairings,
        category: .cancelled,
        startedAt: startedAt
      )
    } catch {
      return setupFailureReport(
        trigger: trigger,
        pairings: pairings,
        category: .configuration,
        startedAt: startedAt
      )
    }

    let accessToken: String
    do {
      guard let storedToken = try await dependencies.credentialStore.read(.accessToken),
        !storedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw CredentialStoreError.blankValue
      }
      accessToken = storedToken
    } catch is CancellationError {
      return setupFailureReport(
        trigger: trigger,
        pairings: pairings,
        category: .cancelled,
        startedAt: startedAt
      )
    } catch {
      return setupFailureReport(
        trigger: trigger,
        pairings: pairings,
        category: .credential,
        startedAt: startedAt
      )
    }

    let indexedOutcomes = await withTaskGroup(
      of: (Int, UUID, TransactionOutcome).self,
      returning: [(Int, UUID, TransactionOutcome)].self
    ) { group in
      for (index, pairing) in pairings.enumerated() {
        group.addTask {
          let outcome = await self.transactionOutcome(
            pairing: pairing,
            baseURL: baseURL,
            accessToken: accessToken,
            deadline: deadline
          )
          return (index, pairing.id, outcome)
        }
      }

      var outcomes: [(Int, UUID, TransactionOutcome)] = []
      for await outcome in group {
        outcomes.append(outcome)
      }
      return outcomes.sorted { $0.0 < $1.0 }
    }

    var savedPairings = 0
    var skippedPairings = 0
    var failures: [InboundSyncFailure] = []
    for (_, pairingID, outcome) in indexedOutcomes {
      switch outcome {
      case .saved:
        savedPairings += 1
      case .skipped:
        skippedPairings += 1
      case .failed(let category):
        failures.append(.init(pairingID: pairingID, category: category))
      }
    }

    return InboundSyncReport(
      trigger: trigger,
      attemptedPairings: pairings.count,
      savedPairings: savedPairings,
      skippedPairings: skippedPairings,
      failures: failures,
      startedAt: startedAt,
      finishedAt: dependencies.now()
    )
  }

  private func transactionOutcome(
    pairing: Pairing,
    baseURL: NormalizedBaseURL,
    accessToken: String,
    deadline: ExecutionDeadline?
  ) async -> TransactionOutcome {
    if let active = activeTransactions[pairing.id] {
      return await waitForTransaction(active.task)
    }

    let token = UUID()
    let dependencies = dependencies
    let task = Task {
      await Self.performTransaction(
        pairing: pairing,
        baseURL: baseURL,
        accessToken: accessToken,
        deadline: deadline,
        dependencies: dependencies
      )
    }
    activeTransactions[pairing.id] = ActiveTransaction(token: token, task: task)
    let outcome = await waitForTransaction(task)
    if activeTransactions[pairing.id]?.token == token {
      activeTransactions[pairing.id] = nil
    }
    return outcome
  }

  private func waitForTransaction(
    _ task: Task<TransactionOutcome, Never>
  ) async -> TransactionOutcome {
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private static func performTransaction(
    pairing: Pairing,
    baseURL: NormalizedBaseURL,
    accessToken: String,
    deadline: ExecutionDeadline?,
    dependencies: Dependencies
  ) async -> TransactionOutcome {
    let timeout: TimeInterval
    do {
      timeout = try ExecutionDeadline.requestTimeout(for: deadline, now: dependencies.now())
    } catch {
      return .failed(.deadlineExceeded)
    }
    let state: HomeAssistantState
    do {
      try Task.checkCancellation()
      state = try await dependencies.stateFetcher.fetchState(
        entityID: pairing.entityID,
        baseURL: baseURL,
        accessToken: accessToken,
        timeout: timeout
      )
    } catch {
      return .failed(failureCategory(for: error, fallback: .transport))
    }

    if isUnavailable(state.state) {
      return .skipped
    }

    let normalized: NormalizedHomeAssistantState
    do {
      normalized = try HomeAssistantStateParser.normalize(state, for: pairing)
    } catch is CancellationError {
      return .failed(.cancelled)
    } catch {
      return .failed(.validation)
    }

    let identity = SyncIdentity.make(
      pairingID: pairing.id,
      entityID: normalized.entityID,
      homeAssistantUpdatedAt: normalized.lastUpdated,
      normalizedValue: normalized.normalizedValue,
      destination: normalized.destination
    )

    do {
      if let checkpoint = try await dependencies.checkpointStore.checkpoint(for: pairing.id),
        checkpoint.matches(normalized),
        checkpoint.syncIdentifier == identity.identifier,
        checkpoint.syncVersion == identity.version
      {
        return .skipped
      }
    } catch is CancellationError {
      return .failed(.cancelled)
    } catch {
      return .failed(.checkpoint)
    }

    if let deadline, deadline.remaining(now: dependencies.now()) <= 0 {
      return .failed(.deadlineExceeded)
    }

    let write = HealthSampleWrite(
      destination: normalized.destination,
      value: normalized.normalizedValue,
      date: normalized.lastUpdated,
      syncIdentifier: identity.identifier,
      syncVersion: identity.version
    )
    do {
      try await dependencies.writer.save(write)
      try Task.checkCancellation()
    } catch is CancellationError {
      return .failed(.cancelled)
    } catch {
      return .failed(.healthKit)
    }

    let checkpoint = PairingCheckpoint(
      pairingID: pairing.id,
      entityID: normalized.entityID,
      homeAssistantUpdatedAt: normalized.lastUpdated,
      normalizedValue: normalized.normalizedValue,
      destination: normalized.destination,
      syncIdentifier: identity.identifier,
      syncVersion: identity.version
    )
    do {
      try await dependencies.checkpointStore.commit(checkpoint)
    } catch is CancellationError {
      return .failed(.cancelled)
    } catch {
      return .failed(.checkpoint)
    }
    return .saved
  }

  private static func isUnavailable(_ state: String) -> Bool {
    switch state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "unknown", "unavailable", "none": true
    default: false
    }
  }

  private func setupFailureReport(
    trigger: SyncTrigger,
    pairings: [Pairing] = [],
    category: SyncFailureCategory,
    startedAt: Date
  ) -> InboundSyncReport {
    let failures =
      pairings.isEmpty
      ? [InboundSyncFailure(pairingID: nil, category: category)]
      : pairings.map { InboundSyncFailure(pairingID: $0.id, category: category) }
    return InboundSyncReport(
      trigger: trigger,
      attemptedPairings: pairings.count,
      savedPairings: 0,
      skippedPairings: 0,
      failures: failures,
      startedAt: startedAt,
      finishedAt: dependencies.now()
    )
  }

  private static func failureCategory(
    for error: any Error,
    fallback: SyncFailureCategory
  ) -> SyncFailureCategory {
    if error is CancellationError { return .cancelled }
    guard let failure = error as? NetworkFailure else { return fallback }
    switch failure {
    case .cancelled: return .cancelled
    case .timeout: return .timeout
    case .dnsFailure: return .dnsFailure
    case .offline: return .offline
    case .connectionLost: return .connectionLost
    case .tlsFailure: return .tlsFailure
    case .unauthorized: return .unauthorized
    case .forbidden: return .forbidden
    case .notFound: return .notFound
    case .validation: return .validation
    case .rateLimited: return .rateLimited
    case .server: return .server
    case .malformedResponse: return .malformedResponse
    case .protocolMismatch: return .protocolMismatch
    case .unexpectedStatus, .transport: return .transport
    }
  }
}
