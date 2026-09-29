import Foundation

public struct RequestIDGenerator: Sendable {
  private let uuidProvider: @Sendable () -> UUID

  public init(uuidProvider: @escaping @Sendable () -> UUID = { UUID() }) {
    self.uuidProvider = uuidProvider
  }

  public func live() -> String {
    makeID(prefix: "live")
  }

  public func connectionTest() -> String {
    makeID(prefix: "test")
  }

  public func backfill() -> String {
    makeID(prefix: "backfill")
  }

  public static func isValid(_ requestID: String) -> Bool {
    requestID.range(
      of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",
      options: .regularExpression
    ) != nil
  }

  private func makeID(prefix: String) -> String {
    "\(prefix).\(uuidProvider().uuidString.lowercased())"
  }
}
