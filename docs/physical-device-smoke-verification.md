# Physical-Device Smoke Verification

**Status:** Partial physical-device verification completed on 2026-08-28. Signing, installation, launch, configured Tailscale HTTP connectivity, live HealthKit-to-Home-Assistant synchronization, and a bounded historical import were exercised. This is not evidence for Shortcut execution, Home Assistant-to-HealthKit writes, or background reliability.

## Environment

- App commit: `0c058e6dd4e7f9f00e4150f3426f3537380cfca8`
- Xcode: 26.6 (`17F113`)
- Device: physical iPhone 14 (`iPhone14,7`)
- Device OS: iOS 26.6 (`23G71`)
- Connection: paired Xcode wireless/local-network connection
- App bundle: `com.olhapi.HAHealthSync`, version `0.1.0` build `1`

Device serial numbers, UDIDs, account identifiers, URLs, credentials, and health values are intentionally omitted.

## Verified evidence

- A physical-iOS build completed successfully using the signed-in developer team and an existing Apple Development identity.
- `codesign --verify --deep --strict` passed for the generated app.
- The signed app contains `com.apple.developer.healthkit` and `com.apple.developer.healthkit.background-delivery` entitlements.
- The signed application identifier matches the expected team and `com.olhapi.HAHealthSync` bundle identifier.
- `devicectl` installed the 6.3 MiB app successfully on the physical iPhone.
- `devicectl` launched the app successfully, and the process remained alive after launch.
- The installed-app inventory reported **HA Health Sync**, bundle `com.olhapi.HAHealthSync`, version `0.1.0`, build `1`.
- The repository remained clean; no source or project signing setting was changed for the device build.

## Storage-bound verification

No simulator runtime, simulator device, package dependency, Xcode component, or asset was downloaded. Xcode fetched only the small provisioning profile required for this app.

Opening Xcode's Devices window automatically started copying iOS 26.6 shared-cache symbols from the phone. That operation was stopped, its exact partial `iPhone14,7 26.6 (23G71)` cache (1.1 GiB at cancellation) was removed, and only this project's reproducible DerivedData and SwiftPM build caches were removed afterward. Existing simulator runtimes and the pre-existing iOS 26.5.2 device-support caches were not changed. The Data volume reported 1.8 GiB available after cleanup.

The app remains installed on the phone. Rebuilding locally will recreate this project's deleted build caches.

## Follow-up interoperability evidence

After the networking and incremental-sync fixes were installed in place on 2026-08-28:

- The installed behavior corresponds to code commit `94a7c25064e65bfcf8d3e6c6e7a0de3fd3ac905a`; later documentation-only changes do not alter that binary.
- The user confirmed the configured, explicitly allowed Tailscale HTTP connection succeeded on the physical phone.
- The user confirmed a manual live HealthKit-to-Health-Bridge synchronization succeeded. The app's protected, value-free status record reported no final failure.
- An initial sleep metric with historical anchored changes but no current-window value was checkpointed and skipped instead of repeating a compatibility failure. The fix is covered by an anchor transaction regression test.
- Health Bridge reported experimental backfill protocol 1 available. The protected checkpoint store independently recorded 16 committed metrics.
- The installed build at that time reported 85 attempted metrics, 16 committed metrics, 370 committed points, and 69 local failures. Follow-up diagnosis proved that the report incorrectly classified metrics with fewer than two eligible points as validation failures. The reporting fix separates those metrics under “Skipped (no eligible history)” while preserving genuine errors under “Failures”; the original 16 confirmed commits remain valid.
- A clean, no-change live prerequisite is now accepted before backfill. The fix is covered by a coordinator regression test.

The records inspected for this follow-up contain identifiers, categories, counts, timestamps, and checkpoints only. No credential, URL, or health value was extracted or recorded.

## Historical-import reporting correction

Code commit `d77897d` was installed in place on the connected phone on 2026-08-28. The install succeeded while the phone was locked; the automated launch request was denied by iOS until the user unlocks the device. The corrected build reports metrics with fewer than two eligible points as skipped, not failed. A new import on the unlocked phone remains the physical-device confirmation for the displayed split.

## Still unverified

- First-launch privacy and onboarding UI on the physical display
- Partial or denied HealthKit authorization
- Real HealthKit reads, writes, observer delivery, corrections, and deletions
- Independently repeating both labeled connection tests and their invalid-credential cases
- Pull-to-refresh synchronization against an unmodified integration
- Home Assistant to HealthKit pairings and duplicate/feedback-loop behavior on-device
- Shortcut discovery and invocation outside the test process
- Local-network permission behavior
- Locked-phone, force-quit, network-change, and short-background-window behavior
- Backfill retry/idempotency, incompatible recorder behavior, and medication access on-device
- The corrected historical-import skipped/failure split on a new physical-device import
- The required continuous 24-hour background observation

These items remain unchecked in the [real-device checklist](real-device-checklist.md). Background synchronization must continue to be described as best effort and controlled by iOS.
