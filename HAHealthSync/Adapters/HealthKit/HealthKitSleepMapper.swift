import HealthKit
import HealthSyncCore

enum HealthKitSleepMapper {
  static func stage(for value: HKCategoryValueSleepAnalysis) -> SleepStage? {
    switch value {
    case .inBed: .inBed
    case .asleepUnspecified: .asleepUnspecified
    case .awake: .awake
    case .asleepCore: .core
    case .asleepDeep: .deep
    case .asleepREM: .rem
    @unknown default: nil
    }
  }
}
