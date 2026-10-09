# Architecture

Vital Relay separates platform adapters from a deterministic Swift package so synchronization policy can be tested without an iPhone or Home Assistant instance.

## Boundaries

- `HealthStoreClient` adapters own HealthKit authorization, current and anchored queries, observer delivery, workouts, sleep mapping, medication reads, and allowlisted writes.
- `HomeAssistantClient` owns authenticated `/api/` and entity-state REST calls with bearer authentication.
- `HealthBridgeWebhookClient` and `HealthBridgeBackfillClient` own the live and experimental webhook wire contracts and acknowledgement validation.
- `MetricRegistry` is the single typed source for identifier, HealthKit type, name/category, units, aggregation, window, background/write capability, minimum OS, transformation, validation, and availability.
- `SyncCoordinator`, `InboundSyncCoordinator`, `BackfillCoordinator`, and `MedicationSyncCoordinator` are actors that own directional transactional policy and prevent overlapping work.
- `BidirectionalSyncCoordinator` is the shared normal-sync gate. It coalesces triggers, applies the persisted automatic cadence, runs outbound metrics and inbound pairings concurrently, and records one combined value-free event.
- protocol-backed checkpoint, configuration, pairing, credential, and status stores isolate persistence from synchronization logic.
- `HealthKitObserverManager` treats observer delivery as the primary background signal; `AppRefreshManager` offers a secondary best-effort opportunity.
- `AppIntentSyncHandler` and `AppModel` invoke the same shared bidirectional coordinator.
- `AppModel` translates actor results into value-free observable UI state. SwiftUI views do not query HealthKit or construct requests.

## Outbound transaction

For each selected metric, the coordinator obtains changes from its committed anchor, transforms and validates the authoritative value, sends a versioned live request, requires a matching positive applied acknowledgement, and only then commits the candidate anchor. Cancellation, retry exhaustion, validation failure, or a negative/mismatched acknowledgement retains the old anchor. A per-metric actor gate prevents concurrent transactions.

Daily windows are calendar-derived rather than fixed-duration, duplicate UUIDs and overlapping intervals are normalized, and imported samples are excluded by source/origin metadata to prevent feedback loops.

## Inbound transaction

Each enabled pairing independently fetches one authenticated entity state, strictly parses state/unit/timestamps, applies its bounded transform, converts to the fixed native HealthKit unit, validates plausible bounds, compares its checkpoint, and saves with stable application-owned sync metadata. The checkpoint advances only after HealthKit confirms the save. A deterministic sync identifier makes a retry safe if checkpoint persistence fails after the save.

## Background and cancellation

Observer callbacks batch nearby HealthKit type notifications and invoke every completion promptly. They do not own cadence; they forward one background trigger to `BidirectionalSyncCoordinator`. Background App Refresh schedules its earliest opportunity from the persisted last-attempt timestamp and the selected minimum interval. The coordinator applies the authoritative gate, so observer and refresh triggers cannot bypass each other.

The four persisted presets are Responsive (5 minutes), Balanced (15 minutes, default and migration fallback), Battery Saver (1 hour), and Daily (24 hours). Manual Sync Now and Shortcuts bypass that automatic gate, run both directions immediately, and reset the next automatic eligibility. Short execution windows cancel structured tasks without corrupting anchors. Disabling background synchronization stops observers, disables HealthKit background delivery, cancels scheduled and active refresh work, and preserves checkpoints. `earliestBeginDate` is only a request to iOS; no next-run time is promised.

## Historical and medication isolation

Historical import is separately enabled, capability-probed, limited, checkpointed, and outbound-only. Recorder incompatibility changes only the backfill capability state; live sync has no dependency on recorder internals.

Medication synchronization is available only through iOS 26 APIs behind availability checks. It uses per-object authorization, opaque app-derived identifiers, anchored dose-event changes, and its own checkpoint. Medication writes are intentionally absent because Apple exposes these APIs as read workflows.

## Dependency policy

There are no third-party runtime or test dependencies. `HealthSyncCore` is a checked-in local Swift package; all other dependencies are Apple frameworks included with Xcode. Networking uses URLSession and injectable transports. Tests use fakes, in-memory stores, and a custom URLProtocol rather than live services.
