import Foundation
import HealthKit
import HealthSyncCore

enum HealthKitMetricQueryError: Error, Equatable, Sendable {
  case healthDataUnavailable
  case unsupportedMetric
  case invalidDateInterval
  case unsupportedAggregation
}

struct HealthKitQuantityResult: Sendable, Equatable {
  let timestamp: Date
  let value: Double
}

protocol HealthStoreClient: Sendable {
  func isHealthDataAvailable() async -> Bool
  func requestAuthorization(
    toShare shareTypes: Set<HKSampleType>,
    read readTypes: Set<HKObjectType>
  ) async throws
  func cumulativeSum(
    for type: HKQuantityType,
    unit: HKUnit,
    interval: DateInterval
  ) async throws -> HealthKitQuantityResult?
  func latestQuantity(
    for type: HKQuantityType,
    unit: HKUnit
  ) async throws -> HealthKitQuantityResult?
  func quantitySamples(
    for type: HKQuantityType,
    unit: HKUnit,
    symbol: UnitSymbol,
    interval: DateInterval
  ) async throws -> [HealthSample]
  func sleepIntervals(
    for type: HKCategoryType,
    interval: DateInterval
  ) async throws -> [SleepInterval]
  func categoryIntervals(
    for type: HKCategoryType,
    interval: DateInterval
  ) async throws -> [HealthSample]
  func latestWorkout() async throws -> WorkoutSummary?
}

extension HealthStoreClient {
  func quantitySamples(
    for type: HKQuantityType,
    unit: HKUnit,
    symbol: UnitSymbol,
    interval: DateInterval
  ) async throws -> [HealthSample] {
    []
  }
}

struct HealthKitMetricQueryService: MetricQuerying, BackfillPointQuerying, Sendable {
  private let store: any HealthStoreClient

  init(store: any HealthStoreClient) {
    self.store = store
  }

  func requestReadAuthorization(for metrics: Set<MetricID>) async throws {
    try Task.checkCancellation()
    guard await store.isHealthDataAvailable() else {
      throw HealthKitMetricQueryError.healthDataUnavailable
    }

    let definitions = metrics.compactMap { MetricRegistry[$0] }
    guard definitions.count == metrics.count else {
      throw HealthKitMetricQueryError.unsupportedMetric
    }
    let readTypes = Set(
      definitions.compactMap { try? HealthKitTypeResolver.objectType(for: $0.healthObjectType) }
    )
    guard !readTypes.isEmpty else {
      throw HealthKitMetricQueryError.unsupportedMetric
    }
    try await store.requestAuthorization(toShare: [], read: readTypes)
  }

  func currentReading(
    for definition: MetricDefinition,
    now: Date,
    calendar: Calendar
  ) async throws -> MetricReading? {
    try Task.checkCancellation()

    if definition.healthObjectType == .sleepAnalysis {
      guard
        let interval = MetricAggregator.dateInterval(
          for: definition.syncWindow,
          now: now,
          calendar: calendar
        )
      else {
        throw HealthKitMetricQueryError.invalidDateInterval
      }
      guard
        let type = try HealthKitTypeResolver.objectType(for: .sleepAnalysis) as? HKCategoryType
      else {
        throw HealthKitMetricQueryError.unsupportedMetric
      }
      let intervals = try await store.sleepIntervals(for: type, interval: interval)
      return try SleepAggregator.aggregate(intervals: intervals, now: now)[definition.id]
    }

    if definition.aggregation == .intervalDuration {
      guard
        let interval = MetricAggregator.dateInterval(
          for: definition.syncWindow,
          now: now,
          calendar: calendar
        )
      else {
        throw HealthKitMetricQueryError.invalidDateInterval
      }
      guard
        let type = try HealthKitTypeResolver.objectType(
          for: definition.healthObjectType
        ) as? HKCategoryType
      else {
        throw HealthKitMetricQueryError.unsupportedMetric
      }
      let samples = try await store.categoryIntervals(for: type, interval: interval)
      return try MetricAggregator.aggregate(
        samples: samples,
        definition: definition,
        now: now,
        calendar: calendar
      )
    }

    let type = try HealthKitTypeResolver.quantityType(for: definition.healthObjectType)
    let unit = try HealthKitTypeResolver.unit(for: definition.healthKitUnit)

    let result: HealthKitQuantityResult?
    let timestamp: Date
    switch definition.aggregation {
    case .dailyCumulativeSum:
      guard let interval = calendar.dateInterval(of: .day, for: now) else {
        throw HealthKitMetricQueryError.invalidDateInterval
      }
      result = try await store.cumulativeSum(for: type, unit: unit, interval: interval)
      timestamp = now
    case .latestSample:
      result = try await store.latestQuantity(for: type, unit: unit)
      timestamp = result?.timestamp ?? now
    default:
      throw HealthKitMetricQueryError.unsupportedAggregation
    }

    guard let result else {
      if definition.aggregation == .dailyCumulativeSum {
        return MetricReading(metricID: definition.id, timestamp: now, value: 0)
      }
      return nil
    }
    let sample = HealthSample(
      timestamp: timestamp,
      value: result.value,
      unit: definition.healthKitUnit
    )
    return try MetricTransformer.transform(sample, using: definition)
  }

  func latestWorkout(now: Date) async throws -> WorkoutSummary? {
    try Task.checkCancellation()
    return try await store.latestWorkout()
  }

  func points(
    for definition: MetricDefinition,
    interval: DateInterval,
    calendar: Calendar
  ) async throws -> [BackfillPoint] {
    try Task.checkCancellation()
    if definition.healthObjectType == .sleepAnalysis {
      guard
        let type = try HealthKitTypeResolver.objectType(for: .sleepAnalysis) as? HKCategoryType
      else { throw HealthKitMetricQueryError.unsupportedMetric }
      let intervals = try await store.sleepIntervals(for: type, interval: interval)
      if definition.id == .sleepDetails {
        let eligible = intervals.reduce(into: [UUID: SleepInterval]()) { result, interval in
          guard !interval.isFromThisApplication else { return }
          if let current = result[interval.id], current.end >= interval.end { return }
          result[interval.id] = interval
        }.values
        return eligible.sorted { $0.start < $1.start }.compactMap {
          guard let code = $0.stage.healthBridgeCode else { return nil }
          return BackfillPoint(timestamp: $0.start, value: Double(code))
        }
      }
      return try dayIntervals(in: interval, calendar: calendar).compactMap { day in
        let overlapping = intervals.filter { $0.end > day.start && $0.start < day.end }
        guard
          let reading = try SleepAggregator.aggregate(intervals: overlapping, now: day.end)[
            definition.id
          ]
        else { return nil }
        return BackfillPoint(timestamp: day.end, value: reading.value)
      }
    }

    if definition.aggregation == .intervalDuration {
      guard
        let type = try HealthKitTypeResolver.objectType(
          for: definition.healthObjectType
        ) as? HKCategoryType
      else { throw HealthKitMetricQueryError.unsupportedMetric }
      let samples = try await store.categoryIntervals(for: type, interval: interval)
      return try aggregateByDay(
        samples, definition: definition, interval: interval, calendar: calendar)
    }

    let type = try HealthKitTypeResolver.quantityType(for: definition.healthObjectType)
    let unit = try HealthKitTypeResolver.unit(for: definition.healthKitUnit)
    let samples = try await store.quantitySamples(
      for: type,
      unit: unit,
      symbol: definition.healthKitUnit,
      interval: interval
    )
    switch definition.aggregation {
    case .latestSample:
      return try samples.map {
        let reading = try MetricTransformer.transform($0, using: definition)
        return BackfillPoint(timestamp: reading.timestamp, value: reading.value)
      }
    case .dailyCumulativeSum, .dailyAverage, .dailyMinimum, .dailyMaximum:
      return try aggregateByDay(
        samples, definition: definition, interval: interval, calendar: calendar)
    default:
      throw HealthKitMetricQueryError.unsupportedAggregation
    }
  }

  private func aggregateByDay(
    _ samples: [HealthSample],
    definition: MetricDefinition,
    interval: DateInterval,
    calendar: Calendar
  ) throws -> [BackfillPoint] {
    try dayIntervals(in: interval, calendar: calendar).compactMap { day in
      let daySamples = samples.filter { $0.timestamp >= day.start && $0.timestamp < day.end }
      guard !daySamples.isEmpty,
        let reading = try MetricAggregator.aggregate(
          samples: daySamples,
          definition: definition,
          now: day.start,
          calendar: calendar
        )
      else { return nil }
      return BackfillPoint(timestamp: day.end, value: reading.value)
    }
  }

  private func dayIntervals(in interval: DateInterval, calendar: Calendar) throws
    -> [DateInterval]
  {
    var result: [DateInterval] = []
    var cursor = interval.start
    while cursor < interval.end {
      guard let day = calendar.dateInterval(of: .day, for: cursor) else {
        throw HealthKitMetricQueryError.invalidDateInterval
      }
      let clipped = DateInterval(
        start: max(day.start, interval.start), end: min(day.end, interval.end))
      if clipped.start < clipped.end { result.append(clipped) }
      cursor = day.end
    }
    return result
  }
}

final class HKHealthStoreClient: HealthStoreClient, @unchecked Sendable {
  private let healthStore: HKHealthStore

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func isHealthDataAvailable() -> Bool {
    HKHealthStore.isHealthDataAvailable()
  }

  func requestAuthorization(
    toShare shareTypes: Set<HKSampleType>,
    read readTypes: Set<HKObjectType>
  ) async throws {
    try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
  }

  func cumulativeSum(
    for type: HKQuantityType,
    unit: HKUnit,
    interval: DateInterval
  ) async throws -> HealthKitQuantityResult? {
    let predicate = HKQuery.predicateForSamples(
      withStart: interval.start,
      end: interval.end,
      options: [.strictStartDate, .strictEndDate]
    )
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: type, predicate: predicate)],
      sortDescriptors: [SortDescriptor(\HKQuantitySample.endDate)]
    )
    let samples = try await descriptor.result(for: healthStore).filter {
      Self.shouldInclude($0, applicationBundleIdentifier: Bundle.main.bundleIdentifier)
    }
    guard !samples.isEmpty else { return nil }
    let value = samples.reduce(0) { result, sample in
      result + sample.quantity.doubleValue(for: unit)
    }
    return HealthKitQuantityResult(
      timestamp: interval.end,
      value: value
    )
  }

  func latestQuantity(
    for type: HKQuantityType,
    unit: HKUnit
  ) async throws -> HealthKitQuantityResult? {
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: type)],
      sortDescriptors: [SortDescriptor(\HKQuantitySample.endDate, order: .reverse)],
      limit: HKObjectQueryNoLimit
    )
    guard
      let sample = try await descriptor.result(for: healthStore).first(where: {
        Self.shouldInclude($0, applicationBundleIdentifier: Bundle.main.bundleIdentifier)
      })
    else {
      return nil
    }
    return HealthKitQuantityResult(
      timestamp: sample.endDate,
      value: sample.quantity.doubleValue(for: unit)
    )
  }

  func quantitySamples(
    for type: HKQuantityType,
    unit: HKUnit,
    symbol: UnitSymbol,
    interval: DateInterval
  ) async throws -> [HealthSample] {
    let predicate = HKQuery.predicateForSamples(
      withStart: interval.start,
      end: interval.end,
      options: [.strictStartDate, .strictEndDate]
    )
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: type, predicate: predicate)],
      sortDescriptors: [SortDescriptor(\HKQuantitySample.endDate)]
    )
    let applicationBundleIdentifier = Bundle.main.bundleIdentifier
    return try await descriptor.result(for: healthStore).compactMap { sample in
      guard Self.shouldInclude(sample, applicationBundleIdentifier: applicationBundleIdentifier)
      else { return nil }
      return HealthSample(
        id: sample.uuid,
        timestamp: sample.endDate,
        value: sample.quantity.doubleValue(for: unit),
        unit: symbol,
        sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
        isFromThisApplication: false,
        isImportedFromHomeAssistant: false
      )
    }
  }

  nonisolated static func shouldInclude(
    _ sample: HKSample,
    applicationBundleIdentifier: String?
  ) -> Bool {
    let isThisApplication =
      sample.sourceRevision.source.bundleIdentifier
      == applicationBundleIdentifier
    let isHomeAssistantImport =
      sample.metadata?[HealthKitOriginMetadata.key] as? String
      == HealthKitOriginMetadata.homeAssistant
    return !isThisApplication && !isHomeAssistantImport
  }

  func sleepIntervals(
    for type: HKCategoryType,
    interval: DateInterval
  ) async throws -> [SleepInterval] {
    let predicate = HKQuery.predicateForSamples(
      withStart: interval.start,
      end: interval.end,
      options: [.strictStartDate]
    )
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.categorySample(type: type, predicate: predicate)],
      sortDescriptors: [SortDescriptor(\HKCategorySample.startDate)]
    )
    let applicationBundleIdentifier = Bundle.main.bundleIdentifier
    return try await descriptor.result(for: healthStore).compactMap { sample in
      guard
        let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
        let stage = HealthKitSleepMapper.stage(for: value)
      else {
        return nil
      }
      let sourceBundleIdentifier = sample.sourceRevision.source.bundleIdentifier
      return SleepInterval(
        id: sample.uuid,
        stage: stage,
        start: sample.startDate,
        end: sample.endDate,
        sourceBundleIdentifier: sourceBundleIdentifier,
        isFromThisApplication: sourceBundleIdentifier == applicationBundleIdentifier
      )
    }
  }

  func categoryIntervals(
    for type: HKCategoryType,
    interval: DateInterval
  ) async throws -> [HealthSample] {
    let predicate = HKQuery.predicateForSamples(
      withStart: interval.start,
      end: interval.end,
      options: [.strictStartDate]
    )
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.categorySample(type: type, predicate: predicate)],
      sortDescriptors: [SortDescriptor(\HKCategorySample.startDate)]
    )
    let applicationBundleIdentifier = Bundle.main.bundleIdentifier
    return try await descriptor.result(for: healthStore).map { sample in
      let sourceBundleIdentifier = sample.sourceRevision.source.bundleIdentifier
      return HealthSample(
        id: sample.uuid,
        startDate: sample.startDate,
        endDate: sample.endDate,
        value: sample.endDate.timeIntervalSince(sample.startDate),
        unit: .seconds,
        sourceBundleIdentifier: sourceBundleIdentifier,
        isFromThisApplication: sourceBundleIdentifier == applicationBundleIdentifier
      )
    }
  }

  func latestWorkout() async throws -> WorkoutSummary? {
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.workout()],
      sortDescriptors: [SortDescriptor(\HKWorkout.endDate, order: .reverse)],
      limit: 1
    )
    guard let workout = try await descriptor.result(for: healthStore).first else {
      return nil
    }

    let activeEnergy = quantity(
      from: workout,
      identifier: .activeEnergyBurned,
      unit: .kilocalorie()
    )
    let distance = distanceMetres(from: workout)
    let heartRate = try await heartRateStatistics(
      interval: DateInterval(start: workout.startDate, end: workout.endDate)
    )
    return WorkoutSummary(
      activityName: HealthKitWorkoutMapper.activityName(for: workout.workoutActivityType),
      start: workout.startDate,
      end: workout.endDate,
      durationSeconds: workout.duration,
      distanceMetres: distance,
      activeEnergyKilocalories: activeEnergy,
      averageHeartRateBPM: heartRate.average,
      maximumHeartRateBPM: heartRate.maximum
    )
  }

  private func distanceMetres(from workout: HKWorkout) -> Double? {
    let identifiers: [HKQuantityTypeIdentifier] = [
      .distanceWalkingRunning,
      .distanceCycling,
      .distanceSwimming,
      .distanceDownhillSnowSports,
    ]
    let values = identifiers.compactMap {
      quantity(from: workout, identifier: $0, unit: .meter())
    }
    return values.isEmpty ? nil : values.reduce(0, +)
  }

  private func quantity(
    from workout: HKWorkout,
    identifier: HKQuantityTypeIdentifier,
    unit: HKUnit
  ) -> Double? {
    guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
      return nil
    }
    return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
  }

  private func heartRateStatistics(
    interval: DateInterval
  ) async throws -> (average: Double?, maximum: Double?) {
    guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
      return (nil, nil)
    }
    let predicate = HKQuery.predicateForSamples(
      withStart: interval.start,
      end: interval.end,
      options: [.strictStartDate, .strictEndDate]
    )
    let descriptor = HKStatisticsQueryDescriptor(
      predicate: .quantitySample(type: type, predicate: predicate),
      options: [.discreteAverage, .discreteMax]
    )
    let statistics = try await descriptor.result(for: healthStore)
    let unit = HKUnit.count().unitDivided(by: .minute())
    return (
      statistics?.averageQuantity()?.doubleValue(for: unit),
      statistics?.maximumQuantity()?.doubleValue(for: unit)
    )
  }
}
