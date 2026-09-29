import Foundation
import HealthSyncCore
import UIKit

extension SyncRunContext.BackgroundRefresh {
  init(_ status: UIBackgroundRefreshStatus) {
    switch status {
    case .available: self = .available
    case .denied: self = .denied
    case .restricted: self = .restricted
    @unknown default: self = .restricted
    }
  }
}

struct SystemSyncRunContextProvider: SyncRunContextProviding {
  func currentContext() async -> SyncRunContext? {
    await MainActor.run {
      SyncRunContext(
        backgroundRefresh: .init(UIApplication.shared.backgroundRefreshStatus),
        lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
        protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
      )
    }
  }
}
