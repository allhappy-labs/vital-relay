import Foundation
import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitSampleWriterTests: XCTestCase {
  private let identifier = "ha-health-sync." + String(repeating: "a", count: 64)

  func testRequestsOnlyAllowlistedWriteTypes() async throws {
    let client = FakeHealthKitWritingClient()
    let writer = HealthKitSampleWriter(client: client)

    try await writer.requestWriteAuthorization(for: [.bodyMass, .dietaryWater, .uvExposure])

    let identifiers = await client.requestedTypes.map(\.identifier)
    XCTAssertEqual(
      Set(identifiers),
      Set([
        HealthObjectTypeID.bodyMass.rawValue,
        HealthObjectTypeID.dietaryWater.rawValue,
        HealthObjectTypeID.uvExposure.rawValue,
      ]))
  }

  func testRejectsUnavailableAndUnsupportedAuthorizationRequests() async {
    let unavailable = HealthKitSampleWriter(
      client: FakeHealthKitWritingClient(isAvailable: false)
    )
    await assertThrows(.healthDataUnavailable) {
      try await unavailable.requestWriteAuthorization(for: [.bodyMass])
    }

    let writer = HealthKitSampleWriter(client: FakeHealthKitWritingClient())
    await assertThrows(.unsupportedDestination) {
      try await writer.requestWriteAuthorization(for: [.restingHeartRate])
    }
  }

  func testAuthorizationRequestRequiresGrantedSharingState() async {
    let undetermined = HealthKitSampleWriter(
      client: FakeHealthKitWritingClient(status: .notDetermined)
    )
    await assertThrows(.authorizationNotDetermined) {
      try await undetermined.requestWriteAuthorization(for: [.uvExposure])
    }

    let denied = HealthKitSampleWriter(
      client: FakeHealthKitWritingClient(status: .sharingDenied)
    )
    await assertThrows(.authorizationDenied) {
      try await denied.requestWriteAuthorization(for: [.uvExposure])
    }
  }

  func testSaveRequiresAuthorizedSharingState() async {
    let undetermined = HealthKitSampleWriter(
      client: FakeHealthKitWritingClient(status: .notDetermined)
    )
    await assertThrows(.authorizationNotDetermined) {
      try await undetermined.save(self.write())
    }

    let denied = HealthKitSampleWriter(
      client: FakeHealthKitWritingClient(status: .sharingDenied)
    )
    await assertThrows(.authorizationDenied) {
      try await denied.save(self.write())
    }
  }

  func testCreatesNativeQuantityWithStableValueFreeMetadata() async throws {
    let client = FakeHealthKitWritingClient(status: .sharingAuthorized)
    let writer = HealthKitSampleWriter(client: client)
    let write = write()

    try await writer.save(write)

    let savedSamples = await client.savedSamples
    let sample = try XCTUnwrap(savedSamples.first)
    XCTAssertEqual(sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), 70)
    XCTAssertEqual(sample.startDate, write.date)
    XCTAssertEqual(sample.endDate, write.date)
    XCTAssertEqual(sample.metadata?[HKMetadataKeySyncIdentifier] as? String, identifier)
    XCTAssertEqual(sample.metadata?[HKMetadataKeySyncVersion] as? Int, 1)
    XCTAssertEqual(
      sample.metadata?[HealthKitOriginMetadata.key] as? String,
      HealthKitOriginMetadata.homeAssistant
    )
    XCTAssertNil(sample.metadata?["entity_id"])
    XCTAssertFalse(String(describing: sample.metadata).contains("70"))
  }

  func testCreatesUVExposureWithHealthKitCountUnit() async throws {
    let client = FakeHealthKitWritingClient(status: .sharingAuthorized)
    let writer = HealthKitSampleWriter(client: client)

    try await writer.save(write(destination: .uvExposure, value: 7.4))

    let savedSamples = await client.savedSamples
    let sample = try XCTUnwrap(savedSamples.first)
    XCTAssertEqual(sample.quantityType.identifier, HealthObjectTypeID.uvExposure.rawValue)
    XCTAssertEqual(sample.quantity.doubleValue(for: .count()), 7.4)
  }

  func testRejectsInvalidValueIdentityAndVersionBeforeSave() async {
    let client = FakeHealthKitWritingClient(status: .sharingAuthorized)
    let writer = HealthKitSampleWriter(client: client)

    await assertThrows(.invalidSample) { try await writer.save(self.write(value: .nan)) }
    await assertThrows(.invalidSample) { try await writer.save(self.write(value: 900)) }
    await assertThrows(.invalidSample) {
      try await writer.save(self.write(identifier: "entity.sensor_mass"))
    }
    await assertThrows(.invalidSample) { try await writer.save(self.write(version: 2)) }
    let savedSamples = await client.savedSamples
    XCTAssertTrue(savedSamples.isEmpty)
  }

  func testSaveFailureAndCancellationPropagateWithoutRetry() async {
    let failing = HealthKitSampleWriter(
      client: FakeHealthKitWritingClient(
        status: .sharingAuthorized, saveError: TestFailure.expected)
    )
    do {
      try await failing.save(write())
      XCTFail("Expected save failure")
    } catch {
      XCTAssertEqual(error as? TestFailure, .expected)
    }

    let client = FakeHealthKitWritingClient(status: .sharingAuthorized)
    let writer = HealthKitSampleWriter(client: client)
    let sample = write()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await writer.save(sample)
    }
    do {
      try await task.value
      XCTFail("Expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    let savedSamples = await client.savedSamples
    XCTAssertTrue(savedSamples.isEmpty)
  }

  private func write(
    destination: HealthObjectTypeID = .bodyMass,
    value: Double = 70,
    identifier: String? = nil,
    version: Int = 1
  ) -> HealthSampleWrite {
    HealthSampleWrite(
      destination: destination,
      value: value,
      date: Date(timeIntervalSince1970: 1_788_052_801),
      syncIdentifier: identifier ?? self.identifier,
      syncVersion: version
    )
  }

  private func assertThrows(
    _ expected: HealthKitSampleWriterError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected)")
    } catch {
      XCTAssertEqual(error as? HealthKitSampleWriterError, expected)
    }
  }

  private enum TestFailure: Error { case expected }
}

private actor FakeHealthKitWritingClient: HealthKitWritingClient {
  let isAvailable: Bool
  let status: HKAuthorizationStatus
  let saveError: (any Error)?
  private(set) var requestedTypes: Set<HKSampleType> = []
  private(set) var savedSamples: [HKQuantitySample] = []

  init(
    isAvailable: Bool = true,
    status: HKAuthorizationStatus = .sharingAuthorized,
    saveError: (any Error)? = nil
  ) {
    self.isAvailable = isAvailable
    self.status = status
    self.saveError = saveError
  }

  func isHealthDataAvailable() -> Bool { isAvailable }

  func requestAuthorization(toShare types: Set<HKSampleType>) {
    requestedTypes.formUnion(types)
  }

  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
    status
  }

  func save(_ sample: HKQuantitySample) throws {
    try Task.checkCancellation()
    if let saveError { throw saveError }
    savedSamples.append(sample)
  }
}
