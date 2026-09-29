# Milestone 3 Verification

Verified on 2026-08-28 using only the already-installed iPhone 17 Pro simulator running iOS 26.5. No package, dependency, simulator runtime, or device was downloaded or created.

## Completed behavior

- HealthKit observer queries are installed once per selected HealthKit type and use immediate background-delivery registration where Apple supports it.
- Duplicate callbacks and callbacks for different types batch into one shared background trigger, and every observer completion handler is called exactly once.
- Observer work has a bounded execution window and delegates to the same bidirectional coordinator used by manual synchronization and Shortcuts.
- Responsive (5 minutes), Balanced (15 minutes, default), Battery Saver (1 hour), and Daily (24 hours) are persisted minimum intervals applied across observer and App Refresh triggers.
- One `BGAppRefreshTask` identifier provides a secondary catch-up opportunity, requests the persisted eligibility date, handles a throttled result exactly, and cancels synchronization on expiration.
- “Sync Health with Home Assistant” is emitted as App Intents metadata and Shortcut training data and returns only a concise value-free result.
- The app exposes a best-effort background setting and frequency picker, per-metric registration state, last attempt/success/failure, and bounded combined value-free events.
- The built simulator configuration contains the HealthKit and HealthKit background-delivery entitlements, one Background App Refresh mode, and one permitted task identifier.

## Automated evidence

| Gate | Result |
| --- | --- |
| `swift test --package-path Packages/HealthSyncCore` | Passed: 217 tests in 49 suites |
| `xcodebuild build` on iPhone 17 Pro / iOS 26.5 | `BUILD SUCCEEDED` |
| `xcodebuild test` on iPhone 17 Pro / iOS 26.5 | Passed: 161, failed: 0, skipped: 5 (166 total) |
| `swift-format lint --recursive --strict` | Passed |
| `xcodebuild analyze` on iPhone 17 Pro / iOS 26.5 | `ANALYZE SUCCEEDED` |
| App Intents build extraction | Generated `Metadata.appintents` and trained “Sync Health with Home Assistant in HA Health Sync” |
| Built capability inspection | HealthKit and background-delivery entitlements; `fetch` only; `com.olhapi.HAHealthSync.refresh` only |

The five skipped tests are exact filesystem data-protection metadata assertions for the protected configuration, pairing, pairing-checkpoint, sync-checkpoint, and status stores. CoreSimulator does not report this metadata; deterministic tests still cover each store's requested protection and backup-exclusion behavior.

Xcode emitted its local `DebuggerLLDB.DebuggerVersionStore.StoreError` diagnostic while launching simulator test processes. The `.xcresult` is authoritative and records 166 total tests, 161 passed, five skipped, and zero failures. This is simulator tooling output rather than a source/compiler warning.

## Remaining limitations

- Actual HealthKit observer relaunch, locked-phone access, Background App Refresh scheduling, force-quit behavior, and Shortcut invocation outside the test process cannot be verified on a simulator.
- Presets limit how often automatic attempts may begin; they do not promise execution at that interval. iOS decides whether and when the app receives observer or refresh execution time.
- The [real-device checklist](real-device-checklist.md) remains entirely unrun. Background synchronization must not be called reliable until that checklist has passed over at least 24 hours on a physical iPhone.
- No live Home Assistant instance or user credentials were used, so live API/webhook interoperability remains unverified.
- Home Assistant-to-HealthKit imports are Milestone 4 work.
- Historical backfill, remaining integration metrics, medication support, destructive reset controls, diagnostics export, and final UI polish are Milestone 5 work.
