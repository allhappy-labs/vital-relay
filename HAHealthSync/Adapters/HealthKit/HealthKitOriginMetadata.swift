import Foundation
import HealthKit

enum HealthKitOriginMetadata {
  static let key = "com.olhapi.HAHealthSync.origin"
  static let homeAssistant = "home-assistant"

  static func excludes(_ sample: HKSample, applicationBundleID: String) -> Bool {
    sample.sourceRevision.source.bundleIdentifier == applicationBundleID
      || sample.metadata?[key] as? String == homeAssistant
  }

  static var outboundPredicate: NSPredicate {
    NSCompoundPredicate(andPredicateWithSubpredicates: [
      NSCompoundPredicate(
        notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default())),
      NSCompoundPredicate(
        notPredicateWithSubpredicate: HKQuery.predicateForObjects(
          withMetadataKey: key, allowedValues: [homeAssistant])),
    ])
  }
}
