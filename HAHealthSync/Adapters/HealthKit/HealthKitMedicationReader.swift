import Foundation
import HealthKit
import HealthSyncCore

enum HealthKitMedicationError: Error, Sendable, Equatable {
  case unavailable
  case missingAnchor
  case invalidCalendarWindow
}

struct MedicationAnchorDelta: Sendable, Equatable {
  let candidateAnchor: Data
  let hasChanges: Bool
}

protocol HealthKitMedicationClient: Sendable {
  func requestAuthorization() async throws
  func concepts() async throws -> [MedicationConcept]
  func doseChanges(anchor: Data?) async throws -> MedicationAnchorDelta
  func doses(interval: DateInterval) async throws -> [MedicationDose]
}

protocol MedicationAccessProviding: Sendable {
  func requestAuthorizationAndList() async throws -> [MedicationConcept]
}

struct HealthKitMedicationReader: MedicationReading, MedicationAccessProviding, Sendable {
  private let client: any HealthKitMedicationClient

  init(client: any HealthKitMedicationClient) {
    self.client = client
  }

  func requestAuthorization() async throws {
    try Task.checkCancellation()
    guard #available(iOS 26.0, *) else { throw HealthKitMedicationError.unavailable }
    try await client.requestAuthorization()
  }

  func requestAuthorizationAndList() async throws -> [MedicationConcept] {
    try await requestAuthorization()
    return try await client.concepts()
  }

  func read(
    committedCheckpoint: MedicationCheckpoint?,
    now: Date,
    calendar: Calendar
  ) async throws -> MedicationReadResult {
    try Task.checkCancellation()
    guard #available(iOS 26.0, *) else { throw HealthKitMedicationError.unavailable }
    let concepts = try await client.concepts()
    let activeConcepts = concepts.filter { !$0.isArchived }.sorted { $0.id < $1.id }
    let activeIDs = activeConcepts.map(\.id)
    let activeIDSet = Set(activeIDs)
    let fingerprint = MedicationIdentifier.fingerprint(
      concepts.map { "\($0.id)|\($0.isArchived)|\($0.name ?? "")" }
    )
    let delta = try await client.doseChanges(anchor: committedCheckpoint?.anchor)
    let removed = Set(committedCheckpoint?.medicationIDs ?? []).subtracting(activeIDSet)
    let hasChanges =
      committedCheckpoint == nil
      || committedCheckpoint?.sourceFingerprint != fingerprint
      || delta.hasChanges
      || !removed.isEmpty
    let candidate = MedicationCheckpoint(
      anchor: delta.candidateAnchor,
      medicationIDs: activeIDs,
      sourceFingerprint: fingerprint
    )
    guard hasChanges else {
      return MedicationReadResult(
        concepts: [],
        doses: [],
        candidateCheckpoint: candidate,
        hasChanges: false
      )
    }
    guard let interval = calendar.dateInterval(of: .day, for: now) else {
      throw HealthKitMedicationError.invalidCalendarWindow
    }
    let doses = try await client.doses(interval: interval).filter {
      activeIDSet.contains($0.medicationID)
    }
    return MedicationReadResult(
      concepts: activeConcepts,
      doses: doses,
      candidateCheckpoint: candidate,
      hasChanges: true,
      removedMedicationIDs: removed
    )
  }
}

final class HKHealthStoreMedicationClient: HealthKitMedicationClient, @unchecked Sendable {
  private let healthStore: HKHealthStore

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func requestAuthorization() async throws {
    guard #available(iOS 26.0, *) else { throw HealthKitMedicationError.unavailable }
    try await healthStore.requestPerObjectReadAuthorization(
      for: HKObjectType.userAnnotatedMedicationType(),
      predicate: nil
    )
  }

  func concepts() async throws -> [MedicationConcept] {
    guard #available(iOS 26.0, *) else { throw HealthKitMedicationError.unavailable }
    let medications = try await HKUserAnnotatedMedicationQueryDescriptor().result(for: healthStore)
    return try medications.map { medication in
      MedicationConcept(
        id: try Self.identifier(for: medication.medication.identifier),
        name: medication.nickname ?? medication.medication.displayText,
        isArchived: medication.isArchived
      )
    }
  }

  func doseChanges(anchor: Data?) async throws -> MedicationAnchorDelta {
    guard #available(iOS 26.0, *) else { throw HealthKitMedicationError.unavailable }
    let decodedAnchor = try anchor.map(HealthKitAnchorCodec.decode)
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKAnchoredObjectQuery(
        type: HKObjectType.medicationDoseEventType(),
        predicate: nil,
        anchor: decodedAnchor,
        limit: HKObjectQueryNoLimit
      ) { _, samples, deleted, newAnchor, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let newAnchor else {
          continuation.resume(throwing: HealthKitMedicationError.missingAnchor)
          return
        }
        do {
          continuation.resume(
            returning: MedicationAnchorDelta(
              candidateAnchor: try HealthKitAnchorCodec.encode(newAnchor),
              hasChanges: !(samples ?? []).isEmpty || !(deleted ?? []).isEmpty
            )
          )
        } catch {
          continuation.resume(throwing: error)
        }
      }
      healthStore.execute(query)
    }
  }

  func doses(interval: DateInterval) async throws -> [MedicationDose] {
    guard #available(iOS 26.0, *) else { throw HealthKitMedicationError.unavailable }
    let predicate = HKQuery.predicateForSamples(
      withStart: interval.start,
      end: interval.end,
      options: [.strictStartDate]
    )
    let descriptor = HKSampleQueryDescriptor<HKSample>(
      predicates: [
        .sample(type: HKObjectType.medicationDoseEventType(), predicate: predicate)
      ],
      sortDescriptors: [SortDescriptor(\HKSample.startDate)]
    )
    return try await descriptor.result(for: healthStore).compactMap { sample in
      guard let event = sample as? HKMedicationDoseEvent else { return nil }
      return MedicationDose(
        id: event.uuid,
        medicationID: try Self.identifier(for: event.medicationConceptIdentifier),
        status: Self.status(event.logStatus),
        schedule: event.scheduleType == .schedule ? .scheduled : .asNeeded,
        doseQuantity: event.doseQuantity,
        unit: event.unit.unitString
      )
    }
  }

  @available(iOS 26.0, *)
  private static func identifier(for value: HKHealthConceptIdentifier) throws -> String {
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: value,
      requiringSecureCoding: true
    )
    return MedicationIdentifier.make(from: data)
  }

  @available(iOS 26.0, *)
  private static func status(_ value: HKMedicationDoseEvent.LogStatus) -> MedicationDoseStatus {
    switch value {
    case .taken: .taken
    case .skipped: .skipped
    case .notInteracted, .notificationNotSent, .snoozed, .notLogged: .pending
    @unknown default: .pending
    }
  }
}
