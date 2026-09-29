import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Sync trigger")
struct SyncTriggerTests {
  @Test("Only system-launched triggers are automatic")
  func automatic() {
    #expect(SyncTrigger.healthKitObserver.isAutomatic)
    #expect(SyncTrigger.appRefresh.isAutomatic)
    #expect(SyncTrigger.background.isAutomatic)
    #expect(!SyncTrigger.manual.isAutomatic)
    #expect(!SyncTrigger.pullToRefresh.isAutomatic)
    #expect(!SyncTrigger.shortcut.isAutomatic)
  }

  @Test("Budgets match the background runtime each trigger receives")
  func budgets() {
    #expect(SyncTrigger.appRefresh.budget == 25)
    #expect(SyncTrigger.shortcut.budget == 25)
    #expect(SyncTrigger.healthKitObserver.budget == 18)
    #expect(SyncTrigger.background.budget == 18)
    #expect(SyncTrigger.manual.budget == nil)
    #expect(SyncTrigger.pullToRefresh.budget == nil)
  }

  @Test("Legacy and new trigger raw values decode")
  func decoding() throws {
    let data = Data(#"["background","healthKitObserver","appRefresh"]"#.utf8)
    let triggers = try JSONDecoder().decode([SyncTrigger].self, from: data)
    #expect(triggers == [.background, .healthKitObserver, .appRefresh])
  }

  @Test("Deadline exhaustion has its own category")
  func deadlineCategory() throws {
    let data = Data(#"["deadlineExceeded"]"#.utf8)
    #expect(try JSONDecoder().decode([SyncFailureCategory].self, from: data) == [.deadlineExceeded])
  }
}
