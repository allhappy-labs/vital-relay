import Foundation
import HealthSyncCore
import Observation
import UIKit

@MainActor
@Observable
final class BackgroundSystemStatus {
  private(set) var backgroundRefresh = SyncRunContext.BackgroundRefresh.available
  private(set) var isLowPowerModeEnabled = false
  @ObservationIgnored private var observers: [NSObjectProtocol] = []

  func start() {
    refresh()
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    let names: [Notification.Name] = [
      UIApplication.backgroundRefreshStatusDidChangeNotification,
      .NSProcessInfoPowerStateDidChange,
    ]
    observers = names.map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
  }

  func stop() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
  }

  func refresh() {
    backgroundRefresh = .init(UIApplication.shared.backgroundRefreshStatus)
    isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
  }
}
