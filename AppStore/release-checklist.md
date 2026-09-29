# App Store release checklist — 1.0.0 (1)

Public contact: Oleh Vdovenko, o@olhapi.com

## Website and DNS

- [x] Home, Privacy, Support, and branded not-found routes are implemented.
- [x] Website source verification, lint, production build, and production dependency audit pass locally.
- [x] Public URLs in listing metadata use `health-sync.olhapi.com`.
- [x] Historical staging deployment exists at `https://ha-health-sync.oleh904119.chatgpt.site`; it predates the current lifetime-unlock website copy.
- [ ] Publish the current approved website copy after separate deployment authorization.
- [x] Register `health-sync.olhapi.com` with Sites and obtain its exact DNS validation records.
- [ ] Connect only `health-sync.olhapi.com` in Cloudflare after confirming the exact target and absence of a conflicting DNS record.
- [ ] Verify trusted HTTPS, final host, title, canonical metadata, and content at `/`, `/privacy`, and `/support`.

Pending Cloudflare records (DNS only; proxying should remain disabled until Sites reports the domain active):

- `CNAME health-sync` → `custom-domains.chatgpt.site.`
- `TXT _openai-site-verification.health-sync` → `openai-site-verification=iEvUdb4LFuWI5nz5nWu8Qq_Jqd45SlFq8Ju52T99ij0`
- `TXT _cf-custom-hostname.health-sync` → `bbc514b3-6dd9-4213-9339-397aaa6c9c0d`

## Apple Developer and App Store Connect

- [ ] Confirm the correct Apple Developer team and Account Holder authorization.
- [ ] Confirm or create the App Store Connect app record for `com.marynavdovenko.HAHealthSync`.
- [x] Confirm Apple Distribution certificate and App Store provisioning profile for the exact bundle ID.
- [x] Confirm HealthKit and background-delivery capabilities on the App ID and profile.
- [ ] Verify private App Review contact phone and email in App Store Connect; do not commit them here.
- [ ] Complete legal entity, Digital Services Act trader status, agreements, tax, and banking gates.
- [ ] Choose availability regions, release method, and pricing.

## Lifetime unlock product (external gates)

- [ ] Confirm the app record belongs to team `9XN7WN8JN2` and bundle `com.marynavdovenko.HAHealthSync`.
- [ ] Create the non-consumable `com.marynavdovenko.HAHealthSync.lifetimeUnlock`, with Family Sharing off.
- [ ] Confirm Paid Apps Agreement, tax, and banking with the Account Holder; private financial entry remains interactive.
- [ ] Select exactly US $10.00 in the US base region. If unavailable, stop for a decision; do not substitute another price.
- [ ] Prepare product localization, review screenshot, country availability, and first-purchase linkage to app version 1.0.0.
- [ ] Verify actual localized price, purchase, restore on another device, and refund/revocation with sandbox and processed TestFlight.
- [ ] Capture free manual sync and paid automatic/Shortcuts/history disclosure in screenshots. No subscription; StoreKit supplies the displayed price.
- [ ] Verify signed clean-device onboarding and Health consent. The new bundle is a distinct installed app; no in-place migration is claimed.

## Binary

- [x] Marketing version is `1.0.0` and build number is `1` in the project.
- [x] Re-run complete tests, strict formatting, analyzer, app-icon, and unsigned Release-build gates for the final lifetime-unlock candidate (`6b3a049`; see linked evidence).
- [x] Verify the unsigned Release bundle is `com.marynavdovenko.HAHealthSync` version `1.0.0 (1)`, iOS 18, iPhone-only, and excludes local HTML prototypes.
- [x] Produce a signed Release archive with the intended Apple Distribution identity and profile (candidate `6b3a049`; local export only).
- [x] Inspect archive bundle ID, version/build, signing authority, entitlements, privacy manifest, app icon, and App Intents metadata (candidate `6b3a049`; exported IPA also verified).
- [ ] Validate the archive in Organizer or with the supported App Store validation flow.
- [ ] Upload the archive only after explicit authorization.
- [ ] Wait for build processing and select build `1` for version `1.0.0`.

## Full-history archive release gate (development branch)

- [ ] Revalidate the privacy policy, App Privacy answers, review instructions, and screenshots against the exact binary if the iOS 27 archive feature is included. It creates a long-lived Home Assistant copy of original samples, while local reset and permission revocation do not erase it.
- [ ] Decide one authoritative uploader per Health Bridge user and test any intended multi-device ownership before claiming it is safe.
- [ ] Complete the [full-history verification record](../docs/full-history-archive-verification.md) and its [physical-device checklist](../docs/real-device-checklist.md): signed iOS 27 install, protocol-2/schema-2 installed capability, older-than-14-day originals, interruption/resume, boundary expansion, recorder purge, archive/raw export and multiyear-statistics readback.
- [x] The `2.1.1a1` fork at `2fe7916` passed the disposable installed Home Assistant Core 2026.9.3 container gate: schema 2, HAL/PAL/v1 compatibility, restart receipt idempotence, a configuration backup containing a restorable archive, recorder purge, raw/statistics readback, and two clean shutdowns.
- [ ] Confirm installation and clean operation on the intended Home Assistant deployment. HA OS/Supervisor restore and browser-rendered archive UI remain unverified; the native macOS/Python shutdown crash is separate. Confirm distribution from a reviewed fork source; no public HACS fork URL or install has been verified.
- [ ] Verify administrator-only archive browse/export, explicit archive deletion scope, configuration-inclusive backup and restore, and separate recorder/statistics/backup retention. Keep v1 fallback and medication behavior covered.

The 31 August 2026 evidence below is historical and predates archive work. The current Binary section refers to the separately linked lifetime-unlock qualification evidence; neither local qualification nor historical evidence authorizes App Store submission.

## Privacy

- [x] Public Privacy Policy describes HealthKit access, direct transfer, local storage, diagnostics, deletion, permissions, and contact.
- [x] App Privacy draft recommends no collection and records the reasoning and invalidation conditions.
- [ ] Recheck every source fact in `app-privacy.md` against the exact submitted build.
- [ ] Complete the App Privacy questionnaire in App Store Connect.
- [ ] Confirm the privacy-policy URL is live before saving or submitting metadata.

## Product page

- [x] English listing name, subtitle, description, keywords, categories, URLs, and copyright are drafted and locally validated.
- [ ] Confirm the app name is available in App Store Connect.
- [ ] Enter the verified English metadata and review the rendered product page.
- [ ] Complete age-rating questions.
- [ ] Complete the regulated-medical-device declaration accurately; the app must not be represented as medical diagnosis or treatment software.
- [ ] Choose promotional text only if needed; none is required for this package.

## Screenshots

- [ ] Capture 1–10 portrait PNG or JPEG screenshots at exactly 1290×2796 pixels for the 6.9-inch iPhone display class.
- [ ] Use only synthetic data and a non-private Home Assistant test environment.
- [ ] Cover onboarding/direct-data-flow context, dashboard status, metric selection, import pairing, and privacy/local-data controls as useful.
- [ ] Exclude credentials, tokens, webhook secrets, URLs, entity identifiers, personal health readings, notification content, and device-owner details.
- [ ] Check legibility, localization, status-bar content, and final pixel dimensions before upload.

## Review access

- [x] Reviewer guidance explains prerequisites, selected permissions, direct data flow, synthetic simulator data, background limitations, and deletion.
- [x] No demo account, server URL, access token, or webhook secret is committed.
- [ ] Decide whether Apple Review needs a dedicated reachable Home Assistant plus Health Bridge environment.
- [ ] If required, create a least-privilege review environment and enter its access details only in private App Review fields.
- [ ] Test the complete review instructions from a clean device or simulator.

## Compliance

- [ ] Answer export-compliance questions for the exact binary and its use of standard Apple networking/TLS.
- [ ] Confirm content-rights responses and HealthKit usage comply with current App Review requirements.
- [ ] Confirm no unlisted third-party SDK, tracking, advertising, or account behavior exists.

## TestFlight

- [ ] Upload and process the release candidate.
- [ ] Complete any beta review information required for external testing.
- [ ] Install the processed build from TestFlight and smoke-test onboarding, manual sync, Settings, Privacy Policy, diagnostics, and deletion.
- [ ] Record live Home Assistant and background-delivery observations separately from local regression gates.

## Submission

- [ ] Re-run metadata validation and all release gates on the exact final commit.
- [ ] Confirm every App Store Connect warning and required field is resolved.
- [ ] Confirm the selected build, screenshots, privacy answers, review access, availability, and release method with the Account Holder.
- [ ] Submit for Review only after explicit authorization.

## Local candidate evidence — 27 September 2026

Final qualification supersedes earlier pending-local-gate statements below: [exact candidate evidence](../docs/2026-09-27-lifetime-unlock-release-evidence.md) records 488 Core tests passed, 330 Xcode tests passed, 8 expected skips, zero failures; build/analyzer/format/icon/metadata/website gates passed. A signed Apple Distribution archive and local IPA export were produced and verified. No upload or Apple server validation occurred. Synthetic screenshots were visually inspected but are 1206×2622 and incomplete for submission; the 1290×2796 gate remains open. Final-host DNS failed, and authenticated App Store Connect access was unavailable. Portal, exact-price, legal, live-purchase, physical-device, TestFlight, and submission gates remain open.

- App, unit-test, and UI-test Debug/Release identifiers use Maryna's namespace and team `9XN7WN8JN2`. Background-task registration and Info.plist match. Internal storage, Keychain service, logs, and HealthKit origin markers are preserved.
- Read-only local metadata inspection found an Apple Distribution identity for Maryna's team and matching development/App Store profiles. Both grant HealthKit and background delivery; the App Store profile expires 25 September 2027 and disables get-task-allow. This does not prove live portal status, signing permission, export, or App Store Connect setup.
- Metadata validation, compiled layered-icon validation, unsigned iOS Release build, and exact-bundle validation passed. Focused HealthKit origin/background-refresh tests passed: 23 tests, zero failures or skips, existing iPhone 17 Pro iOS 26.5 simulator. Website source verification, lint, and production build passed. Full final-candidate tests and signed archive remain pending.
- Updated listing, review instructions, HealthKit purpose string, and local website privacy/support source disclose lifetime unlock and durable archive retention. Publication and final HTTPS checks remain pending.
- Preserve old certificates, profiles, and installed app. Signed archive, sandbox/TestFlight, physical-device acceptance, and submission remain separate gates.

## Verified evidence — 31 August 2026

- HealthSyncCore: 223 tests in 49 suites passed.
- Xcode app/UI plan on iPhone 17 Pro simulator: 192 passed, 0 failed, and 5 expected skips because CoreSimulator did not report iOS data-protection metadata.
- Strict Swift formatting, Xcode static analysis, app-icon verification, website verification/lint/build, metadata validation, and the production dependency audit passed.
- Sites origin `/`, `/privacy`, and `/support` returned HTTP 200; the unknown-route check returned HTTP 404 as designed.
- Cloudflare DNS remains pending because the available browser and CLI sessions are not authenticated. Sites requires a CNAME plus two TXT validation records before TLS can activate.
- Historical signing state on 31 August: no Apple Distribution identity or App Store profile was available then. Superseded by the local metadata inspection above; no signed candidate/export is claimed.
