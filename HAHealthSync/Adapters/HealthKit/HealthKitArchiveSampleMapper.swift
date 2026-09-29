import Foundation
import HealthKit
import HealthSyncCore

struct HealthKitArchiveSampleMapper: Sendable {
  let applicationBundleID: String

  init(
    applicationBundleID: String = Bundle.main.bundleIdentifier ?? "com.marynavdovenko.HAHealthSync"
  ) {
    self.applicationBundleID = applicationBundleID
  }

  func map(_ sample: HKSample, type: HealthObjectTypeID) throws -> ArchiveSample? {
    guard !HealthKitOriginMetadata.excludes(sample, applicationBundleID: applicationBundleID) else {
      return nil
    }
    guard sample.sampleType == (try HealthKitTypeResolver.objectType(for: type)) else {
      throw ArchiveValidationError.invalidSample
    }
    let payload: ArchiveSamplePayload
    if let quantity = sample as? HKQuantitySample {
      guard let definition = MetricRegistry.selectable.first(where: { $0.healthObjectType == type })
      else { throw HealthKitMetricQueryError.unsupportedMetric }
      let unit = try HealthKitTypeResolver.unit(for: definition.healthKitUnit)
      let value = quantity.quantity.doubleValue(for: unit)
      guard value.isFinite else { throw ArchiveValidationError.invalidSample }
      // HKQuantity exposes conversion, not its original storage unit. Both fields describe
      // this explicitly chosen registry query unit, never an inferred original unit.
      // The server catalog uses UnitSymbol tokens; HKUnit.unitString differs for fractions,
      // cadence, MET, micrograms, and other compound units.
      payload = .quantity(
        ArchiveQuantityPayload(
          rawValue: value, rawUnit: definition.healthKitUnit.rawValue, canonicalValue: value,
          canonicalUnit: definition.healthKitUnit.rawValue))
    } else if let category = sample as? HKCategorySample {
      payload = .category(ArchiveCategoryPayload(value: category.value))
    } else if let workout = sample as? HKWorkout {
      payload = .workout(
        ArchiveWorkoutPayload(
          activityType: String(workout.workoutActivityType.rawValue),
          durationSeconds: workout.duration,
          totalEnergy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
            .map {
              ArchiveWorkoutQuantity(value: $0.doubleValue(for: .kilocalorie()), unit: "kcal")
            },
          totalDistance: workout.totalDistance.map {
            ArchiveWorkoutQuantity(value: $0.doubleValue(for: .meter()), unit: "m")
          },
          detail: workout.workoutEvents.map { events in
            [
              "events": .array(
                events.map {
                  .object([
                    "type": .number(Double($0.type.rawValue)),
                    "start": .string(Self.timestamp($0.dateInterval.start)),
                    "end": .string(Self.timestamp($0.dateInterval.end)),
                  ])
                })
            ]
          }))
    } else {
      throw ArchiveValidationError.invalidSample
    }
    let revision = sample.sourceRevision
    let os = revision.operatingSystemVersion
    let revisionText = [
      revision.version, revision.productType,
      "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
    ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ";")
    let timeZone = sample.metadata?[HKMetadataKeyTimeZone] as? String
    let device = sample.device.map {
      ArchiveDevice(
        manufacturer: $0.manufacturer, model: $0.model, name: $0.name,
        hardwareVersion: $0.hardwareVersion, softwareVersion: $0.softwareVersion)
    }
    return ArchiveSample(
      uuid: sample.uuid.uuidString.lowercased(), start: Self.timestamp(sample.startDate),
      end: Self.timestamp(sample.endDate),
      source: ArchiveSource(
        bundleID: revision.source.bundleIdentifier, name: revision.source.name,
        revision: revisionText),
      timeZone: timeZone.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil } ?? "UTC",
      metadata: Self.metadata(sample.metadata), payload: payload, device: device)
  }

  private static func timestamp(_ date: Date) -> String {
    // The wire supports microseconds; ISO8601DateFormatter's fractional format emits only
    // milliseconds. Round to the wire precision before separating whole/fractional seconds.
    let microseconds = (date.timeIntervalSince1970 * 1_000_000).rounded()
    let seconds = floor(microseconds / 1_000_000)
    let fraction = Int(microseconds - seconds * 1_000_000)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let whole = formatter.string(from: Date(timeIntervalSince1970: seconds)).dropLast()
    let digits =
      fraction % 1000 == 0
      ? String(format: "%03d", fraction / 1000) : String(format: "%06d", fraction)
    return "\(whole).\(digits)Z"
  }

  private static func metadata(_ values: [String: Any]?) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    for key in [
      HKMetadataKeyWasUserEntered, HKMetadataKeyIndoorWorkout, HKMetadataKeySwimmingLocationType,
      HKMetadataKeySwimmingStrokeStyle, HKMetadataKeyVO2MaxTestType,
      HKMetadataKeyHeartRateMotionContext, HKMetadataKeyInsulinDeliveryReason,
    ] {
      guard let value = values?[key] as? NSNumber else { continue }
      if key == HKMetadataKeyWasUserEntered || key == HKMetadataKeyIndoorWorkout {
        result[key] = .boolean(value.boolValue)
      } else if value.doubleValue.isFinite {
        result[key] = .number(value.doubleValue)
      }
    }
    // Missing/invalid source time zone is represented as UTC for the UTC instants;
    // only a genuine source-provided zone is retained as metadata provenance.
    if let zone = values?[HKMetadataKeyTimeZone] as? String, TimeZone(identifier: zone) != nil {
      result[HKMetadataKeyTimeZone] = .string(zone)
    }
    return result
  }
}
