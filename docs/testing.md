# Testing

## Lifetime unlock candidate qualification

The exact app-source candidate `6b3a049d72ddde63dcefe7543e3299825d171530` passed the complete Core and simulator gates on 27 September 2026: 490 Core tests and 332 Xcode tests passed; 8 expected Xcode skips and zero failures. This supersedes the earlier `c8fa3b27` qualification. Fresh signed local archive/export, artifact identity, synthetic screenshot limitations, external blockers, and reproduction commands are recorded in [lifetime unlock release evidence](2026-09-27-lifetime-unlock-release-evidence.md). These local gates do not establish live StoreKit, processed TestFlight, physical background execution, or App Store readiness.

## Existing-simulator-only policy

All automated iOS verification in this workspace targets the simulator that was already installed:

```text
platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5
```

Do not install an Xcode component, download another runtime, or create another device. The project has no external package dependency to resolve.

Do not add `CODE_SIGNING_ALLOWED=NO` to simulator tests. The Keychain contract tests require Xcode's local simulator signature and generated access-group entitlement; disabling signing produces `errSecMissingEntitlement` and is not a valid test result.

## Complete simulator gate

```bash
rtk swift test --package-path Packages/HealthSyncCore

rtk xcodebuild build -project HAHealthSync.xcodeproj -scheme HAHealthSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'

rtk xcodebuild test -project HAHealthSync.xcodeproj -scheme HAHealthSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'

rtk xcrun swift-format lint --recursive --strict \
  HAHealthSync Packages HAHealthSyncTests HAHealthSyncUITests

rtk xcodebuild analyze -project HAHealthSync.xcodeproj -scheme HAHealthSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

The iOS 26.5 simulator can compile and test the iOS 27 archive implementation with deterministic adapters, but cannot exercise the iOS 27 HealthKit authorization boundary or physical original samples. The archive tests cover protocol-2 capability/acknowledgement, per-type discovery and mapping, interval checkpoints, duplicate UUIDs, resume, reconciliation, and separate projection status. Run the full gate above plus local release checks on the exact candidate commit; record command exit codes in [full-history archive verification](full-history-archive-verification.md). A green automated gate does not complete the installed-fork and device checklist.

The available release checks are `rtk bash Tools/verify-app-icon.sh`, `rtk node AppStore/verify-metadata.mjs`, and, after an unsigned Release build, `rtk bash Tools/verify-release-bundle.sh <path-to-HAHealthSync.app>`. The bundle verifier needs an actual app path and cannot replace signing or physical installation. `rtk git diff --check` catches whitespace errors in the documentation change.

## Focused Tailscale HTTP transport gate

```bash
rtk swift test --package-path Packages/HealthSyncCore \
  --filter TailscaleAddressPolicyTests

rtk xcodebuild test -project HAHealthSync.xcodeproj -scheme HAHealthSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:HAHealthSyncTests/HostAddressResolverTests \
  -only-testing:HAHealthSyncTests/URLSessionTransportTests \
  -only-testing:HAHealthSyncTests/AppModelConnectionTests
```

These focused unit tests use only synthetic hostnames and addresses with an injected resolver and URL protocol. They never query DNS, contact a tailnet, or use a real credential or health value.

## Focused incremental and backfill transaction gates

```bash
rtk swift test --package-path Packages/HealthSyncCore \
  --filter AnchorTransactionTests

rtk swift test --package-path Packages/HealthSyncCore \
  --filter BackfillCoordinatorTests
```

The anchor suite verifies that first-run historical changes outside a metric's current window commit the candidate anchor and skip cleanly, while a deletion after an already committed latest-value anchor retains the compatibility failure and rolls back. The backfill suite verifies that a clean no-change live prerequisite permits history querying and recorder submission, zero or one eligible point is counted as skipped rather than failed, and genuine failures still preserve the prior checkpoint. App-model and UI coverage verify the exact 85-attempted, 16-committed, 69-skipped, 370-point presentation with zero failures and no current error.

For an optional real simulator connectivity gate, create the ignored `HAHealthSyncTests/IntegrationTests.local.json` with only a base URL:

```json
{
  "base_url": "http://homeassistant.example-tailnet.ts.net:8123"
}
```

Then run:

```bash
rtk xcodebuild test -project HAHealthSync.xcodeproj -scheme HAHealthSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:HAHealthSyncTests/LiveTailscaleConnectivityTests
```

The synchronized test target bundles this ignored local file. The test reads only `base_url`, sends a synthetic invalid bearer value, and requires HTTP 401 through both the MagicDNS transport path and the resolver-derived direct Tailscale IP. It never reads or sends the webhook secret or long-lived access token. Without the ignored file, the two live tests skip.

The scheme includes unit tests and UI smoke tests. UI tests use `-ui-testing-onboarding`, `-ui-testing-dashboard`, and `-ui-testing-background` to assemble in-memory fakes; these flags contain no credentials or health values and make no network or HealthKit request.

Milestone 2 tests cover all 34 initial registry definitions and transformations, percentage and unit normalization, local-calendar aggregation across both Zurich DST transitions, sample/source deduplication, overlapping sleep stages, workout payloads, secure anchor coding and storage, transactional anchor commit/rollback, retry/cancellation/deadline behavior, categorized selection, and value-free dashboard results.

Milestone 3 tests cover bounded status storage, per-metric background registration state, unique HealthKit observer registration, duplicate callback coalescing, exactly-once completion, short-window cancellation, database-inaccessible behavior, BGAppRefresh registration/rescheduling/expiration, Shortcut trigger routing, App Intent result privacy, settings, and recent value-free events. Xcode build output must show App Intents metadata and Shortcut training data generation.

Milestone 4 tests cover the exact writable allowlist, typed conversions, strict entity-state parsing, pairing validation/protected persistence, deterministic sync identities, HealthKit metadata and authorization errors, imported-source filtering, per-pairing transaction commit/rollback/cancellation, concurrent trigger coalescing, independent pairing progress, Shortcut inbound routing, and create/duplicate/delete UI behavior. All HealthKit saves and Home Assistant state requests remain faked in the automated suite.

Milestone 5 tests cover backfill request/acknowledgement/error contracts, capability probing, live-entity prerequisites, batching and checkpoint rollback, the complete direct-HealthKit metric registry, iOS 26 medication authorization and anchored dose-event mapping, medication checkpoint rollback, diagnostics allowlisting/redaction, synchronization reset, complete local deletion, active background-task cancellation, editable connection credential preservation, and experimental/maintenance UI behavior.

The app icon is produced without downloads from `Tools/AppIconGenerator/main.swift`. To reproduce and validate it using installed tools only:

```bash
rtk xcrun swiftc Tools/AppIconGenerator/main.swift -o /tmp/HAHealthSyncAppIconGenerator
rtk /tmp/HAHealthSyncAppIconGenerator \
  HAHealthSync/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
rtk sips -g pixelWidth -g pixelHeight -g space -g hasAlpha \
  HAHealthSync/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Expected: 1024×1024, RGB/sRGB-compatible output, and `hasAlpha: no`.

## Optional live integration configuration

For the Tailscale transport gate, create `HAHealthSyncTests/IntegrationTests.local.json` as described above. The file is ignored by Git and must contain only `base_url`; no credential belongs in it. When the file is present, both the focused command and the normal Xcode suite run the two live connectivity tests against that URL with a synthetic invalid bearer value. Remove the file, or leave it absent, to make those tests skip without contacting Home Assistant.

The older root-level `IntegrationTests.local.example.json` remains a manual integration template. No automated test reads that file.

Never commit or place real credentials in environment dumps, test results, shell history, screenshots, fixtures, or diagnostic archives.

## Simulator limitations

- HealthKit does not provide meaningful personal health samples in the simulator. HealthKit adapter tests therefore use deterministic domain fixtures and fakes.
- Real authorization combinations and denial behavior need a physical iPhone.
- HealthKit observer delivery, locked-phone execution, and force-quit behavior cannot be validated here.
- CoreSimulator does not expose iOS file-protection metadata; the exact write options are tested and the filesystem metadata assertion is skipped when unavailable.
- Real Home Assistant API and webhook connectivity require user-owned credentials and are not exercised by the default tests.
- The disposable Home Assistant Core 2026.9.3 container gate passed with fork `2fe7916`, including two clean shutdowns, a backup containing a restorable archive, recorder purge, and raw/statistics readback. The separate native macOS/Homebrew Python environment still crashes at interpreter finalization with or without the component. Container success does not establish HA OS/Supervisor restore, production behavior, or iOS 27 HealthKit import.

Accordingly, simulator success is not evidence of reliable background synchronization. That claim requires the unexecuted [real-device checklist](real-device-checklist.md), including at least 24 hours of physical-device observation.
