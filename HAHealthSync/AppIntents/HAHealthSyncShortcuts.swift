import AppIntents

struct HAHealthSyncShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SyncHealthWithHomeAssistantIntent(),
      phrases: [
        "Sync Health with Home Assistant in \(.applicationName)"
      ],
      shortTitle: "Sync Health",
      systemImageName: "heart.text.clipboard"
    )
  }
}
