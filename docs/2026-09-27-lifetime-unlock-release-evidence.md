# Lifetime unlock candidate qualification — 27 September 2026

## Final review fix candidate

Current app-source candidate: `6b3a049d72ddde63dcefe7543e3299825d171530`. It adds entitlement rechecking after queued paid sync waits, preserves independent free sync during purchase authorization, adds foreground product-fetch retry, and stabilizes StoreKit update tests. The earlier candidates and artifacts are historical and superseded for release qualification.

Fresh local gates: Core exit 0 (490 tests in 70 suites); strict recursive formatting, simulator build/analyzer, unsigned Release build/bundle verifier, layered icon verification, metadata verifier, website verify/lint/build, and production dependency audit all exit 0 (0 vulnerabilities). Final complete simulator gate exit 0: 340 total, 332 passed, 8 skipped, 0 failed; result bundle `/tmp/healthsync-6b3a049-qualification/tests.xcresult`. The same six file-protection metadata checks and two absent-config live Tailscale checks skipped; no runtime warnings or expected failures were recorded in the xcresult summary. Only the prescribed iPhone 17 Pro/iOS 26.5 simulator was used.

Fresh signed archive and export both exit 0. Artifacts are `/tmp/healthsync-6b3a049-qualification/HAHealthSync.xcarchive` and `/tmp/healthsync-6b3a049-qualification/export/HAHealthSync.ipa`. IPA SHA-256: `22105f57a127e061452a1cd3eca77983c095466273fd68af94f2a52a69e78ac9`. Archive and extracted IPA pass bundle verification and `codesign --verify --deep --strict` (exit 0); Apple Distribution: Maryna Vdovenko (`9XN7WN8JN2`), exact application identifier, HealthKit/background delivery, `get-task-allow=false`, and `beta-reports-active=true` were inspected with signing-service access. The exported profile is `HA Health Sync App Store 9XN7WN8JN2`. As before, sandbox-only signature inspection hid authority/entitlements; authorized inspection resolved that diagnostic. Build caches named `healthsync-387709d-qualification` were reused and rebuilt after the final source change; their names do not identify the final binary revision.

Website build retains the known notice: “Some routes could not be classified. vinext currently uses static analysis and cannot detect dynamic API usage (headers(), cookies(), etc.) at build time. Automatic classification will be improved in a future release.” `/`, `/privacy`, and `/support` are marked Unknown. Build succeeds; this classification limitation is recorded without claiming published rendering or deployed-copy acceptance.

No new screenshots, live purchases, device acceptance, portal changes, deployment, upload, or submission were performed in the final fix wave. Earlier screenshots remain limited historical review captures and do not show the new retry control. All external and physical-device handoff items below remain open.

Final-candidate reproduction uses the same commands below with archive/export/result paths under `/tmp/healthsync-6b3a049-qualification` (the result bundle is `tests.xcresult`). The final simulator build/analyzer used `-derivedDataPath /tmp/healthsync-387709d-qualification/simulator-derived`; final archive and unsigned Release rebuilds used the corresponding `archive-derived` and `unsigned-derived` caches. Fresh export used the same inspected export-only options. Both the archive and extracted IPA were checked with the bundle verifier and `codesign --verify --deep --strict`. The exported provisioning profile expires `2027-09-25T03:49:52Z`; final privacy manifest inspection declares no collection, tracking, tracking domains, or accessed API categories.

## Historical qualification of the superseded candidate

App-source candidate: `c8fa3b27e14c57fa2de3e8ccd2eda7664390890a`. Qualification changes only documentation. Artifacts are local under `/tmp/healthsync-c8fa3b2-qualification`; they are not uploaded or committed and may be removed by normal temporary-directory cleanup.

## Verified local gates

| Gate | Result |
| --- | --- |
| HealthSyncCore | Exit 0; 488 tests in 70 suites passed |
| Complete Xcode simulator suite | Exit 0; 338 total, 330 passed, 8 skipped, 0 failed |
| Simulator build and analyzer | Exit 0; both succeeded, App Intents metadata extracted |
| Strict recursive swift-format | Exit 0 |
| Layered icon verification | Exit 0; default, dark, tinted appearances compiled |
| App Store metadata verifier | Exit 0 |
| Website verify, lint, production build | Each exit 0 |
| Website production dependency audit | Exit 0; 0 vulnerabilities |
| Signed Release archive | Exit 0 |
| Unsigned iOS Release build and bundle verifier | Both exit 0 |
| Local App Store IPA export | Exit 0; destination was local export, no upload |
| Archive and exported IPA bundle/signature inspection | Exit 0 with signing-service access |

The Xcode plan used only the existing iPhone 17 Pro, iOS 26.5 (`D17101C9-01EB-488D-AFE1-58E6C089B853`). Its unit target ran 310 tests (302 passed, 8 skipped); the UI target passed all 28. Six skips were unavailable CoreSimulator file-protection metadata; two were absent ignored live-Tailscale configuration. No failure or unexpected skip was hidden. The result bundle is `authorized-tests.xcresult`.

Initial sandbox attempts failed because compiler caches, CoreSimulator, and signing trust services were inaccessible. Authorized reruns passed. In particular, the sandbox's `CSSMERR_TP_NOT_TRUSTED` / invalid-entitlements diagnostic disappeared when verification could access signing services; the authorized `codesign --verify --deep --strict` returned 0 for both archive and exported IPA. Initial npm audit DNS/cache failure also cleared on the authorized retry.

## Signed artifact

- Archive: `/tmp/healthsync-c8fa3b2-qualification/HAHealthSync.xcarchive`.
- IPA: `/tmp/healthsync-c8fa3b2-qualification/export/HAHealthSync.ipa`.
- IPA SHA-256: `10ebad9ca3f63f992fce63506f12ba7e02b61bc3396b7224340df8796c116987`.
- Identity: Apple Distribution: Maryna Vdovenko (`9XN7WN8JN2`); signature chain includes Apple Worldwide Developer Relations Certification Authority and Apple Root CA.
- Bundle: `com.marynavdovenko.HAHealthSync`, version `1.0.0 (1)`, minimum iOS 18.0, iPhone only.
- Embedded profile: `HA Health Sync App Store 9XN7WN8JN2`, expires `2027-09-25T03:49:52Z`.
- Archive and exported entitlements: exact team/application identifier, HealthKit and HealthKit background delivery enabled, `get-task-allow=false`, `beta-reports-active=true`.
- Bundle verifier confirmed `Assets.car`, `PrivacyInfo.xcprivacy`, `Metadata.appintents`, exact background identifier, and absence of local HTML prototypes. The privacy manifest declares no collected data, tracking, tracking domains, or accessed API categories.

This is local signature/export evidence, not Apple server validation, processed-build acceptance, installation on a physical device, or a successful live purchase. Existing historical IPA files were not used as candidate evidence.

## Screenshots and public endpoints

`onboarding.png` and `free-dashboard.png` were captured with deterministic `-ui-testing-onboarding` and `-ui-testing-dashboard -ui-testing-purchase-locked` launch arguments. Both were visually inspected: no credentials, server URLs, entity identifiers, personal readings, notifications, or owner details. Dashboard readings are synthetic fixtures. Status bars show only time, network, and battery. These are review captures, not submission-ready screenshots: the prescribed existing simulator produces 1206×2622, not the checklist's 1290×2796, and the pair does not cover the complete paid-feature disclosure/selection/settings flow. No resizing or new simulator was used.

Read-only HTTPS checks found the staging home, privacy, and support pages returned HTTP 200. The final `health-sync.olhapi.com` hostname failed DNS resolution (curl exit 6), so final-host HTTPS, canonical metadata, and policy availability are not qualified. Current candidate website changes were not published.

The browser inventory exposed no controllable browser tabs. A native-browser inspection stalled and was aborted; no authenticated App Store Connect record or agreement/price/product fields were inspected. No portal setting was changed.

## Required handoff

1. Account Holder: verify team/app record, Paid Apps Agreement, legal/trader status, tax and banking; private fields stay interactive.
2. With separately authorized portal configuration, confirm non-consumable `com.marynavdovenko.HAHealthSync.lifetimeUnlock`, Family Sharing off, exactly US $10.00, localization, review screenshot, availability, and first-IAP linkage to version 1.0.0. If exact price is unavailable, stop for a decision.
3. Finish synthetic screenshot coverage at the required dimensions. Publish current website and complete DNS/HTTPS only after separate authorization.
4. Validate through Apple's supported flow; authorize upload separately, wait for processing, and verify actual localized pricing, purchase, restore on another device, refund/revocation, and TestFlight behavior.
5. Complete signed clean-device Health consent, physical background observation, iOS 27 archive and installed-fork acceptance, privacy answers, review access, and all App Store warnings.

No agreements, financial fields, DNS, portal configuration, upload, distribution, submission, release, or production changes were performed. Integration, PR creation, or keeping the branch remain explicit choices; no merge or push was performed.

## Reproduction

Run from the candidate worktree. All shell invocations use the `rtk` wrapper; cache/simulator/signing/network access may require the approved execution context.

```sh
rtk swift test --package-path Packages/HealthSyncCore
rtk xcodebuild test -project HAHealthSync.xcodeproj -scheme HAHealthSync -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath /tmp/healthsync-c8fa3b2-qualification/authorized-tests.xcresult
rtk xcodebuild build analyze -project HAHealthSync.xcodeproj -scheme HAHealthSync -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
rtk xcrun swift-format lint --recursive --strict HAHealthSync Packages HAHealthSyncTests HAHealthSyncUITests
rtk bash Tools/verify-app-icon.sh
rtk node AppStore/verify-metadata.mjs
rtk xcodebuild build -project HAHealthSync.xcodeproj -scheme HAHealthSync -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/healthsync-c8fa3b2-qualification/unsigned-derived CODE_SIGNING_ALLOWED=NO
rtk bash Tools/verify-release-bundle.sh /tmp/healthsync-c8fa3b2-qualification/unsigned-derived/Build/Products/Release-iphoneos/HAHealthSync.app
rtk xcodebuild archive -project HAHealthSync.xcodeproj -scheme HAHealthSync -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/healthsync-c8fa3b2-qualification/HAHealthSync.xcarchive -derivedDataPath /tmp/healthsync-c8fa3b2-qualification/archive-derived CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=9XN7WN8JN2 CODE_SIGN_IDENTITY='Apple Distribution' PROVISIONING_PROFILE_SPECIFIER='HA Health Sync App Store 9XN7WN8JN2'
rtk xcodebuild -exportArchive -archivePath /tmp/healthsync-c8fa3b2-qualification/HAHealthSync.xcarchive -exportPath /tmp/healthsync-c8fa3b2-qualification/export -exportOptionsPlist /tmp/HAHealthSync-new-team-export/ExportOptions.plist
rtk xcrun xcresulttool get test-results summary --path /tmp/healthsync-c8fa3b2-qualification/authorized-tests.xcresult
rtk bash Tools/verify-release-bundle.sh /tmp/healthsync-c8fa3b2-qualification/HAHealthSync.xcarchive/Products/Applications/HAHealthSync.app
rtk codesign --verify --deep --strict /tmp/healthsync-c8fa3b2-qualification/HAHealthSync.xcarchive/Products/Applications/HAHealthSync.app
```

Website commands, run from `website`: `rtk npm run verify`, `rtk npm run lint`, `rtk npm run build`, `rtk npm audit --omit=dev`. Export options were inspected before use: method `app-store-connect`, destination `export`, manual signing, exact team/profile, symbol upload off. No `-allowProvisioningUpdates` was used.
