import Foundation
import Testing

@testable import HealthSyncCore

/// Every metric window is anchored to the local day, so the refresh gate is "was this metric
/// touched by a run today?". These cover the gate end to end through `SyncCoordinator`.
@Suite("Daily window refresh")
struct WindowRefreshTests {
  private static let oldAnchor = Data([1])
  private static let candidateAnchor = Data([2])
  private static let unchanged = MetricChanges(
    addedSampleIDs: [],
    deletedSampleIDs: [],
    candidateAnchor: candidateAnchor
  )
  private static let added = MetricChanges(
    addedSampleIDs: [UUID()],
    deletedSampleIDs: [],
    candidateAnchor: candidateAnchor
  )

  @Test("An unchanged metric not touched today is resent without advancing its anchor")
  func metricIsResentAfterMidnight() async throws {
    let fixture = try await makeFixture(now: date("2026-09-19T00:30:00+02:00"))

    let outcome = await fixture.sync(lastWindowTouchAt: [.steps: date("2026-09-18T23:50:00+02:00")])

    #expect(outcome.report.synchronizedMetrics == 1)
    #expect(outcome.report.skippedMetrics == 0)
    #expect(outcome.report.failures.isEmpty)
    #expect(outcome.sentRequests == 1)
    #expect(outcome.anchor == Self.oldAnchor)
    #expect(outcome.commits.isEmpty)
  }

  @Test("An unchanged metric already touched today is skipped")
  func metricIsNotResentTwiceInADay() async throws {
    let fixture = try await makeFixture(now: date("2026-09-19T12:00:00+02:00"))

    let outcome = await fixture.sync(lastWindowTouchAt: [.steps: date("2026-09-19T00:10:00+02:00")])

    #expect(outcome.report.synchronizedMetrics == 0)
    #expect(outcome.report.skippedMetrics == 1)
    #expect(outcome.report.failures.isEmpty)
    #expect(outcome.sentRequests == 0)
    #expect(outcome.anchor == Self.oldAnchor)
  }

  @Test("A touch exactly at local midnight belongs to today and suppresses the refresh")
  func touchAtLocalMidnightCountsAsToday() async throws {
    let fixture = try await makeFixture(now: date("2026-09-19T12:00:00+02:00"))

    let outcome = await fixture.sync(lastWindowTouchAt: [.steps: date("2026-09-19T00:00:00+02:00")])

    #expect(outcome.report.skippedMetrics == 1)
    #expect(outcome.sentRequests == 0)
  }

  @Test("A metric that has never been touched is refreshed")
  func neverTouchedMetricIsRefreshed() async throws {
    let fixture = try await makeFixture(now: date("2026-09-19T00:30:00+02:00"))

    let outcome = await fixture.sync(lastWindowTouchAt: [:])

    #expect(outcome.report.synchronizedMetrics == 1)
    #expect(outcome.sentRequests == 1)
    #expect(outcome.anchor == Self.oldAnchor)
  }

  @Test("A trailing-window metric refreshes daily, not once per window")
  func trailingWindowMetricRefreshesDaily() async throws {
    // `.asleepTime` covers `.trailingDays(2)`; its value still changes every local day.
    let fixture = try await makeFixture(metric: .asleepTime, now: date("2026-09-19T10:00:00+02:00"))

    let outcome = await fixture.sync(
      lastWindowTouchAt: [.asleepTime: date("2026-09-18T22:00:00+02:00")]
    )

    #expect(outcome.report.synchronizedMetrics == 1)
    #expect(outcome.report.skippedMetrics == 0)
    #expect(outcome.sentRequests == 1)
    #expect(outcome.anchor == Self.oldAnchor)
  }

  @Test(
    "The day boundary follows the calendar across a daylight-saving shift",
    arguments: [("2026-03-29T23:30:00+02:00", true), ("2026-03-30T00:30:00+02:00", false)]
  )
  func daylightSavingShiftUsesCalendarDays(argument: (String, Bool)) async throws {
    // The day before was 23 hours long in Zurich, so a fixed 24-hour rule would call the late
    // touch on 03-29 "recent" and never refresh; the calendar day says it was yesterday.
    let now = date("2026-03-30T12:00:00+02:00")
    let touchedAt = date(argument.0)
    #expect(touchedAt > now.addingTimeInterval(-86_400))
    let fixture = try await makeFixture(now: now)

    let outcome = await fixture.sync(lastWindowTouchAt: [.steps: touchedAt])

    #expect(outcome.report.synchronizedMetrics == (argument.1 ? 1 : 0))
    #expect(outcome.report.skippedMetrics == (argument.1 ? 0 : 1))
    #expect(outcome.sentRequests == (argument.1 ? 1 : 0))
  }

  @Test("A refresh that finds no value is not retried for the rest of the day")
  func refreshWithoutAValueIsNotRepeated() async throws {
    // Body weight with no sample today: the refresh queries HealthKit, finds nothing and skips.
    let fixture = try await makeFixture(metric: .bodyMass, now: date("2026-09-19T12:00:00+02:00"))
    await fixture.query.configureReading(nil, for: .bodyMass)

    let first = await fixture.sync(lastWindowTouchAt: [:])
    let second = await fixture.sync(
      lastWindowTouchAt: [.bodyMass: date("2026-09-19T12:00:00+02:00")]
    )

    #expect(first.report.skippedMetrics == 1)
    #expect(first.readingQueries == 1)
    // The refresh resolved the metric — there was genuinely nothing to send — so it records a
    // check, which is what the day gate reads as today's touch.
    #expect(first.report.resolvedMetricIDs == [.bodyMass])
    #expect(second.report.skippedMetrics == 1)
    #expect(second.readingQueries == 1, "The second run must not query the value again")
    #expect(second.sentRequests == 0)
    #expect(second.anchor == Self.oldAnchor)
  }

  @Test("A metric with changes still commits its candidate anchor")
  func changedMetricCommitsItsAnchor() async throws {
    let fixture = try await makeFixture(
      now: date("2026-09-19T12:00:00+02:00"),
      changes: Self.added
    )

    let outcome = await fixture.sync(lastWindowTouchAt: [.steps: date("2026-09-19T00:10:00+02:00")])

    #expect(outcome.report.synchronizedMetrics == 1)
    #expect(outcome.sentRequests == 1)
    #expect(outcome.anchor == Self.candidateAnchor)
    #expect(outcome.commits == [.steps])
  }

  private struct Outcome {
    let report: SyncReport
    let sentRequests: Int
    let readingQueries: Int
    let anchor: Data?
    let commits: [MetricID]
  }

  private struct Fixture {
    let coordinator: SyncCoordinator
    let query: FakeMetricQueryService
    let store: TransactionCheckpointStore
    let sender: TransactionSender
    let metric: MetricID

    func sync(lastWindowTouchAt: [MetricID: Date]) async -> Outcome {
      let report = await coordinator.sync(
        trigger: .healthKitObserver,
        metrics: [metric],
        deadline: nil,
        includesMedications: false,
        lastWindowTouchAt: lastWindowTouchAt
      )
      return Outcome(
        report: report,
        sentRequests: await sender.requestIDs.count,
        readingQueries: await query.readingRequests.count,
        anchor: await store.anchor(for: metric),
        commits: await store.commits
      )
    }
  }

  private func makeFixture(
    metric: MetricID = .steps,
    now: Date,
    changes: MetricChanges = WindowRefreshTests.unchanged
  ) async throws -> Fixture {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let query = FakeMetricQueryService()
    await query.configureReading(
      MetricReading(metricID: metric, timestamp: now, value: 8_421),
      for: metric
    )
    let store = TransactionCheckpointStore(anchors: [metric: Self.oldAnchor])
    let sender = TransactionSender(outcomes: [])
    let configuration = AppConfiguration(
      baseURL: "https://ha.example.com",
      allowsConfirmedLocalHTTP: false,
      healthBridgeUserID: "example-user",
      selectedMetrics: [metric],
      backgroundSyncEnabled: true
    )
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-secret", for: .webhookSecret)
    let coordinator = SyncCoordinator(
      configurationStore: InMemoryConfigurationStore(configuration: configuration),
      credentialStore: credentials,
      metricQuery: query,
      webhookSender: sender,
      calendar: calendar,
      now: { now },
      checkpointStore: store,
      changeQuery: TransactionChangeQuery(changes: changes),
      sleeper: RecordingSleeper(),
      jitterSource: FixedJitterSource()
    )
    return Fixture(
      coordinator: coordinator, query: query, store: store, sender: sender,
      metric: metric)
  }
}

/// Parses an ISO-8601 instant with an explicit offset, so every day boundary is deterministic.
private func date(_ iso: String) -> Date {
  ISO8601DateFormatter().date(from: iso)!
}
