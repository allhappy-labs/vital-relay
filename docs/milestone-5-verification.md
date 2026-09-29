# Milestone 5 verification

**Verification date:** 2026-08-28  
**Verified code commit:** `37b04e515ad81db6578cbdbab6499ce02a9eeee6`  
**Scope:** milestone gate used the existing simulator and local fakes; a later physical-device follow-up is recorded separately below

## Completed behavior

- Health Bridge backfill protocol 1 request, acknowledgement, limits, error mapping, bounded retry, live-entity prerequisite, checkpoint rollback, and recorder capability isolation.
- All 92 canonical integration identifiers represented in the registry; every selectable metric has a direct public HealthKit source and complete typed policy. The two integration-only derived values without direct HealthKit sources remain explicitly unavailable rather than guessed.
- iOS 26 per-medication authorization, anchored dose-event mapping, opaque identifiers, checkpointing, and versioned live delivery. Medication writes are intentionally unavailable.
- Experimental historical-import and medication settings with explicit scope, opt-in, availability, progress, cancellation, and committed-count states.
- Allowlist-first redacted diagnostics, synchronization-state reset, complete local-data deletion, editable connection settings, and automatic initial synchronization after onboarding.
- Original locally generated app icon, Dynamic Type-safe onboarding, dark-mode dashboard, accessibility labels/hints, and complete setup/privacy/architecture/troubleshooting documentation.
- Privacy-safe OSLog network lifecycle entries contain only static messages and the HTTP status code; no method, URL, header, body, entity, credential, or health value is logged.

## Environment

- Xcode 26.6 (`17F113`)
- Apple Swift 6.3.3 with Swift 6 language mode and complete strict concurrency
- Deployment target iOS 18.0
- Only existing simulator used: iPhone 17 Pro, iOS 26.5, device `D17101C9-01EB-488D-AFE1-58E6C089B853`
- No simulator, runtime, Xcode component, third-party dependency, or external asset was created or downloaded

## Automated evidence

`rtk swift test --package-path Packages/HealthSyncCore`

- Passed: 191 tests in 45 suites
- Failed: 0
- The package reported: `No external dependencies found`

`rtk xcodebuild build -project HAHealthSync.xcodeproj -scheme HAHealthSync -destination 'platform=iOS Simulator,id=D17101C9-01EB-488D-AFE1-58E6C089B853'`

- Result: `BUILD SUCCEEDED`
- App Intents metadata extraction and Shortcut phrase training completed during the test/analyze builds.
- Asset compilation produced `AppIcon` and `AccentColor` without asset warnings.

`rtk xcodebuild test -project HAHealthSync.xcodeproj -scheme HAHealthSync -destination 'platform=iOS Simulator,id=D17101C9-01EB-488D-AFE1-58E6C089B853'`

- Result bundle: `Test-HAHealthSync-2026.08.28_03-23-35-+0200.xcresult`
- Passed: 122
- Skipped: 5
- Failed: 0
- The five skips are explicit CoreSimulator limitations: it does not report iOS data-protection metadata. File-protection constants, write options, and backup exclusion are otherwise exercised.

`rtk xcodebuild analyze -project HAHealthSync.xcodeproj -scheme HAHealthSync -destination 'platform=iOS Simulator,id=D17101C9-01EB-488D-AFE1-58E6C089B853'`

- Exit status: 0
- Analyzer findings: 0

`rtk xcrun swift-format lint --strict --recursive HAHealthSync HAHealthSyncTests HAHealthSyncUITests Packages/HealthSyncCore/Sources Packages/HealthSyncCore/Tests Tools/AppIconGenerator`

- Exit status: 0
- Formatting violations: 0

## UI and asset evidence

- Light-mode onboarding was visually inspected at the largest accessibility Dynamic Type setting; content scrolls and the Continue action remains in a safe-area inset.
- The dashboard was visually inspected in dark mode on the same simulator.
- Focused UI coverage verifies onboarding credential privacy, separate connection tests, metric categories, manual sync counts, background status, pairings, experimental backfill, medication authorization, diagnostics, two-stage reset/delete confirmations, and editable connection prefill without secrets.
- The checked-in CoreGraphics generator reproduced the icon as 1024×1024 RGB with `hasAlpha: no`; no downloaded image or proprietary asset was used.

## Privacy and configuration audit

- The app contains one local Swift package and no remote Swift package reference.
- No tracked DerivedData, `.build`, `.xcresult`, local integration credential file, or SwiftPM workspace data was found.
- The built Info.plist contains both HealthKit usage descriptions, local-network description, the permitted refresh identifier, `fetch` background mode, and local-network-only ATS allowance.
- Generated simulator entitlements contain `com.apple.developer.healthkit`, `com.apple.developer.healthkit.background-delivery`, and the local application identifier.
- The built privacy manifest declares no tracking, tracking domains, collected-data categories, or required-reason API categories.
- Source inspection found no UserDefaults, SwiftData, CloudKit, iCloud storage, shared URL cache, TLS bypass, analytics, advertising, remote logging, or external backend.
- Keychain, protected-file, diagnostics-redaction, network contract, feedback-loop, duplicate-prevention, and reset/delete behavior are covered by automated tests.

## Explicitly unverified

The milestone gate itself used only the existing simulator. A later [physical-device verification](physical-device-smoke-verification.md) proved signing, installation, entitlements, launch, configured Tailscale HTTP connectivity, manual live synchronization, and a bounded protocol-1 historical import on an iPhone 14 running iOS 26.6. Therefore this milestone still does not claim:

- real HealthKit authorization behavior, sample reads/writes, or medication data;
- every authenticated API/webhook error path or Home Assistant-to-HealthKit write;
- Shortcut execution from the Shortcuts app outside the test process;
- locked-phone observer delivery, force-quit relaunch, or any background schedule/reliability;
- real iOS file-protection metadata; or
- the required 24-hour physical-device background observation.

The exact remaining scenarios are unchecked in [real-device-checklist.md](real-device-checklist.md). Background synchronization is described only as best effort and controlled by iOS.

## 2026-08-28 physical-device follow-up

- The installed behavior corresponds to code commit `94a7c25064e65bfcf8d3e6c6e7a0de3fd3ac905a`.
- The configured connection and manual HealthKit-to-Health-Bridge live synchronization were confirmed by the user on the installed build.
- A protected, value-free device status record isolated and verified the initial sleep-anchor compatibility fix.
- Backfill capability reported protocol 1 available, and the protected checkpoint store recorded 16 committed metrics. The UI reported 370 committed points from 85 attempted metrics.
- The original screen's 69 local failures were not evidence that the committed import rolled back. Follow-up diagnosis proved that metrics with fewer than two eligible points were incorrectly classified as validation failures. The corrected report tracks them as skipped and reserves failures for actual errors.
- Background execution over 24 hours, Shortcut execution, Home Assistant-to-HealthKit writes, medication behavior, and the remaining error matrices were not verified.

## Final regression verification

The compatibility follow-up used only the already-installed simulator and connected phone. No runtime, dependency, Xcode component, or asset was downloaded.

- `rtk swift test --package-path Packages/HealthSyncCore`: 196 tests in 46 suites passed.
- The complete Xcode result bundle recorded 137 passes and 5 expected CoreSimulator file-protection skips. Six UI processes were killed by the local Xcode/CoreSimulator duplicated-framework runner fault before assertions; rerunning those exact six tests together passed 6 of 6. Across the complete run and exact retry, every functional test passed and 5 simulator-only checks remained skipped.
- The simulator app build succeeded with App Intents metadata extraction and no build warnings.
- Static analysis succeeded with zero analyzer findings.
- Strict recursive Swift formatting, plist validation, protected local-configuration ignore verification, debug-marker search, and strict patch whitespace validation passed.

## Historical-import reporting regression

The later reporting correction was verified without downloading any runtime or dependency:

- 197 `HealthSyncCore` tests in 46 suites passed.
- The complete existing-simulator Xcode suite passed in one run: 145 passed, 5 expected CoreSimulator file-protection skips, and 0 failed.
- The app-model regression used the observed 85 attempted, 16 committed, 69 skipped, and 370 committed-point counts and confirmed zero failures and no current error.
- The UI regression confirmed that the screen renders 69 under “Skipped (no eligible history)” and 0 under “Failures.”
- Simulator build, static analysis, strict formatting, plist validation, whitespace validation, and privacy checks passed.
- Code commit `d77897d` was signed, built for the connected phone, code-signature verified, and installed in place. Automated launch was denied only because the phone remained locked.
