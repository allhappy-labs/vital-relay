# Milestone 4 Verification

Verified on 2026-08-28 using only the already-installed iPhone 17 Pro simulator running iOS 26.5. No dependency, Xcode component, simulator runtime, or device was downloaded or created.

## Completed behavior

- Users can create, edit, enable, disable, and delete independent Home Assistant → Apple Health pairings without changing outbound metric selection.
- At this milestone snapshot, the destination picker was backed by 15 source-confirmed numeric HealthKit write destinations; computed, read-only, clinical, sleep, workout, medication, and unverified types were absent. The current allowlist is documented in `healthkit-write-allowlist.md`.
- Each pairing stores a Home Assistant entity ID, typed source/native destination units, a bounded optional transform, and enabled state in a protected, atomic, backup-excluded file.
- Authenticated entity retrieval uses the long-lived access token only and strictly parses `state`, `last_changed`, `last_updated`, and `attributes.unit_of_measurement`.
- The inbound actor performs fetch → normalize/validate → deterministic identity → checkpoint comparison → HealthKit save → checkpoint commit. Failure or cancellation before commit retains the old checkpoint.
- HealthKit samples use `last_updated`, Apple's sync identifier/version metadata, and a value-free application origin marker. Outbound queries exclude both this app's source and the origin marker to prevent feedback loops.
- Manual Sync Now runs outbound metrics and enabled inbound pairings independently. Background inbound execution remains disabled. The App Shortcut also runs both directions and reports counts/categories only.
- The dashboard exposes only inbound saved/skipped/failure counts. It never displays fetched entity values.

## Automated evidence

| Gate | Result |
| --- | --- |
| `swift test --package-path Packages/HealthSyncCore` | Passed: 148 tests in 34 suites |
| `xcodebuild build` on iPhone 17 Pro / iOS 26.5 | `BUILD SUCCEEDED`; local simulator signing preserved HealthKit and Keychain entitlements |
| `xcodebuild test` on iPhone 17 Pro / iOS 26.5 | Passed: 94, failed: 0, skipped: 5; 99 total |
| Pairing UI smoke tests | Passed: allowlisted editor state, entity validation, explicit permission action, create, duplicate rejection, and confirmed deletion |
| `swift-format lint --recursive --strict` | Passed |
| `xcodebuild analyze` on iPhone 17 Pro / iOS 26.5 | `ANALYZE SUCCEEDED` |
| App Intents build extraction | Generated `Metadata.appintents` and trained “Sync Health with Home Assistant in HA Health Sync” |

The five skipped tests are CoreSimulator filesystem-metadata assertions for protected configuration, outbound checkpoint/status, pairing, and pairing-checkpoint stores. The suite still tests the exact requested file-protection options, atomic writes, and backup-exclusion behavior.

The authoritative `.xcresult` identifies the destination as `iPhone 17 Pro`, iOS 26.5 build 23F77, arm64; it records 99 tests, 94 passed, five skipped, zero failed, and zero expected failures.

The initial test invocation incorrectly supplied `CODE_SIGNING_ALLOWED=NO`. Security correctly returned `errSecMissingEntitlement` (`-34018`) for the two real Keychain tests. Re-running the documented command with normal Xcode “Sign to Run Locally” restored the app identifier, Keychain access group, HealthKit, and background-delivery entitlements; the Keychain tests and complete suite then passed. The no-signing result is not counted as verification evidence.

Xcode emitted its local `DebuggerLLDB.DebuggerVersionStore.StoreError` diagnostic while launching simulator processes. The final `.xcresult` contains no test failures; this is external simulator tooling output rather than a compiler/source warning.

## Remaining limitations

- The simulator tests sample creation and saves through fakes. It does not verify a real HealthKit authorization prompt, an actual HealthKit database write, or how each writable type behaves on a physical iPhone.
- No live Home Assistant instance or real credentials were used. Authenticated REST requests and state responses are tested through an injectable transport and fixtures, not a user deployment.
- App Shortcut routing and metadata are verified in-process/build-time; invocation from the Shortcuts app remains physically unverified.
- HealthKit background delivery, locked-phone behavior, force-quit behavior, and 24-hour reliability remain unverified and must not be claimed.
- The [real-device checklist](real-device-checklist.md) remains entirely unrun because this workspace is restricted to the existing simulator.
- Experimental historical backfill, the remaining Health Bridge registry metrics, iOS 26 medication support where feasible, diagnostics export, destructive reset controls, and final polish remain Milestone 5 work.
