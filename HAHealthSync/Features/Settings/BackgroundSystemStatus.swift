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

/// The one system condition stopping background sync, if any. Shown on Background Sync only
/// when it applies; the full system state lives in Sync Details.
struct BackgroundSyncBlocker: Equatable {
  let message: String
  /// Whether the user can fix it from this app's page in iOS Settings.
  let offersSettings: Bool

  static func current(
    refresh: SyncRunContext.BackgroundRefresh, isLowPowerModeEnabled: Bool
  ) -> BackgroundSyncBlocker? {
    switch refresh {
    case .denied:
      return .init(
        message: "Background App Refresh is off for Health Sync.", offersSettings: true)
    case .restricted:
      return .init(
        message: "Background App Refresh is restricted on this iPhone.", offersSettings: false)
    case .available:
      guard isLowPowerModeEnabled else { return nil }
      return .init(
        message: "iOS pauses background refresh in Low Power Mode.", offersSettings: false)
    }
  }
}
