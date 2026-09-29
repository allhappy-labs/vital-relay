import HealthKit

enum HealthKitWorkoutMapper {
  static func activityName(for type: HKWorkoutActivityType) -> String {
    switch type {
    case .running: "Running"
    case .walking: "Walking"
    case .cycling: "Cycling"
    case .swimming: "Swimming"
    case .hiking: "Hiking"
    case .traditionalStrengthTraining: "Traditional Strength Training"
    case .functionalStrengthTraining: "Functional Strength Training"
    case .highIntensityIntervalTraining: "High Intensity Interval Training"
    case .mixedCardio: "Mixed Cardio"
    case .yoga: "Yoga"
    case .pilates: "Pilates"
    case .rowing: "Rowing"
    case .elliptical: "Elliptical"
    case .stairClimbing: "Stair Climbing"
    case .dance: "Dance"
    case .crossTraining: "Cross Training"
    case .coreTraining: "Core Training"
    case .soccer: "Soccer"
    case .tennis: "Tennis"
    case .other: "Other"
    default: "Other"
    }
  }
}
