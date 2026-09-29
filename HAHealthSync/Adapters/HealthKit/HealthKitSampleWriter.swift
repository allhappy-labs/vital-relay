import HealthKit
import HealthSyncCore

enum HealthKitSampleWriterError: Error, Equatable, Sendable {
  case healthDataUnavailable
  case unsupportedDestination
  case authorizationNotDetermined
  case authorizationDenied
  case invalidSample
}

protocol HealthKitWritingClient: Sendable {
  func isHealthDataAvailable() async -> Bool
  func requestAuthorization(toShare types: Set<HKSampleType>) async throws
  func authorizationStatus(for type: HKObjectType) async -> HKAuthorizationStatus
  func save(_ sample: HKQuantitySample) async throws
}

struct HealthKitSampleWriter: HealthSampleWriting, Sendable {
  private let client: any HealthKitWritingClient

  init(client: any HealthKitWritingClient) {
    self.client = client
  }

  func requestWriteAuthorization(for destinations: Set<HealthObjectTypeID>) async throws {
    try Task.checkCancellation()
    guard await client.isHealthDataAvailable() else {
      throw HealthKitSampleWriterError.healthDataUnavailable
    }
    let types = try Set(
      destinations.map { destination -> HKSampleType in
        guard WritableHealthRegistry[destination] != nil else {
          throw HealthKitSampleWriterError.unsupportedDestination
        }
        return try HealthKitTypeResolver.quantityType(for: destination)
      }
    )
    try await client.requestAuthorization(toShare: types)
    for type in types {
      switch await client.authorizationStatus(for: type) {
      case .notDetermined:
        throw HealthKitSampleWriterError.authorizationNotDetermined
      case .sharingDenied:
        throw HealthKitSampleWriterError.authorizationDenied
      case .sharingAuthorized:
        continue
      @unknown default:
        throw HealthKitSampleWriterError.authorizationDenied
      }
    }
  }

  func save(_ sample: HealthSampleWrite) async throws {
    try Task.checkCancellation()
    guard let destination = WritableHealthRegistry[sample.destination],
      sample.value.isFinite,
      destination.plausibleBounds.contains(sample.value),
      sample.syncVersion == 1,
      sample.syncIdentifier.count == 79,
      sample.syncIdentifier.hasPrefix("ha-health-sync."),
      sample.syncIdentifier == sample.syncIdentifier.lowercased()
    else {
      throw HealthKitSampleWriterError.invalidSample
    }

    let type = try HealthKitTypeResolver.quantityType(for: sample.destination)
    switch await client.authorizationStatus(for: type) {
    case .notDetermined:
      throw HealthKitSampleWriterError.authorizationNotDetermined
    case .sharingDenied:
      throw HealthKitSampleWriterError.authorizationDenied
    case .sharingAuthorized:
      break
    @unknown default:
      throw HealthKitSampleWriterError.authorizationDenied
    }

    let unit = try HealthKitTypeResolver.unit(for: destination.nativeUnit)
    let quantity = HKQuantity(unit: unit, doubleValue: sample.value)
    let healthKitSample = HKQuantitySample(
      type: type,
      quantity: quantity,
      start: sample.date,
      end: sample.date,
      metadata: [
        HKMetadataKeySyncIdentifier: sample.syncIdentifier,
        HKMetadataKeySyncVersion: sample.syncVersion,
        HealthKitOriginMetadata.key: HealthKitOriginMetadata.homeAssistant,
      ]
    )
    try Task.checkCancellation()
    try await client.save(healthKitSample)
  }
}

final class HKHealthStoreWritingClient: HealthKitWritingClient, @unchecked Sendable {
  private let healthStore: HKHealthStore

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func isHealthDataAvailable() -> Bool {
    HKHealthStore.isHealthDataAvailable()
  }

  func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
    try await healthStore.requestAuthorization(toShare: types, read: [])
  }

  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
    healthStore.authorizationStatus(for: type)
  }

  func save(_ sample: HKQuantitySample) async throws {
    try await healthStore.save(sample)
  }
}
