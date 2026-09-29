struct DestructiveActionPresentation {
  let title: String
  let removedHeading: String
  let removed: [String]
  let preservedHeading: String
  let preserved: [String]
  let reviewButtonTitle: String
  let stageOneTitle: String
  let stageOneMessage: String
  let confirmationTitle: String
  let confirmationMessage: String

  static let reset = DestructiveActionPresentation(
    title: "Reset Synchronization State",
    removedHeading: "Removed",
    removed: [
      "Apple Health query anchors",
      "Home Assistant import checkpoints",
      "Historical import checkpoints",
      "Local archive import checkpoint and pending upload",
      "Medication checkpoints",
      "Metric freshness records",
      "Recent sync status",
    ],
    preservedHeading: "Preserved",
    preserved: [
      "Connection settings and Keychain credentials",
      "Device-only archive uploader credential",
      "Selected metrics and entity pairings",
      "Apple Health samples and Home Assistant data",
      "Home Assistant health archive",
    ],
    reviewButtonTitle: "Review Reset",
    stageOneTitle: "Review synchronization reset",
    stageOneMessage: "Settings, credentials, metrics, and pairings remain.",
    confirmationTitle: "Reset Synchronization State",
    confirmationMessage:
      "The next sync may resend current data. The Home Assistant health archive remains untouched; delete it separately as an administrator in the Health Bridge archive card."
  )

  static let deleteAll = DestructiveActionPresentation(
    title: "Delete All Local App Data",
    removedHeading: "Deleted From This iPhone",
    removed: [
      "Connection settings",
      "Keychain credentials",
      "Selected metrics and entity pairings",
      "Synchronization checkpoints",
      "Local archive import checkpoint and pending upload",
      "Device-only archive uploader credential",
      "Recent sync status",
    ],
    preservedHeading: "Untouched",
    preserved: [
      "Apple Health samples and Home Assistant data",
      "Home Assistant entities and recorder history",
      "Home Assistant health archive",
    ],
    reviewButtonTitle: "Review Delete",
    stageOneTitle: "Review complete local deletion",
    stageOneMessage:
      "All Health Sync configuration and credentials on this iPhone will be removed.",
    confirmationTitle: "Delete All Local App Data",
    confirmationMessage:
      "This removes the iPhone's archive uploader credential. An administrator must approve a new uploader or transfer before archive import can resume. The Home Assistant health archive remains; delete it separately as an administrator in the Health Bridge archive card."
  )
}
