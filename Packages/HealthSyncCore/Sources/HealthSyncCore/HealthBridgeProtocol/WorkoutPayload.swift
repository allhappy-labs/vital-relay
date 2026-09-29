public struct WorkoutPayload: Sendable, Equatable {
  public let fields: [String: JSONValue]

  public init(fields: [String: JSONValue]) {
    self.fields = fields
  }

  public var liveValue: JSONValue {
    .array([.object(fields)])
  }
}
