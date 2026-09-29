import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sync status recording")
struct SyncStatusRecordingTests {
  private let start = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("A cancelled task still records its report and clears the in-flight marker")
  func cancelledRecord() async throws {
    let store = InMemorySyncStatusStore()
    try await store.recordAttempt(trigger: .appRefresh, at: start)
    #expect(await store.snapshot().inFlightAttempt?.trigger == .appRefresh)

    let report = report(trigger: .appRefresh, failure: .cancelled)
    let task = Task {
      try? await Task.sleep(for: .seconds(10))
      try await store.record(report: report)
    }
    task.cancel()
    try await task.value

    let snapshot = await store.snapshot()
    #expect(snapshot.recentEvents.count == 1)
    #expect(snapshot.recentEvents[0].failureCategories == [.cancelled])
    #expect(snapshot.lastFailure?.category == .cancelled)
    #expect(snapshot.inFlightAttempt == nil)
  }

  @Test("A marker from another launch becomes one interrupted event")
  func interruptedFromPreviousLaunch() async throws {
    let previousLaunch = UUID()
    let store = InMemorySyncStatusStore(
      snapshot: SyncStatusSnapshot(
        lastAttemptedAt: start,
        inFlightAttempt: SyncInFlightAttempt(
          trigger: .healthKitObserver,
          startedAt: start,
          launchID: previousLaunch
        ),
        pendingThrottledWakes: 2
      )
    )

    let event = try #require(try await store.recordInterruptedAttemptIfNeeded())

    #expect(event.outcome == .interrupted)
    #expect(event.trigger == .healthKitObserver)
    #expect(event.startedAt == start)
    #expect(event.finishedAt == start)
    #expect(event.throttledWakesBefore == 2)
    let snapshot = await store.snapshot()
    #expect(snapshot.inFlightAttempt == nil)
    #expect(snapshot.pendingThrottledWakes == 0)
    #expect(snapshot.recentEvents == [event])
    #expect(snapshot.lastFailure?.category == .cancelled)
    #expect(snapshot.lastFailure?.at == start)
    #expect(try await store.recordInterruptedAttemptIfNeeded() == nil)
  }

  @Test("A marker from the current launch is never interrupted")
  func currentLaunchIsActive() async throws {
    let store = InMemorySyncStatusStore()
    try await store.recordAttempt(trigger: .manual, at: start)

    #expect(try await store.recordInterruptedAttemptIfNeeded() == nil)
    #expect(await store.snapshot().inFlightAttempt?.launchID == SyncProcessLaunch.id)
  }

  @Test("Throttled wakes accumulate into the next recorded event")
  func throttledWakes() async throws {
    let store = InMemorySyncStatusStore()
    try await store.recordThrottledWake()
    try await store.recordThrottledWake()
    try await store.record(report: report(trigger: .appRefresh, failure: nil))
    try await store.record(report: report(trigger: .appRefresh, failure: nil))

    let events = await store.snapshot().recentEvents
    #expect(events.map(\.throttledWakesBefore) == [2, 0])
    #expect(await store.snapshot().pendingThrottledWakes == 0)
  }

  @Test("Events carry start, request count and context")
  func eventFields() {
    let context = SyncRunContext(
      backgroundRefresh: .available,
      lowPowerMode: true,
      protectedDataAvailable: false
    )
    let outbound = SyncReport(
      trigger: .appRefresh, attemptedMetrics: 3, synchronizedMetrics: 3, skippedMetrics: 0,
      failures: [], startedAt: start, finishedAt: start.addingTimeInterval(4), requestCount: 2
    )
    let event = SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: .appRefresh, outbound: outbound, inbound: nil,
        startedAt: start, finishedAt: start.addingTimeInterval(5), context: context
      )
    )

    #expect(event.startedAt == start)
    #expect(event.duration == 5)
    #expect(event.requestCount == 2)
    #expect(event.context == context)
    #expect(event.outcome == .completed)
  }

  @Test("Version-1 documents without the new fields still decode")
  func legacyDecoding() throws {
    var snapshot = SyncStatusSnapshot(
      lastAttemptedAt: start,
      inFlightAttempt: SyncInFlightAttempt(trigger: .manual, startedAt: start, launchID: UUID()),
      pendingThrottledWakes: 3
    )
    snapshot.apply(report(trigger: .background, failure: nil))
    let encoded = try SyncStatusCodec.encode(snapshot)
    var document = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var body = try #require(document["snapshot"] as? [String: Any])
    body.removeValue(forKey: "inFlightAttempt")
    body.removeValue(forKey: "pendingThrottledWakes")
    var events = try #require(body["recentEvents"] as? [[String: Any]])
    for key in ["startedAt", "outcome", "requestCount", "throttledWakesBefore", "context"] {
      events[0].removeValue(forKey: key)
    }
    body["recentEvents"] = events
    document["snapshot"] = body
    let legacy = try JSONSerialization.data(withJSONObject: document)

    let decoded = try SyncStatusCodec.decode(legacy)

    #expect(decoded.inFlightAttempt == nil)
    #expect(decoded.pendingThrottledWakes == 0)
    #expect(decoded.recentEvents[0].trigger == .background)
    #expect(decoded.recentEvents[0].outcome == .completed)
    #expect(decoded.recentEvents[0].startedAt == nil)
    #expect(decoded.recentEvents[0].throttledWakesBefore == 0)
  }

  private func report(trigger: SyncTrigger, failure: SyncFailureCategory?)
    -> BidirectionalSyncReport
  {
    BidirectionalSyncReport(
      trigger: trigger,
      outbound: SyncReport(
        trigger: trigger,
        attemptedMetrics: 1,
        synchronizedMetrics: failure == nil ? 1 : 0,
        skippedMetrics: 0,
        failures: failure.map { [.init(metricID: nil, category: $0)] } ?? [],
        startedAt: start,
        finishedAt: start
      ),
      inbound: nil,
      setupFailureCategory: nil,
      startedAt: start,
      finishedAt: start
    )
  }
}
