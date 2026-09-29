import Foundation

public struct AppConfiguration: Codable, Sendable, Equatable {
  public var baseURL: String
  public var allowsConfirmedLocalHTTP: Bool
  public var healthBridgeUserID: String
  public var selectedMetrics: Set<MetricID>
  public var backgroundSyncEnabled: Bool
  public var backgroundSyncFrequency: BackgroundSyncFrequency
  public var experimentalBackfillEnabled: Bool
  public var medicationSyncEnabled: Bool
  public var publishSyncAttempts: Bool

  public init(
    baseURL: String,
    allowsConfirmedLocalHTTP: Bool,
    healthBridgeUserID: String,
    selectedMetrics: Set<MetricID>,
    backgroundSyncEnabled: Bool,
    backgroundSyncFrequency: BackgroundSyncFrequency = .balanced,
    experimentalBackfillEnabled: Bool = false,
    medicationSyncEnabled: Bool = false,
    publishSyncAttempts: Bool = false
  ) {
    self.baseURL = baseURL
    self.allowsConfirmedLocalHTTP = allowsConfirmedLocalHTTP
    self.healthBridgeUserID = healthBridgeUserID
    self.selectedMetrics = selectedMetrics
    self.backgroundSyncEnabled = backgroundSyncEnabled
    self.backgroundSyncFrequency = backgroundSyncFrequency
    self.experimentalBackfillEnabled = experimentalBackfillEnabled
    self.medicationSyncEnabled = medicationSyncEnabled
    self.publishSyncAttempts = publishSyncAttempts
  }

  public static let `default` = AppConfiguration(
    baseURL: "",
    allowsConfirmedLocalHTTP: false,
    healthBridgeUserID: "",
    selectedMetrics: [],
    backgroundSyncEnabled: false,
    experimentalBackfillEnabled: false,
    medicationSyncEnabled: false
  )

  private enum CodingKeys: String, CodingKey {
    case baseURL
    case allowsConfirmedLocalHTTP
    case healthBridgeUserID
    case selectedMetrics
    case backgroundSyncEnabled
    case backgroundSyncFrequency
    case experimentalBackfillEnabled
    case medicationSyncEnabled
    case publishSyncAttempts
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    baseURL = try container.decode(String.self, forKey: .baseURL)
    allowsConfirmedLocalHTTP = try container.decode(Bool.self, forKey: .allowsConfirmedLocalHTTP)
    healthBridgeUserID = try container.decode(String.self, forKey: .healthBridgeUserID)
    selectedMetrics = try container.decode(Set<MetricID>.self, forKey: .selectedMetrics)
    backgroundSyncEnabled = try container.decode(Bool.self, forKey: .backgroundSyncEnabled)
    backgroundSyncFrequency =
      try container.decodeIfPresent(
        BackgroundSyncFrequency.self,
        forKey: .backgroundSyncFrequency
      ) ?? .balanced
    experimentalBackfillEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .experimentalBackfillEnabled) ?? false
    medicationSyncEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .medicationSyncEnabled) ?? false
    publishSyncAttempts =
      try container.decodeIfPresent(Bool.self, forKey: .publishSyncAttempts) ?? false
  }

  public func validate() throws {
    let pattern = "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
    guard healthBridgeUserID.range(of: pattern, options: .regularExpression) != nil else {
      throw ConfigurationStoreError.invalidUserID
    }
  }
}
