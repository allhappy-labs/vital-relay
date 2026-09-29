import Foundation

public protocol SyncRunContextProviding: Sendable {
  func currentContext() async -> SyncRunContext?
}
