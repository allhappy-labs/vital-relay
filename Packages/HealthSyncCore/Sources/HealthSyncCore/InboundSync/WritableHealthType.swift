public struct WritableHealthType: Codable, Sendable, Equatable, Identifiable {
  public let id: HealthObjectTypeID
  public let displayName: String
  public let category: MetricCategory
  public let nativeUnit: UnitSymbol
  public let plausibleBounds: ClosedRange<Double>
  public let minimumIOSMajorVersion: Int

  public init(
    id: HealthObjectTypeID,
    displayName: String,
    category: MetricCategory,
    nativeUnit: UnitSymbol,
    plausibleBounds: ClosedRange<Double>,
    minimumIOSMajorVersion: Int
  ) {
    self.id = id
    self.displayName = displayName
    self.category = category
    self.nativeUnit = nativeUnit
    self.plausibleBounds = plausibleBounds
    self.minimumIOSMajorVersion = minimumIOSMajorVersion
  }
}
