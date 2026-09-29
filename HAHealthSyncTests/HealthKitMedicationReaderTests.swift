import Foundation
import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitMedicationReaderTests: XCTestCase {
  private let firstID = MedicationIdentifier.make(from: Data("first".utf8))
  private let removedID = MedicationIdentifier.make(from: Data("removed".utf8))

  func testReadsAuthorizedCurrentDayChangesAndCreatesValueFreeCheckpoint() async throws {
    let now = try date(year: 2026, month: 3, day: 29, hour: 12)
    let client = FakeMedicationClient(
      concepts: [MedicationConcept(id: firstID, name: "Example")],
      delta: MedicationAnchorDelta(candidateAnchor: Data([4, 5, 6]), hasChanges: true),
      doses: [
        MedicationDose(
          medicationID: firstID,
          status: .taken,
          schedule: .scheduled,
          doseQuantity: 1,
          unit: "tablet"
        )
      ]
    )
    let reader = HealthKitMedicationReader(client: client)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))

    try await reader.requestAuthorization()
    let result = try await reader.read(
      committedCheckpoint: nil,
      now: now,
      calendar: calendar
    )

    XCTAssertTrue(result.hasChanges)
    XCTAssertEqual(result.concepts.map(\.id), [firstID])
    XCTAssertEqual(result.doses.count, 1)
    XCTAssertEqual(result.candidateCheckpoint.medicationIDs, [firstID])
    XCTAssertFalse(result.candidateCheckpoint.sourceFingerprint.contains("Example"))
    let authorizationCount = await client.authorizationCount
    let intervals = await client.intervals
    XCTAssertEqual(authorizationCount, 1)
    XCTAssertEqual(intervals.first?.duration, 23 * 3_600)
  }

  func testDetectsRemovedAuthorizationOrMedicationAndSkipsExactNoChange() async throws {
    let unchangedConcept = MedicationConcept(id: firstID, name: "Example")
    let fingerprint = MedicationIdentifier.fingerprint([
      "\(unchangedConcept.id)|\(unchangedConcept.isArchived)|\(unchangedConcept.name ?? "")"
    ])
    let committed = MedicationCheckpoint(
      anchor: Data([1]),
      medicationIDs: [firstID],
      sourceFingerprint: fingerprint
    )
    let client = FakeMedicationClient(
      concepts: [unchangedConcept],
      delta: MedicationAnchorDelta(candidateAnchor: Data([2]), hasChanges: false),
      doses: []
    )
    let reader = HealthKitMedicationReader(client: client)

    let result = try await reader.read(
      committedCheckpoint: committed,
      now: .now,
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertFalse(result.hasChanges)
    XCTAssertTrue(result.removedMedicationIDs.isEmpty)
    let intervalCount = await client.intervals.count
    XCTAssertEqual(intervalCount, 0)

    let changedCommitted = MedicationCheckpoint(
      anchor: Data([1]),
      medicationIDs: [firstID, removedID],
      sourceFingerprint: fingerprint
    )
    let removal = try await reader.read(
      committedCheckpoint: changedCommitted,
      now: .now,
      calendar: Calendar(identifier: .gregorian)
    )
    XCTAssertEqual(removal.removedMedicationIDs, [removedID])
  }

  func testProductionMedicationTypesRequirePerObjectAuthorization() throws {
    if #available(iOS 26.0, *) {
      XCTAssertTrue(
        HKObjectType.userAnnotatedMedicationType().requiresPerObjectAuthorization()
      )
      XCTAssertFalse(HKObjectType.medicationDoseEventType().requiresPerObjectAuthorization())
    }
  }

  func testMedicationAuthorizationUsesOnlyPerObjectSelection() async throws {
    guard #available(iOS 26.0, *) else { return }
    let healthStore = RecordingMedicationHealthStore()
    let client = HKHealthStoreMedicationClient(healthStore: healthStore)

    try await client.requestAuthorization()

    XCTAssertEqual(healthStore.standardReadTypeIdentifiers, [])
    XCTAssertEqual(
      healthStore.perObjectReadTypeIdentifiers,
      [HKObjectType.userAnnotatedMedicationType().identifier]
    )
  }

  private func date(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
    return try XCTUnwrap(
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    )
  }
}

private final class RecordingMedicationHealthStore: HKHealthStore, @unchecked Sendable {
  private let lock = NSLock()
  private var standardReadTypes: [String] = []
  private var perObjectReadTypes: [String] = []

  var standardReadTypeIdentifiers: [String] {
    lock.withLock { standardReadTypes }
  }

  var perObjectReadTypeIdentifiers: [String] {
    lock.withLock { perObjectReadTypes }
  }

  override func requestAuthorization(
    toShare typesToShare: Set<HKSampleType>?,
    read typesToRead: Set<HKObjectType>?,
    completion: @escaping @Sendable (Bool, (any Error)?) -> Void
  ) {
    lock.withLock {
      standardReadTypes.append(contentsOf: (typesToRead ?? []).map(\.identifier))
    }
    completion(true, nil)
  }

  override func requestPerObjectReadAuthorization(
    for objectType: HKObjectType,
    predicate: NSPredicate?,
    completion: @escaping @Sendable (Bool, (any Error)?) -> Void
  ) {
    lock.withLock {
      perObjectReadTypes.append(objectType.identifier)
    }
    completion(true, nil)
  }
}

private actor FakeMedicationClient: HealthKitMedicationClient {
  private let storedConcepts: [MedicationConcept]
  private let delta: MedicationAnchorDelta
  private let storedDoses: [MedicationDose]
  private(set) var authorizationCount = 0
  private(set) var intervals: [DateInterval] = []

  init(
    concepts: [MedicationConcept],
    delta: MedicationAnchorDelta,
    doses: [MedicationDose]
  ) {
    storedConcepts = concepts
    self.delta = delta
    storedDoses = doses
  }

  func requestAuthorization() { authorizationCount += 1 }
  func concepts() -> [MedicationConcept] { storedConcepts }
  func doseChanges(anchor: Data?) -> MedicationAnchorDelta { delta }
  func doses(interval: DateInterval) -> [MedicationDose] {
    intervals.append(interval)
    return storedDoses
  }
}
