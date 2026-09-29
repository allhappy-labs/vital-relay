import Foundation
import HealthKit
import HealthSyncCore
import XCTest

@testable import HAHealthSync

final class HealthKitMetricQueryServiceTests: XCTestCase {
  func testRequestsOnlySelectedReadTypesAndNoShareTypes() async throws {
    let store = FakeHealthStoreClient()
    let service = HealthKitMetricQueryService(store: store)

    try await service.requestReadAuthorization(for: [.steps, .bodyMass])

    let authorization = await store.authorizationRequest
    XCTAssertEqual(authorization?.shareCount, 0)
    XCTAssertEqual(
      authorization?.readIdentifiers,
      Set([
        HKQuantityTypeIdentifier.stepCount.rawValue,
        HKQuantityTypeIdentifier.bodyMass.rawValue,
      ])
    )
  }

  func testUnavailableHealthDataFailsBeforeAuthorization() async {
    let store = FakeHealthStoreClient(healthDataAvailable: false)
    let service = HealthKitMetricQueryService(store: store)

    do {
      try await service.requestReadAuthorization(for: [.steps])
      XCTFail("Expected healthDataUnavailable")
    } catch {
      XCTAssertEqual(error as? HealthKitMetricQueryError, .healthDataUnavailable)
    }
    let authorization = await store.authorizationRequest
    XCTAssertNil(authorization)
  }

  func testUnavailableMetricDoesNotPreventAuthorizationOfAvailableType() async throws {
    let store = FakeHealthStoreClient()
    let service = HealthKitMetricQueryService(store: store)

    try await service.requestReadAuthorization(for: [.steps, .uvExposureSED])

    let authorization = await store.authorizationRequest
    XCTAssertEqual(
      authorization?.readIdentifiers,
      Set([HKQuantityTypeIdentifier.stepCount.rawValue])
    )
  }

  func testStepsUseCalendarDayAcrossDST() async throws {
    let now = try date(
      year: 2026,
      month: 3,
      day: 29,
      hour: 12,
      timeZoneID: "Europe/Zurich"
    )
    let store = FakeHealthStoreClient(
      cumulativeResult: HealthKitQuantityResult(timestamp: now, value: 8_421)
    )
    let service = HealthKitMetricQueryService(store: store)
    let definition = try XCTUnwrap(MetricRegistry[.steps])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))

    let reading = try await service.currentReading(
      for: definition,
      now: now,
      calendar: calendar
    )

    XCTAssertEqual(reading?.metricID, .steps)
    XCTAssertEqual(reading?.timestamp, now)
    XCTAssertEqual(reading?.value, 8_421)
    let request = await store.cumulativeRequest
    XCTAssertEqual(request?.typeIdentifier, HKQuantityTypeIdentifier.stepCount.rawValue)
    XCTAssertEqual(request?.unit, HKUnit.count().unitString)
    XCTAssertEqual(request?.interval.duration, 23 * 60 * 60)
    XCTAssertEqual(request?.interval.start, calendar.startOfDay(for: now))
  }

  func testLatestMetricsPreserveSampleTimestampAndUnits() async throws {
    let timestamp = Date(timeIntervalSince1970: 1_788_035_400)
    let store = FakeHealthStoreClient(
      latestResults: [
        HKQuantityTypeIdentifier.bodyMass.rawValue: HealthKitQuantityResult(
          timestamp: timestamp,
          value: 80
        ),
        HKQuantityTypeIdentifier.restingHeartRate.rawValue: HealthKitQuantityResult(
          timestamp: timestamp,
          value: 55
        ),
      ]
    )
    let service = HealthKitMetricQueryService(store: store)
    let calendar = Calendar(identifier: .gregorian)

    let bodyMass = try await service.currentReading(
      for: try XCTUnwrap(MetricRegistry[.bodyMass]),
      now: timestamp,
      calendar: calendar
    )
    let restingHeartRate = try await service.currentReading(
      for: try XCTUnwrap(MetricRegistry[.restingHeartRate]),
      now: timestamp,
      calendar: calendar
    )

    XCTAssertEqual(bodyMass, MetricReading(metricID: .bodyMass, timestamp: timestamp, value: 80))
    XCTAssertEqual(
      restingHeartRate,
      MetricReading(metricID: .restingHeartRate, timestamp: timestamp, value: 55)
    )
    let requests = await store.latestRequests
    XCTAssertEqual(
      requests[HKQuantityTypeIdentifier.bodyMass.rawValue], HKUnit.gramUnit(with: .kilo).unitString)
    XCTAssertEqual(
      requests[HKQuantityTypeIdentifier.restingHeartRate.rawValue],
      HKUnit.count().unitDivided(by: .minute()).unitString
    )
  }

  func testEmptyQueriesReturnNoReading() async throws {
    let store = FakeHealthStoreClient()
    let service = HealthKitMetricQueryService(store: store)

    let reading = try await service.currentReading(
      for: try XCTUnwrap(MetricRegistry[.bodyMass]),
      now: .now,
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertNil(reading)
  }

  func testEmptyCumulativeQueryReturnsAuthoritativeZero() async throws {
    let store = FakeHealthStoreClient()
    let service = HealthKitMetricQueryService(store: store)
    let now = Date(timeIntervalSince1970: 1_788_035_400)

    let reading = try await service.currentReading(
      for: try XCTUnwrap(MetricRegistry[.steps]),
      now: now,
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(reading, MetricReading(metricID: .steps, timestamp: now, value: 0))
  }

  func testSleepDefinitionsUseOneNormalizedIntervalQuery() async throws {
    let now = Date(timeIntervalSince1970: 1_788_035_400)
    let sleepStart = now.addingTimeInterval(-7_200)
    let store = FakeHealthStoreClient(
      sleepResults: [
        SleepInterval(
          stage: .core,
          start: sleepStart,
          end: sleepStart.addingTimeInterval(3_600),
          sourceBundleIdentifier: "fixture"
        )
      ]
    )
    let service = HealthKitMetricQueryService(store: store)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))

    let reading = try await service.currentReading(
      for: try XCTUnwrap(MetricRegistry[.sleepDuration]),
      now: now,
      calendar: calendar
    )

    XCTAssertEqual(reading?.value, 3_600)
    let request = await store.sleepRequest
    XCTAssertEqual(request?.typeIdentifier, HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
    XCTAssertEqual(request?.interval.duration, 48 * 3_600)
  }

  func testLatestWorkoutUsesTheDedicatedHealthStoreQuery() async throws {
    let now = Date(timeIntervalSince1970: 1_788_035_400)
    let expected = WorkoutSummary(
      activityName: "Running",
      start: now.addingTimeInterval(-1_800),
      end: now,
      durationSeconds: 1_800,
      distanceMetres: 5_000
    )
    let store = FakeHealthStoreClient(workoutResult: expected)
    let service = HealthKitMetricQueryService(store: store)

    let workout = try await service.latestWorkout(now: now)

    XCTAssertEqual(workout, expected)
    let requestCount = await store.workoutRequestCount
    XCTAssertEqual(requestCount, 1)
  }

  func testMindfulIntervalsAreUnionedWithoutOverlap() async throws {
    let now = Date(timeIntervalSince1970: 1_788_035_400)
    let start = now.addingTimeInterval(-3_600)
    let store = FakeHealthStoreClient(
      categoryResults: [
        HealthSample(
          startDate: start,
          endDate: start.addingTimeInterval(1_800),
          value: 1_800,
          unit: .seconds
        ),
        HealthSample(
          startDate: start.addingTimeInterval(900),
          endDate: start.addingTimeInterval(2_700),
          value: 1_800,
          unit: .seconds
        ),
      ]
    )
    let service = HealthKitMetricQueryService(store: store)

    let reading = try await service.currentReading(
      for: try XCTUnwrap(MetricRegistry[.mindfulMinutes]),
      now: now,
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(reading?.value, 2_700)
    let request = await store.categoryRequest
    XCTAssertEqual(request?.typeIdentifier, HKCategoryTypeIdentifier.mindfulSession.rawValue)
  }

  func testQueryErrorsAndCancellationPropagate() async throws {
    let failingStore = FakeHealthStoreClient(error: FakeHealthStoreError.queryFailed)
    let failingService = HealthKitMetricQueryService(store: failingStore)
    do {
      _ = try await failingService.currentReading(
        for: try XCTUnwrap(MetricRegistry[.steps]),
        now: .now,
        calendar: Calendar(identifier: .gregorian)
      )
      XCTFail("Expected query failure")
    } catch {
      XCTAssertEqual(error as? FakeHealthStoreError, .queryFailed)
    }

    let service = HealthKitMetricQueryService(store: FakeHealthStoreClient())
    let definition = try XCTUnwrap(MetricRegistry[.steps])
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await service.currentReading(
        for: definition,
        now: .now,
        calendar: Calendar(identifier: .gregorian)
      )
    }
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    }
  }

  func testProductionQuantityFilterRejectsHomeAssistantOriginMetadata() throws {
    let type = try HealthKitTypeResolver.quantityType(for: .bodyMass)
    let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 70)
    let date = Date(timeIntervalSince1970: 1_788_052_801)
    let external = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
    let imported = HKQuantitySample(
      type: type,
      quantity: quantity,
      start: date,
      end: date,
      metadata: [HealthKitOriginMetadata.key: HealthKitOriginMetadata.homeAssistant]
    )

    XCTAssertTrue(
      HKHealthStoreClient.shouldInclude(
        external,
        applicationBundleIdentifier: "com.marynavdovenko.HAHealthSync"
      )
    )
    XCTAssertFalse(
      HKHealthStoreClient.shouldInclude(
        imported,
        applicationBundleIdentifier: "com.marynavdovenko.HAHealthSync"
      )
    )
  }

  func testBackfillDailySumsUseCalendarDaysAcrossDST() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
    let start = try date(year: 2026, month: 3, day: 28, hour: 0, timeZoneID: "Europe/Zurich")
    let end = try date(year: 2026, month: 3, day: 30, hour: 0, timeZoneID: "Europe/Zurich")
    let samples = [
      HealthSample(timestamp: start.addingTimeInterval(12 * 3_600), value: 1_000, unit: .count),
      HealthSample(timestamp: end.addingTimeInterval(-6 * 3_600), value: 2_000, unit: .count),
    ]
    let store = FakeHealthStoreClient(quantityResults: samples)
    let service = HealthKitMetricQueryService(store: store)

    let points = try await service.points(
      for: try XCTUnwrap(MetricRegistry[.steps]),
      interval: DateInterval(start: start, end: end),
      calendar: calendar
    )

    XCTAssertEqual(points.map(\.value), [1_000, 2_000])
    XCTAssertEqual(
      points.map(\.timestamp),
      [
        start.addingTimeInterval(24 * 3_600),
        end,
      ])
    XCTAssertEqual(end.timeIntervalSince(start), 47 * 3_600)
  }

  func testSleepDetailBackfillMapsStagesAndExcludesThisApplication() async throws {
    let start = Date(timeIntervalSince1970: 1_788_000_000)
    let store = FakeHealthStoreClient(
      sleepResults: [
        SleepInterval(
          stage: .inBed,
          start: start,
          end: start.addingTimeInterval(300),
          sourceBundleIdentifier: "fixture"
        ),
        SleepInterval(
          stage: .deep,
          start: start.addingTimeInterval(300),
          end: start.addingTimeInterval(600),
          sourceBundleIdentifier: "fixture"
        ),
        SleepInterval(
          stage: .awake,
          start: start.addingTimeInterval(600),
          end: start.addingTimeInterval(900),
          sourceBundleIdentifier: "com.marynavdovenko.HAHealthSync",
          isFromThisApplication: true
        ),
      ]
    )
    let service = HealthKitMetricQueryService(store: store)

    let points = try await service.points(
      for: try XCTUnwrap(MetricRegistry[.sleepDetails]),
      interval: DateInterval(start: start, end: start.addingTimeInterval(1_800)),
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(points, [BackfillPoint(timestamp: start.addingTimeInterval(300), value: 0)])
  }

  private func date(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    timeZoneID: String
  ) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneID))
    return try XCTUnwrap(
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    )
  }
}

private enum FakeHealthStoreError: Error, Equatable, Sendable {
  case queryFailed
}

private actor FakeHealthStoreClient: HealthStoreClient {
  struct AuthorizationRequest: Sendable {
    let shareCount: Int
    let readIdentifiers: Set<String>
  }

  struct CumulativeRequest: Sendable {
    let typeIdentifier: String
    let unit: String
    let interval: DateInterval
  }

  let healthDataAvailable: Bool
  let cumulativeResult: HealthKitQuantityResult?
  let latestResults: [String: HealthKitQuantityResult]
  let sleepResults: [SleepInterval]
  let workoutResult: WorkoutSummary?
  let categoryResults: [HealthSample]
  let quantityResults: [HealthSample]
  let error: FakeHealthStoreError?
  private(set) var authorizationRequest: AuthorizationRequest?
  private(set) var cumulativeRequest: CumulativeRequest?
  private(set) var latestRequests: [String: String] = [:]
  private(set) var sleepRequest: CumulativeRequest?
  private(set) var workoutRequestCount = 0
  private(set) var categoryRequest: CumulativeRequest?

  init(
    healthDataAvailable: Bool = true,
    cumulativeResult: HealthKitQuantityResult? = nil,
    latestResults: [String: HealthKitQuantityResult] = [:],
    sleepResults: [SleepInterval] = [],
    workoutResult: WorkoutSummary? = nil,
    categoryResults: [HealthSample] = [],
    quantityResults: [HealthSample] = [],
    error: FakeHealthStoreError? = nil
  ) {
    self.healthDataAvailable = healthDataAvailable
    self.cumulativeResult = cumulativeResult
    self.latestResults = latestResults
    self.sleepResults = sleepResults
    self.workoutResult = workoutResult
    self.categoryResults = categoryResults
    self.quantityResults = quantityResults
    self.error = error
  }

  func isHealthDataAvailable() -> Bool {
    healthDataAvailable
  }

  func requestAuthorization(
    toShare shareTypes: Set<HKSampleType>,
    read readTypes: Set<HKObjectType>
  ) throws {
    if let error {
      throw error
    }
    authorizationRequest = AuthorizationRequest(
      shareCount: shareTypes.count,
      readIdentifiers: Set(readTypes.map(\.identifier))
    )
  }

  func cumulativeSum(
    for type: HKQuantityType,
    unit: HKUnit,
    interval: DateInterval
  ) throws -> HealthKitQuantityResult? {
    try Task.checkCancellation()
    if let error {
      throw error
    }
    cumulativeRequest = CumulativeRequest(
      typeIdentifier: type.identifier,
      unit: unit.unitString,
      interval: interval
    )
    return cumulativeResult
  }

  func latestQuantity(
    for type: HKQuantityType,
    unit: HKUnit
  ) throws -> HealthKitQuantityResult? {
    try Task.checkCancellation()
    if let error {
      throw error
    }
    latestRequests[type.identifier] = unit.unitString
    return latestResults[type.identifier]
  }

  func quantitySamples(
    for type: HKQuantityType,
    unit: HKUnit,
    symbol: UnitSymbol,
    interval: DateInterval
  ) throws -> [HealthSample] {
    try Task.checkCancellation()
    if let error { throw error }
    return quantityResults
  }

  func sleepIntervals(
    for type: HKCategoryType,
    interval: DateInterval
  ) throws -> [SleepInterval] {
    try Task.checkCancellation()
    if let error {
      throw error
    }
    sleepRequest = CumulativeRequest(
      typeIdentifier: type.identifier,
      unit: "",
      interval: interval
    )
    return sleepResults
  }

  func latestWorkout() throws -> WorkoutSummary? {
    try Task.checkCancellation()
    if let error {
      throw error
    }
    workoutRequestCount += 1
    return workoutResult
  }

  func categoryIntervals(
    for type: HKCategoryType,
    interval: DateInterval
  ) throws -> [HealthSample] {
    try Task.checkCancellation()
    if let error {
      throw error
    }
    categoryRequest = CumulativeRequest(
      typeIdentifier: type.identifier,
      unit: "",
      interval: interval
    )
    return categoryResults
  }
}
