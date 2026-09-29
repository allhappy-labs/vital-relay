import Foundation

public struct UVEntityCandidate: Sendable, Equatable, Identifiable {
  public let entityID: String
  public let displayName: String

  public var id: String { entityID }

  public init(entityID: String, displayName: String) {
    self.entityID = entityID
    self.displayName = displayName
  }
}

public enum UVEntityDiscovery: Sendable {
  public static func candidates(
    from states: [HomeAssistantState],
    excludingHealthBridgeUserID healthBridgeUserID: String? = nil
  ) -> [UVEntityCandidate] {
    states.compactMap { state -> RankedCandidate? in
      guard state.entityID.hasPrefix("sensor."),
        let value = Double(state.state.trimmingCharacters(in: .whitespacesAndNewlines)),
        value.isFinite,
        (0...50).contains(value)
      else {
        return nil
      }

      let friendlyName = state.attributes.friendlyName?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let searchText = normalizedSearchText(
        [state.entityID, friendlyName].compactMap { $0 }.joined(separator: " ")
      )
      let tokens = searchText.split(separator: " ").map(String.init)
      guard describesUVIndex(tokens) else { return nil }
      guard !tokens.contains("max"), !tokens.contains("maximum"),
        !tokens.contains("forecast")
      else {
        return nil
      }
      guard
        !isHealthBridgeOutput(
          state,
          friendlyName: friendlyName,
          healthBridgeUserID: healthBridgeUserID
        )
      else {
        return nil
      }

      let displayName = friendlyName.flatMap { $0.isEmpty ? nil : $0 } ?? state.entityID
      let candidate = UVEntityCandidate(entityID: state.entityID, displayName: displayName)
      return RankedCandidate(candidate: candidate, rank: tokens.contains("current") ? 0 : 1)
    }
    .sorted {
      if $0.rank != $1.rank { return $0.rank < $1.rank }
      return $0.candidate.displayName.localizedCaseInsensitiveCompare(
        $1.candidate.displayName
      ) == .orderedAscending
    }
    .map(\.candidate)
  }

  private static func describesUVIndex(_ tokens: [String]) -> Bool {
    tokens.contains("uvi")
      || zip(tokens, tokens.dropFirst()).contains { $0 == "uv" && $1 == "index" }
  }

  private static func normalizedSearchText(_ value: String) -> String {
    value.lowercased().unicodeScalars.map { scalar in
      CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
    }.reduce(into: "") { $0.append($1) }
  }

  private static func isHealthBridgeOutput(
    _ state: HomeAssistantState,
    friendlyName: String?,
    healthBridgeUserID: String?
  ) -> Bool {
    let entityID = state.entityID.lowercased()
    if entityID == "sensor.uv_index" || entityID.contains("health_bridge") {
      return true
    }
    guard
      let healthBridgeUserID = healthBridgeUserID?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ), !healthBridgeUserID.isEmpty
    else {
      return false
    }
    let normalizedUserID = normalizedSearchText(healthBridgeUserID)
      .split(separator: " ").joined(separator: "_")
    let normalizedFriendlyName = friendlyName?.lowercased() ?? ""
    return entityID.hasSuffix("_\(normalizedUserID)")
      || normalizedFriendlyName.contains("(\(healthBridgeUserID.lowercased()))")
  }

  private struct RankedCandidate {
    let candidate: UVEntityCandidate
    let rank: Int
  }
}
