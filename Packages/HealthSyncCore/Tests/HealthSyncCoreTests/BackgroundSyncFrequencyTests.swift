import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Background sync frequency")
struct BackgroundSyncFrequencyTests {
  @Test("Presets expose their user-facing name and minimum interval")
  func presetContract() {
    #expect(BackgroundSyncFrequency.responsive.displayName == "Responsive")
    #expect(BackgroundSyncFrequency.responsive.minimumInterval == 300)
    #expect(BackgroundSyncFrequency.balanced.displayName == "Balanced")
    #expect(BackgroundSyncFrequency.balanced.minimumInterval == 900)
    #expect(BackgroundSyncFrequency.batterySaver.displayName == "Battery Saver")
    #expect(BackgroundSyncFrequency.batterySaver.minimumInterval == 3_600)
    #expect(BackgroundSyncFrequency.daily.displayName == "Daily")
    #expect(BackgroundSyncFrequency.daily.minimumInterval == 86_400)
  }

  @Test("Picker labels include the actual interval except for daily")
  func selectionLabels() {
    #expect(BackgroundSyncFrequency.responsive.selectionLabel == "Responsive — 5 min")
    #expect(BackgroundSyncFrequency.balanced.selectionLabel == "Balanced — 15 min")
    #expect(BackgroundSyncFrequency.batterySaver.selectionLabel == "Battery Saver — 1 hr")
    #expect(BackgroundSyncFrequency.daily.selectionLabel == "Daily")
  }
}
