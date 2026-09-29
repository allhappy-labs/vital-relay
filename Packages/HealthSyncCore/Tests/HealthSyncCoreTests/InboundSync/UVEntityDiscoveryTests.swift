import Foundation
import Testing

@testable import HealthSyncCore

@Suite("UV entity discovery")
struct UVEntityDiscoveryTests {
  @Test("Ranks current numeric UV index sensors and excludes Health Bridge output")
  func ranksCurrentUVIndexSensors() {
    let states = [
      makeState(
        entityID: "sensor.patio_uv_index",
        value: "3.1",
        friendlyName: "Patio UV Index"
      ),
      makeState(
        entityID: "sensor.47_3769_8_5417_current_uv_index",
        value: "4.2",
        friendlyName: "Current UV Index"
      ),
      makeState(
        entityID: "sensor.uv_index_fixture_user",
        value: "4.2",
        friendlyName: "UV Index (fixture-user)"
      ),
      makeState(
        entityID: "sensor.garden_current_uv_index",
        value: "unavailable",
        friendlyName: "Garden Current UV Index"
      ),
      makeState(
        entityID: "weather.home",
        value: "4.2",
        friendlyName: "Home UV Index"
      ),
    ]

    let candidates = UVEntityDiscovery.candidates(
      from: states,
      excludingHealthBridgeUserID: "fixture-user"
    )

    #expect(
      candidates.map(\.entityID) == [
        "sensor.47_3769_8_5417_current_uv_index",
        "sensor.patio_uv_index",
      ])
    #expect(candidates.first?.displayName == "Current UV Index")
  }

  @Test("Uses friendly names while rejecting max and forecast UV values")
  func usesFriendlyNamesAndRejectsNonCurrentValues() {
    let states = [
      makeState(entityID: "sensor.outdoor", value: "2", friendlyName: "Outdoor UV Index"),
      makeState(entityID: "sensor.max_uv_index", value: "7", friendlyName: "Max UV Index"),
      makeState(
        entityID: "sensor.uv_forecast",
        value: "5",
        friendlyName: "UV Index Forecast"
      ),
    ]

    let candidates = UVEntityDiscovery.candidates(from: states)

    #expect(candidates.map(\.entityID) == ["sensor.outdoor"])
  }

  private func makeState(
    entityID: String,
    value: String,
    friendlyName: String?
  ) -> HomeAssistantState {
    let date = Date(timeIntervalSince1970: 1_788_052_800)
    return HomeAssistantState(
      entityID: entityID,
      state: value,
      lastChanged: date,
      lastUpdated: date,
      attributes: .init(unitOfMeasurement: nil, friendlyName: friendlyName)
    )
  }
}
