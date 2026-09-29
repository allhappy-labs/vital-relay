import Foundation

public enum SampleOrdering: Sendable {
  public static func isPreferred(_ lhs: HealthSample, over rhs: HealthSample) -> Bool {
    if lhs.timestamp != rhs.timestamp {
      return lhs.timestamp > rhs.timestamp
    }
    if lhs.isUserEntered != rhs.isUserEntered {
      return !lhs.isUserEntered
    }
    if lhs.sourceBundleIdentifier != rhs.sourceBundleIdentifier {
      return lhs.sourceBundleIdentifier < rhs.sourceBundleIdentifier
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  public static func preferred(_ samples: [HealthSample]) -> HealthSample? {
    samples.sorted { isPreferred($0, over: $1) }.first
  }
}
