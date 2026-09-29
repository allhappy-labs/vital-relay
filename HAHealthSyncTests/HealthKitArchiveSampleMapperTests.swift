import Foundation
import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitArchiveSampleMapperTests: XCTestCase {
  func testEveryQuantityWireUnitMatchesForkCatalog() throws {
    // Independent source/unit snapshot from Health_Bridge/docs/protocol/fixtures/archive-catalog-v2.json.
    struct Catalog: Decodable {
      struct Source: Decodable {
        let sampleType: String
        let payloadKind: String
        let canonicalUnit: String?
      }
      let sources: [Source]
    }
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "archive-source-units-v2", withExtension: "json"))
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let catalog = try decoder.decode(Catalog.self, from: Data(contentsOf: url))
    let mapper = HealthKitArchiveSampleMapper(applicationBundleID: "other.app")
    let date = Date(timeIntervalSince1970: 1000)
    let quantitySources = catalog.sources.filter { $0.payloadKind == "quantity" }
    let registeredTypes = Set(
      MetricRegistry.selectable.map(\.healthObjectType).filter {
        $0.rawValue.hasPrefix("HKQuantity")
      })
    XCTAssertEqual(Set(quantitySources.map(\.sampleType)), Set(registeredTypes.map(\.rawValue)))
    for source in quantitySources {
      let type = try XCTUnwrap(HealthObjectTypeID(rawValue: source.sampleType))
      let definition = try XCTUnwrap(
        MetricRegistry.selectable.first { $0.healthObjectType == type })
      let sample = HKQuantitySample(
        type: try HealthKitTypeResolver.quantityType(for: type),
        quantity: HKQuantity(
          unit: try HealthKitTypeResolver.unit(for: definition.healthKitUnit), doubleValue: 1),
        start: date, end: date.addingTimeInterval(60),
        metadata: type == .insulinDelivery
          ? [HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.bolus.rawValue] : nil)
      let mapped = try XCTUnwrap(mapper.map(sample, type: type))
      if type == .insulinDelivery {
        XCTAssertEqual(mapped.metadata[HKMetadataKeyInsulinDeliveryReason], .number(2))
      }
      guard case .quantity(let payload) = mapped.payload else {
        return XCTFail("Expected quantity")
      }
      XCTAssertEqual(payload.rawUnit, source.canonicalUnit, source.sampleType)
      XCTAssertEqual(payload.canonicalUnit, source.canonicalUnit, source.sampleType)
      XCTAssertEqual(payload.canonicalValue, 1, accuracy: 0.000001, source.sampleType)
    }
  }

  func testPreservesSubmillisecondSampleInstants() throws {
    let date = Date(timeIntervalSince1970: 1_000.123456)
    let sample = HKQuantitySample(
      type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 1),
      start: date, end: date)
    let result = try XCTUnwrap(
      HealthKitArchiveSampleMapper(applicationBundleID: "other.app").map(sample, type: .stepCount))
    XCTAssertEqual(result.start, "1970-01-01T00:16:40.123456Z")
    XCTAssertEqual(result.end, "1970-01-01T00:16:40.123456Z")
  }

  func testQuantityPreservesIdentityIntervalsCanonicalUnitAndAllowlistedProvenance() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let device = HKDevice(
      name: "Watch", manufacturer: "Apple", model: "Watch", hardwareVersion: "1",
      firmwareVersion: nil, softwareVersion: "27", localIdentifier: "private",
      udiDeviceIdentifier: nil)
    let sample = HKQuantitySample(
      type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gram(), doubleValue: 72_000),
      start: start, end: start.addingTimeInterval(1), device: device,
      metadata: [
        HKMetadataKeyTimeZone: "Europe/Zurich", HKMetadataKeyWasUserEntered: true,
        "secret": "discard",
      ])
    let result = try XCTUnwrap(
      HealthKitArchiveSampleMapper(applicationBundleID: "other.app").map(sample, type: .bodyMass))
    XCTAssertEqual(result.uuid, sample.uuid.uuidString.lowercased())
    XCTAssertEqual(result.start, "1970-01-01T00:16:40.000Z")
    XCTAssertEqual(result.end, "1970-01-01T00:16:41.000Z")
    XCTAssertEqual(result.timeZone, "Europe/Zurich")
    XCTAssertNil(result.metadata["secret"])
    XCTAssertEqual(result.metadata[HKMetadataKeyWasUserEntered], .boolean(true))
    XCTAssertEqual(result.device?.model, "Watch")
    XCTAssertEqual(result.source.bundleID, sample.sourceRevision.source.bundleIdentifier)
    XCTAssertFalse(result.source.revision.isEmpty)
    guard case .quantity(let quantity) = result.payload else { return XCTFail("Expected quantity") }
    XCTAssertEqual(quantity.rawValue, 72)
    XCTAssertEqual(quantity.rawUnit, "kg")
    XCTAssertEqual(quantity.canonicalValue, 72)
    XCTAssertEqual(quantity.canonicalUnit, "kg")
  }

  // The legacy constructor creates an in-memory fixture without saving personal HealthKit data.
  @available(*, deprecated)
  func testCategoryAndWorkoutRemainOriginalTypedSamples() throws {
    let start = Date(timeIntervalSince1970: 100)
    let mapper = HealthKitArchiveSampleMapper(applicationBundleID: "other.app")
    let category = HKCategorySample(
      type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
      start: start, end: start.addingTimeInterval(60))
    let mapped = try XCTUnwrap(mapper.map(category, type: .sleepAnalysis))
    XCTAssertEqual(mapped.payload, .category(ArchiveCategoryPayload(value: 5)))
    XCTAssertEqual(mapped.uuid, category.uuid.uuidString.lowercased())
    let workout = HKWorkout(
      activityType: .running, start: start, end: start.addingTimeInterval(600), duration: 590,
      totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 80),
      totalDistance: HKQuantity(unit: .meter(), doubleValue: 1_000), metadata: nil)
    let result = try XCTUnwrap(mapper.map(workout, type: .workout))
    XCTAssertEqual(result.uuid, workout.uuid.uuidString.lowercased())
    guard case .workout(let payload) = result.payload else { return XCTFail("Expected workout") }
    XCTAssertEqual(payload.durationSeconds, 590)
    XCTAssertEqual(payload.totalDistance, ArchiveWorkoutQuantity(value: 1_000, unit: "m"))
    XCTAssertEqual(payload.totalEnergy, ArchiveWorkoutQuantity(value: 80, unit: "kcal"))
  }

  func testFiltersOwnAppAndHomeAssistantOrigins() throws {
    let date = Date()
    let sample = HKQuantitySample(
      type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 1),
      start: date, end: date)
    XCTAssertNil(
      try HealthKitArchiveSampleMapper(
        applicationBundleID: sample.sourceRevision.source.bundleIdentifier
      ).map(sample, type: .stepCount))
    let imported = HKQuantitySample(
      type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 1),
      start: date, end: date,
      metadata: [HealthKitOriginMetadata.key: HealthKitOriginMetadata.homeAssistant])
    XCTAssertNil(
      try HealthKitArchiveSampleMapper(applicationBundleID: "other.app").map(
        imported, type: .stepCount))
  }
}
