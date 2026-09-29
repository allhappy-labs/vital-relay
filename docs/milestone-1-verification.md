# Milestone 1 verification

Verified on 2026-08-28 (Europe/Zurich) using only the pre-existing `iPhone 17 Pro` simulator on iOS 26.5. No package, simulator runtime, or device was downloaded or created.

## Completed behavior

- Native iOS 18+ SwiftUI project and local testable Swift package.
- Separate device-only Keychain records for the Health Bridge webhook secret and Home Assistant long-lived token.
- Protected, backup-excluded configuration storage with no credentials in the document.
- Strict URL normalization and local-HTTP confirmation policy.
- Independent authenticated API and webhook connection tests.
- Strongly typed registry and HealthKit queries for Steps, Body Mass, and Resting Heart Rate.
- Actor-isolated manual sync, one metric per versioned live request, strict acknowledgement validation, cancellation, coalescing, and privacy-safe reports.
- Onboarding, dashboard, settings, Sync Now, pull-to-refresh, and launch-only fake UI tests.

## Exact evidence

| Gate | Result |
|---|---|
| `rtk swift test --package-path Packages/HealthSyncCore` | Exit 0; 54 tests in 11 suites passed. |
| `rtk xcodebuild build ... iPhone 17 Pro,OS=26.5` | Exit 0; `BUILD SUCCEEDED`; no compiler warnings. |
| `rtk xcodebuild test ... iPhone 17 Pro,OS=26.5` | Exit 0; xcresult `Passed`; 31 passed, 1 skipped, 0 failed. |
| `rtk xcrun swift-format lint --recursive --strict ...` | Exit 0; no findings. |
| `rtk xcodebuild analyze ... iPhone 17 Pro,OS=26.5` | Exit 0; `ANALYZE SUCCEEDED`; no analyzer warnings. |
| Tracked-file privacy audit | Only explicit invented fixture/test values matched; no logs, DerivedData, `.build`, `.env`, or `IntegrationTests.local.json` are tracked. |
| Simulator visual inspection | Privacy screen and dashboard rendered without clipping or private data. |

The exact file-protection metadata assertion is the single skipped iOS test because CoreSimulator does not report that metadata. The test suite separately proves the exact protected write options and backup exclusion.

The successful `xcodebuild test` command emits `DebuggerLLDB.DebuggerVersionStore.StoreError` and `no debugger version` from the installed Xcode simulator test launcher. This is Xcode infrastructure noise: the command exits 0, its xcresult is `Passed`, and it contains no failed tests or build diagnostics. Build and analyze emit no warning or error diagnostic.

## Remaining limitations

- Real HealthKit samples and partial authorization have not been verified.
- No user-owned Home Assistant instance or credentials were used; live API/webhook interoperability remains unverified.
- HealthKit background delivery, locked-phone operation, force-quit behavior, Shortcuts, inbound HealthKit writes, backfill, and medication support are not part of Milestone 1.
- Background reliability cannot be claimed without at least 24 hours of physical-device testing. The user requested simulator-only execution, so this remains deliberately unverified.
