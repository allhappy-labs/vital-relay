import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sync attempt publisher")
struct SyncAttemptPublisherTests {
  private let now = Date(timeIntervalSince1970: 1_788_035_400)

  @Test("Entity IDs are slugged from the Health Bridge user")
  func entityID() {
    #expect(
      SyncAttemptPublisher.entityID(userID: "Oleh-Phone_1")
        == "sensor.health_bridge_sync_attempt_oleh_phone_1"
    )
  }

  @Test("Outcome labels follow export, lock, failure and interruption")
  func outcomes() {
    #expect(SyncAttemptPublisher.outcome(for: event(synchronized: 2)) == "exported")
    #expect(SyncAttemptPublisher.outcome(for: event(failures: [.deviceLocked])) == "locked")
    #expect(SyncAttemptPublisher.outcome(for: event(failures: [.offline])) == "failed")
    #expect(SyncAttemptPublisher.outcome(for: event()) == "no_changes")
    let interrupted = SyncStatusEvent(
      interrupted: SyncInFlightAttempt(trigger: .appRefresh, startedAt: now, launchID: nil)
    )
    #expect(SyncAttemptPublisher.outcome(for: interrupted) == "interrupted")
  }

  @Test("Attributes are value free")
  func attributes() {
    let attributes = SyncAttemptPublisher.attributes(
      for: event(synchronized: 2, failures: [.offline]),
      userID: "oleh"
    )
    #expect(attributes["device_class"] == .string("timestamp"))
    #expect(attributes["friendly_name"] == .string("Health Bridge sync attempt (oleh)"))
    #expect(attributes["trigger"] == .string("appRefresh"))
    #expect(attributes["outcome"] == .string("exported"))
    #expect(attributes["exported_metrics"] == .number(2))
    #expect(attributes["imported_pairings"] == .number(0))
    #expect(attributes["failure_category"] == .string("offline"))
    #expect(attributes["duration_s"] == .number(4))
    #expect(attributes["throttled_wakes_before"] == .number(0))
  }

  @Test("Nothing is published while the setting is off")
  func disabled() async throws {
    let client = RecordingStatePublisher()
    let publisher = try await makePublisher(enabled: false, client: client)

    let failure = await publisher.publish(event(synchronized: 1), deadline: nil)

    #expect(failure == nil)
    #expect(await client.calls.isEmpty)
  }

  @Test("Publish failures are returned as a failure category")
  func failureCategory() async throws {
    let client = RecordingStatePublisher(error: .forbidden)
    let publisher = try await makePublisher(enabled: true, client: client)

    let failure = await publisher.publish(event(synchronized: 1), deadline: nil)

    #expect(failure == .forbidden)
    #expect(await client.calls.count == 1)
  }

  @Test("Enabled publishing uses the run start and a bounded timeout")
  func enabled() async throws {
    let client = RecordingStatePublisher()
    let publisher = try await makePublisher(enabled: true, client: client)

    let failure = await publisher.publish(
      event(synchronized: 1),
      deadline: ExecutionDeadline(expiresAt: now.addingTimeInterval(3))
    )

    #expect(failure == nil)

    let call = try #require(await client.calls.first)
    #expect(call.entityID == "sensor.health_bridge_sync_attempt_oleh")
    #expect(call.state == ISO8601DateFormatter().string(from: now.addingTimeInterval(-4)))
    #expect(call.timeout == 3)
  }

  @Test("The enable-time test publishes even before the setting is saved")
  func testPublish() async throws {
    let client = RecordingStatePublisher()
    let publisher = try await makePublisher(enabled: false, client: client)

    try await publisher.publishTest()

    let call = try #require(await client.calls.first)
    #expect(call.attributes["outcome"] == .string("test"))
    #expect(call.timeout == 5)
  }

  @Test("Existing configuration documents default publishing off")
  func configurationDefault() throws {
    let data = Data(
      #"{"baseURL":"https://ha.example.com","allowsConfirmedLocalHTTP":false,"healthBridgeUserID":"oleh","selectedMetrics":[],"backgroundSyncEnabled":true}"#
        .utf8
    )
    #expect(
      try JSONDecoder().decode(AppConfiguration.self, from: data).publishSyncAttempts == false)
  }

  private func event(synchronized: Int = 0, failures: [SyncFailureCategory] = []) -> SyncStatusEvent
  {
    SyncStatusEvent(
      report: BidirectionalSyncReport(
        trigger: .appRefresh,
        outbound: SyncReport(
          trigger: .appRefresh,
          attemptedMetrics: synchronized + failures.count,
          synchronizedMetrics: synchronized,
          skippedMetrics: 0,
          failures: failures.map { .init(metricID: nil, category: $0) },
          startedAt: now.addingTimeInterval(-4),
          finishedAt: now
        ),
        inbound: nil,
        startedAt: now.addingTimeInterval(-4),
        finishedAt: now
      )
    )
  }

  private func makePublisher(
    enabled: Bool,
    client: RecordingStatePublisher
  ) async throws -> SyncAttemptPublisher {
    let credentials = InMemoryCredentialStore()
    try await credentials.write("fixture-access-token", for: .accessToken)
    let fixedNow = now
    return SyncAttemptPublisher(
      configurationStore: InMemoryConfigurationStore(
        configuration: AppConfiguration(
          baseURL: "https://ha.example.com",
          allowsConfirmedLocalHTTP: false,
          healthBridgeUserID: "oleh",
          selectedMetrics: [.steps],
          backgroundSyncEnabled: true,
          publishSyncAttempts: enabled
        )
      ),
      credentialStore: credentials,
      client: client,
      now: { fixedNow }
    )
  }
}

actor RecordingStatePublisher: HomeAssistantStatePublishing {
  struct Call: Sendable {
    let entityID: String
    let state: String
    let attributes: [String: JSONValue]
    let timeout: TimeInterval
  }

  private(set) var calls: [Call] = []
  private let error: NetworkFailure?

  init(error: NetworkFailure? = nil) {
    self.error = error
  }

  func publishState(
    entityID: String,
    state: String,
    attributes: [String: JSONValue],
    baseURL: NormalizedBaseURL,
    accessToken: String,
    timeout: TimeInterval
  ) throws {
    calls.append(Call(entityID: entityID, state: state, attributes: attributes, timeout: timeout))
    if let error { throw error }
  }
}
