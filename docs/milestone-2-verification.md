# Milestone 2 Verification

Verified on 2026-08-28 using only the already-installed iPhone 17 Pro simulator running iOS 26.5. No package, simulator runtime, or device was downloaded or created.

## Completed behavior

- All 34 initial Apple Health metrics are represented by the typed registry and categorized selection UI.
- Pure transformation and validation cover the integration's exact units, fractional percentages, sleep seconds, timestamps, sleep-stage codes, and workout structure.
- Daily aggregation uses local calendar boundaries across daylight-saving changes; duplicate UUIDs and this app's imported samples are excluded.
- Sleep and mindful intervals are unioned without double counting, and the latest workout uses a dedicated typed payload.
- Each metric uses an independently persisted, protected HealthKit query anchor.
- Anchors advance only after a matching, applied Health Bridge acknowledgement with a positive updated-entity count.
- Transient failures use bounded retry with jitter; cancellation, permanent failures, and failed acknowledgements preserve the previous anchor.
- The dashboard reports only timestamps, metric counts, and value-free failure categories.

## Automated evidence

| Gate | Result |
| --- | --- |
| `swift test --package-path Packages/HealthSyncCore` | Passed: 95 tests in 22 suites |
| `xcodebuild build` on iPhone 17 Pro / iOS 26.5 | `BUILD SUCCEEDED` |
| `xcodebuild test` on iPhone 17 Pro / iOS 26.5 | Passed: 49, failed: 0, skipped: 2 |
| `swift-format lint --recursive --strict` | Passed |
| `xcodebuild analyze` on iPhone 17 Pro / iOS 26.5 | `ANALYZE SUCCEEDED` |

The two skipped tests are the protected configuration and protected checkpoint filesystem-metadata assertions. CoreSimulator does not report the iOS data-protection metadata; both stores' requested protection options and backup-exclusion behavior are still exercised by deterministic tests.

The test launcher emitted Xcode's local `DebuggerLLDB.DebuggerVersionStore.StoreError` diagnostic while starting simulator tests. The `.xcresult` is authoritative and records the complete run as passed with zero failures.

## Remaining limitations

- HealthKit permission combinations, real samples, background observer delivery, lock-state behavior, and force-quit behavior remain unverified because the hard requirement is simulator-only operation.
- A deletion that leaves a latest-value metric empty cannot be represented by the live Health Bridge protocol. The app reports a compatibility failure and retains the old anchor instead of fabricating a value or claiming success.
- Background synchronization and Shortcuts are Milestone 3 work.
- Home Assistant-to-HealthKit imports are Milestone 4 work.
- Historical backfill, remaining integration metrics, and medication support are Milestone 5 work.
