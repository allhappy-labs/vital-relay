import Foundation

public struct MedicationReadResult: Sendable, Equatable {
  public let concepts: [MedicationConcept]
  public let doses: [MedicationDose]
  public let candidateCheckpoint: MedicationCheckpoint
  public let hasChanges: Bool
  public let removedMedicationIDs: Set<String>

  public init(
    concepts: [MedicationConcept],
    doses: [MedicationDose],
    candidateCheckpoint: MedicationCheckpoint,
    hasChanges: Bool,
    removedMedicationIDs: Set<String> = []
  ) {
    self.concepts = concepts
    self.doses = doses
    self.candidateCheckpoint = candidateCheckpoint
    self.hasChanges = hasChanges
    self.removedMedicationIDs = removedMedicationIDs
  }
}

public protocol MedicationReading: Sendable {
  func requestAuthorization() async throws
  func read(
    committedCheckpoint: MedicationCheckpoint?,
    now: Date,
    calendar: Calendar
  ) async throws -> MedicationReadResult
}

public protocol MedicationHealthBridgeSending: Sendable {
  func send(
    medications: MedicationPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String
  ) async throws -> LiveAcknowledgement
  func send(
    medications: MedicationPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement
}

extension MedicationHealthBridgeSending {
  public func send(
    medications: MedicationPayload,
    baseURL: NormalizedBaseURL,
    webhookSecret: String,
    userID: String,
    requestID: String,
    timeout: TimeInterval
  ) async throws -> LiveAcknowledgement {
    try await send(
      medications: medications,
      baseURL: baseURL,
      webhookSecret: webhookSecret,
      userID: userID,
      requestID: requestID
    )
  }
}

public struct MedicationSyncReport: Codable, Sendable, Equatable {
  public let attempted: Bool
  public let synchronized: Bool
  public let skipped: Bool
  public let failure: SyncFailureCategory?

  public init(
    attempted: Bool,
    synchronized: Bool,
    skipped: Bool,
    failure: SyncFailureCategory?
  ) {
    self.attempted = attempted
    self.synchronized = synchronized
    self.skipped = skipped
    self.failure = failure
  }
}

public protocol MedicationSynchronizing: Sendable {
  func sync(trigger: SyncTrigger) async -> MedicationSyncReport
  func sync(trigger: SyncTrigger, deadline: ExecutionDeadline?) async -> MedicationSyncReport
}

extension MedicationSynchronizing {
  public func sync(
    trigger: SyncTrigger,
    deadline: ExecutionDeadline?
  ) async -> MedicationSyncReport {
    await sync(trigger: trigger)
  }
}

public actor MedicationSyncCoordinator: MedicationSynchronizing {
  private let configurationStore: any ConfigurationStore
  private let credentialStore: any CredentialStore
  private let reader: any MedicationReading
  private let sender: any MedicationHealthBridgeSending
  private let checkpointStore: any MedicationCheckpointStore
  private let requestIDGenerator: RequestIDGenerator
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private let retryPolicy: RetryPolicy
  private let sleeper: any SyncSleeper
  private let jitterSource: any JitterSource

  public init(
    configurationStore: any ConfigurationStore,
    credentialStore: any CredentialStore,
    reader: any MedicationReading,
    sender: any MedicationHealthBridgeSending,
    checkpointStore: any MedicationCheckpointStore,
    requestIDGenerator: RequestIDGenerator = RequestIDGenerator(),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() },
    retryPolicy: RetryPolicy = .default,
    sleeper: any SyncSleeper = ContinuousSyncSleeper(),
    jitterSource: any JitterSource = SystemJitterSource()
  ) {
    self.configurationStore = configurationStore
    self.credentialStore = credentialStore
    self.reader = reader
    self.sender = sender
    self.checkpointStore = checkpointStore
    self.requestIDGenerator = requestIDGenerator
    self.calendar = calendar
    self.now = now
    self.retryPolicy = retryPolicy
    self.sleeper = sleeper
    self.jitterSource = jitterSource
  }

  public func sync(trigger: SyncTrigger) async -> MedicationSyncReport {
    await sync(trigger: trigger, deadline: nil)
  }

  public func sync(trigger: SyncTrigger, deadline: ExecutionDeadline?) async -> MedicationSyncReport
  {
    do {
      try Task.checkCancellation()
      let configuration = try await configurationStore.load()
      guard configuration.medicationSyncEnabled else { return Self.disabled }
      if let deadline, deadline.remaining(now: now()) <= 0 {
        throw MedicationSyncInternalError.deadline
      }
      let baseURL = try NormalizedBaseURL.parse(
        configuration.baseURL,
        allowConfirmedLocalHTTP: configuration.allowsConfirmedLocalHTTP
      )
      guard let secret = try await credentialStore.read(.webhookSecret), !secret.isEmpty else {
        throw CredentialStoreError.blankValue
      }
      let committed = try await checkpointStore.load()
      let result = try await reader.read(
        committedCheckpoint: committed,
        now: now(),
        calendar: calendar
      )
      guard result.hasChanges else {
        return MedicationSyncReport(
          attempted: true,
          synchronized: false,
          skipped: true,
          failure: nil
        )
      }
      guard result.removedMedicationIDs.isEmpty else {
        return Self.failure(.compatibility)
      }
      guard !result.concepts.isEmpty else {
        return MedicationSyncReport(
          attempted: true,
          synchronized: false,
          skipped: true,
          failure: nil
        )
      }
      let payload = try MedicationPayload.aggregate(concepts: result.concepts, doses: result.doses)
      let requestID = requestIDGenerator.live()
      try await sendWithRetry(
        payload: payload,
        baseURL: baseURL,
        secret: secret,
        userID: configuration.healthBridgeUserID,
        requestID: requestID,
        deadline: deadline
      )
      do {
        try await checkpointStore.save(result.candidateCheckpoint)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw MedicationSyncInternalError.checkpoint
      }
      return MedicationSyncReport(
        attempted: true,
        synchronized: true,
        skipped: false,
        failure: nil
      )
    } catch is CancellationError {
      return Self.failure(.cancelled)
    } catch is CredentialStoreError {
      return Self.failure(.credential)
    } catch is MedicationPayloadError {
      return Self.failure(.validation)
    } catch MedicationSyncInternalError.deadline {
      return Self.failure(.deadlineExceeded)
    } catch MedicationSyncInternalError.checkpoint {
      return Self.failure(.checkpoint)
    } catch let failure as NetworkFailure {
      return Self.failure(Self.category(for: failure))
    } catch {
      return Self.failure(.healthKit)
    }
  }

  private func sendWithRetry(
    payload: MedicationPayload,
    baseURL: NormalizedBaseURL,
    secret: String,
    userID: String,
    requestID: String,
    deadline: ExecutionDeadline?
  ) async throws {
    var attempts = 0
    while true {
      try Task.checkCancellation()
      let timeout: TimeInterval
      do {
        timeout = try ExecutionDeadline.requestTimeout(for: deadline, now: now())
      } catch {
        throw MedicationSyncInternalError.deadline
      }
      attempts += 1
      do {
        _ = try await sender.send(
          medications: payload,
          baseURL: baseURL,
          webhookSecret: secret,
          userID: userID,
          requestID: requestID,
          timeout: timeout
        )
        return
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        let failure = error as? NetworkFailure ?? NetworkFailure.classify(error)
        guard
          let delay = retryPolicy.delay(
            after: failure,
            completedAttempts: attempts,
            jitterUnit: await jitterSource.nextUnit()
          )
        else { throw failure }
        if let deadline, (try? deadline.validate(wait: delay, now: now())) == nil {
          throw MedicationSyncInternalError.deadline
        }
        try await sleeper.sleep(for: delay)
      }
    }
  }

  private static let disabled = MedicationSyncReport(
    attempted: false,
    synchronized: false,
    skipped: false,
    failure: nil
  )

  private static func failure(_ category: SyncFailureCategory) -> MedicationSyncReport {
    MedicationSyncReport(attempted: true, synchronized: false, skipped: false, failure: category)
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

private enum MedicationSyncInternalError: Error {
  case checkpoint
  case deadline
}
