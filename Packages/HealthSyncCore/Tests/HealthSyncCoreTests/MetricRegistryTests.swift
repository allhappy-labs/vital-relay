import Testing

@testable import HealthSyncCore

@Suite("Metric registry")
struct MetricRegistryTests {
  @Test("Initial registry matches the Health Bridge contract")
  func initialRegistryMatchesHealthBridgeContract() throws {
    #expect(Set(MetricRegistry.all.map(\.id)) == Set(MetricID.allCases))
    #expect(MetricRegistry.all.count == MetricID.allCases.count)

    let steps = try #require(MetricRegistry[.steps])
    #expect(steps.id.rawValue == "steps")
    #expect(steps.healthObjectType == .stepCount)
    #expect(steps.bridgeUnit == .count)
    #expect(steps.aggregation == .dailyCumulativeSum)
    #expect(steps.validation == 0...250_000)

    let bodyMass = try #require(MetricRegistry[.bodyMass])
    #expect(bodyMass.id.rawValue == "body_mass")
    #expect(bodyMass.healthObjectType == .bodyMass)
    #expect(bodyMass.bridgeUnit == .kilograms)
    #expect(bodyMass.aggregation == .latestSample)
    #expect(bodyMass.validation == 1...700)

    let restingHeartRate = try #require(MetricRegistry[.restingHeartRate])
    #expect(restingHeartRate.id.rawValue == "resting_heart_rate")
    #expect(restingHeartRate.healthObjectType == .restingHeartRate)
    #expect(restingHeartRate.bridgeUnit == .beatsPerMinute)
    #expect(restingHeartRate.aggregation == .latestSample)
    #expect(restingHeartRate.validation == 20...300)
  }

  @Test("Every definition declares synchronization policy")
  func definitionsDeclareSynchronizationPolicy() {
    for definition in MetricRegistry.selectable {
      #expect(definition.minimumIOSMajorVersion == 18)
      #expect(definition.supportsBackgroundDelivery)
      #expect(!definition.displayName.isEmpty)
      #expect(definition.validation.lowerBound <= definition.validation.upperBound)
    }
  }

  @Test("HealthKit identifiers use Apple's stable identifier strings")
  func healthKitIdentifiersAreStable() {
    #expect(HealthObjectTypeID.stepCount.rawValue == "HKQuantityTypeIdentifierStepCount")
    #expect(HealthObjectTypeID.bodyMass.rawValue == "HKQuantityTypeIdentifierBodyMass")
    #expect(
      HealthObjectTypeID.restingHeartRate.rawValue
        == "HKQuantityTypeIdentifierRestingHeartRate"
    )
    #expect(
      HealthObjectTypeID.sleepAnalysis.rawValue
        == "HKCategoryTypeIdentifierSleepAnalysis"
    )
  }
}
