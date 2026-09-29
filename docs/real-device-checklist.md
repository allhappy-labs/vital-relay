# Real-Device Verification Checklist

**Status:** Partially run. A signed physical-device build, install, entitlement check, launch, confirmed Tailscale HTTP connection, manual live synchronization, and bounded historical import passed on 2026-08-28; see the [physical-device verification evidence](physical-device-smoke-verification.md). Items below remain unverified unless individually checked.

**Full-history status (26 September 2026):** The iOS 27 original-sample archive path has not been tested on the available physical iOS 27 device. The schema-3 authoritative-uploader fork at `863a371` passed 265 tests and a disposable installed Home Assistant Core 2026.9.3 gate with all 16 checks and two clean shutdowns. The app feature source through `ee71bbb` passed 481 Core tests and a full existing iPhone 17 Pro/iOS 26.5 simulator run (306 passed, eight skipped). Target Home Assistant installation, Maryna signing integration, and phone-connected import remain untested. The separate native macOS/Python shutdown crash remains open. See [full-history verification](full-history-archive-verification.md). The checklist below for older live/backfill behavior does not close these new gates.

Do not describe HealthKit background synchronization as reliable until the background matrix below has run continuously for at least 24 hours on a physical iPhone with a real, unmodified Health Bridge installation.

## Preparation

- [ ] Record the app commit, iPhone model, iOS version, Home Assistant Core version, Health Bridge version, network path, timezone, and test start/end times without recording URLs, credentials, or health values.
- [x] Confirm the signed build contains the HealthKit and HealthKit background-delivery entitlements. The declared Background App Refresh mode and task identifier remain covered by build-time tests; actual scheduling remains unchecked below.
- [ ] Use synthetic/non-sensitive test values where practical and remove them after verification.
- [ ] Confirm diagnostics and device logs contain no tokens, webhook secrets, URLs with query data, Home Assistant response bodies, or health values.

## Installation and permissions

- [x] Build, sign, install, and launch version `0.1.0` build `1` on a physical iPhone 14 running iOS 26.6 without downloading a simulator runtime, package dependency, Xcode component, or asset.

- [ ] Fresh installation reaches the privacy explanation before any HealthKit request.
- [ ] Approving only part of the selected HealthKit types leaves other metrics safely skipped without claiming they were denied.
- [ ] Denying every requested read permission leaves anchors intact and provides a non-sensitive HealthKit failure or no-data result.
- [ ] Adding a metric later requests only the newly selected HealthKit type.
- [ ] Removing a metric stops its observer/delivery registration without deleting its committed anchor.
- [ ] Reviewing or re-requesting permissions opens the supported Health flow and does not infer read denial from empty data.

## Connections and manual synchronization

- [ ] A valid remote HTTPS or Home Assistant Cloud URL passes both independently labeled connection tests.
- [ ] A confirmed RFC1918 or `.local` plain-HTTP URL shows the security warning and then connects on the local network.
- [x] An explicitly confirmed Tailscale MagicDNS plain-HTTP URL resolves to an allowlisted tailnet address and connects without disabling TLS validation globally.
- [ ] A public plain-HTTP URL remains rejected.
- [x] Manual Sync Now applies selected data through the unmodified Health Bridge webhook and only then advances each anchor.
- [ ] Pull-to-refresh uses the same coordinator and produces an equivalent privacy-safe report.
- [ ] Home Assistant unavailable, offline, DNS failure, timeout, TLS failure, HTTP 429, and HTTP 5xx remain correctly classified and preserve anchors.
- [ ] An invalid webhook secret fails only the Health Bridge test/sync path.
- [ ] An invalid, expired, or revoked long-lived access token fails only the authenticated Home Assistant API test.
- [ ] A 200 response with `applied: false`, mismatched request ID/version, zero updated entities, or skipped entities is not reported as success.

## Shortcut

- [ ] The device build sets `ENABLE_DEBUG_DYLIB=NO`. Without it, App Intents metadata is skipped at build time and Shortcuts cannot find or run the App Shortcut (this happened on 14 Sep).
- [ ] Shortcuts discovers “Sync Health with Home Assistant.”
- [ ] The phrase “Sync Health with Home Assistant in HA Health Sync” invokes the shortcut.
- [ ] Shortcut success returns only synchronized metric and pairing counts.
- [ ] Shortcut failure returns only a concise category and exposes no metric value, URL, token, secret, or response body.
- [ ] Manual, pull-to-refresh, background, and Shortcut triggers all use the same anchors and do not overlap the same metric transaction.

## Background observation for at least 24 hours

- [ ] Enabling background synchronization registers each selected supported metric and shows the frequency disclaimer that iOS may run later.
- [ ] Responsive, Balanced, Battery Saver, and Daily persist as 5-minute, 15-minute, 1-hour, and 24-hour minimum intervals; an existing configuration defaults to Balanced.
- [ ] Each eligible observer or refresh trigger runs outbound metrics and inbound pairings once and records one combined value-free event.
- [ ] Sync Now and Shortcuts run immediately inside the selected interval and reset the next automatic eligibility.
- [ ] Observer delivery after new HealthKit data triggers an incremental sync while the app is not foregrounded.
- [ ] A locked phone after first unlock can access device-only Keychain credentials and protected checkpoints when iOS grants execution.
- [ ] A short background window or expiration completes the observer/BGTask callback, cancels work, and preserves uncommitted anchors.
- [ ] Home Assistant downtime during background work records a value-free failure; later observer/manual work catches up from the retained anchor.
- [ ] Network changes between Wi-Fi, cellular, offline, and restored connectivity do not corrupt or skip anchors.
- [ ] Multiple/duplicate observer events for one HealthKit type coalesce and every observer completion handler runs exactly once.
- [ ] After every run (observer, refresh, Shortcut, Sync Now), a new App Refresh request is submitted: at the next eligible time, or about 15 minutes later after a locked/offline/timeout/out-of-time run; Settings shows it as “Not before …”.
- [ ] Force-quitting does not corrupt local state; document that iOS may suppress relaunch until the user opens the app again.
- [ ] Disabling background synchronization stops observer queries, disables HealthKit background delivery, cancels the refresh request, and preserves anchors.
- [ ] Per-metric registration states, last attempt, last success, last failure, and combined exported/imported recent event counts match observed behavior without showing values or pairing IDs.
- [ ] Cold background App Refresh launch (terminate with `devicectl`, not the app switcher) records an `appRefresh` event, leaves no in-flight marker, and submits the next request (Console, subsystem `com.olhapi.HAHealthSync`, category `background`).
- [ ] A run iOS suspends or ends is shown as “Interrupted” after the next launch.
- [ ] A run with several changed metrics produces one Health Bridge request and one Last Sync Time record.
- [ ] With the sync attempt sensor enabled using an administrator token, `sensor.health_bridge_sync_attempt_<user>` updates on a no-change run; with a non-admin token the switch stays off with the administrator message.
- [ ] A Shortcuts Time of Day automation runs “Sync Health with Home Assistant” without a prompt; record the exact option labels iOS 26 shows.
- [ ] Over a day of runs, scoped Health-update runs finish in under 5 seconds and export their changes, while full sweeps of every selected metric still happen once four times the configured Background Sync interval has passed (an hour on Balanced, four hours on Battery Saver).
- [ ] Home Assistant shows a record for every run that exported something, scoped or full sweep.
- [ ] A daily metric refreshes after local midnight even when no new sample was recorded.
- [ ] The starved count in Recent Sync Events (and `starved=` in the background log) stays at 0 across a full day of otherwise-healthy runs; there is no Settings row for it.
- [ ] Medication sync (when enabled) runs on a full sweep.

## Calendar, correction, and deletion behavior

- [ ] Changing timezone causes the next daily query to use the new local-calendar boundary without duplicating retained samples.
- [ ] Spring-forward and fall-back days use actual 23-hour and 25-hour local-day intervals.
- [ ] A corrected/deleted sample with a remaining replacement recomputes and publishes the authoritative value.
- [ ] Deleting the final cumulative sample publishes zero and commits the anchor.
- [ ] Deleting the final latest-value sample reports the documented compatibility limitation and retains the old anchor.

## Home Assistant to HealthKit

- [ ] A supported writable destination accepts a valid Home Assistant entity state using its `last_updated` timestamp.
- [ ] Write authorization requests only explicitly configured destinations; partial or denied write access fails safely.
- [ ] A duplicate Home Assistant state is not written twice, including after a checkpoint-write retry.
- [ ] A changed timestamp or normalized value creates one new HealthKit sample and advances only that pairing's checkpoint.
- [ ] An imported sample is excluded from outbound synchronization, preventing a feedback loop.
- [ ] Unknown, unavailable, empty, nonnumeric, wrong-unit, implausible, and read-only destinations are rejected.
- [ ] Two enabled pairings progress independently when one entity is unavailable or unauthorized.
- [ ] Deleting a pairing requires confirmation and removes its checkpoint without changing outbound metric selection.

## Experimental history and medications

### iOS 27 original-sample archive acceptance — open

- [ ] On the target instance, submit a claim from the intended iPhone, compare its 12-hex fingerprint with the HA administrator archive card, approve it explicitly, and verify a second phone cannot import or enumerate UUIDs. A replacement must use a separately confirmed transfer; old-phone-only originals must remain visible but unavailable to absence-based deletion.
- [ ] Record app SHA, fork SHA, Home Assistant Core/Python versions, iOS version, selected metric/type counts, authorization choices and observed per-type readable boundaries, without URLs, identifiers, health values, credentials, or device serials.
- [ ] Install a signed development app build on the available iOS 27 device and connect it to the reviewed schema-3 `2.1.1a1` fork. Confirm protocol 2, `ownership_contract_version: 1`, archive schema 3, approved owner generation, supported types, and separate archive/statistics availability from the installed capability response.
- [ ] Import chosen original quantity/category/workout samples older than 14 days; verify UUID-distinct samples, including same-time records, in the authenticated archive view/export. Confirm numeric hourly statistics by readback and browse six timeline-only metric families without claiming numeric projections for them.
- [ ] Interrupt and restart both app and Home Assistant during import; verify exact committed acknowledgement, checkpoint resume, idempotent retries, no duplicates, and separate `samples archived` / `statistics current` states.
- [ ] Replace the authoritative phone only with HA-admin approval. Verify the old phone gets a typed revocation state and retains its pending journal, the new phone cannot replay old-phone checkpoint samples, a new readable UUID re-upload changes generation once, and only then can that phone delete it. Confirm reset keeps the device-only credential while complete local deletion removes it and requires a new transfer.
- [ ] Expand one HealthKit type's readable boundary backward and verify the newly readable interval is imported without erasing prior coverage. Where the API returns no boundary or no samples, record an ambiguous no-data result; do not infer full read or denial. Verify absence-based tombstones pause until a boundary is proved.
- [ ] Purge only the disposable test instance's ordinary recorder history, then retrieve exact original samples and multiyear statistics independently. Verify a configuration-inclusive backup and restore; preserve archive SQLite/WAL consistency. Check administrator-only export and explicit user-scoped archive deletion separately from recorder/statistics/backups.
- [ ] Verify iOS 18–26 or a protocol-1-only integration retains the latest-14-days recorder import and live sync. Verify medication authorization and dose events remain in their separate opt-in flow.
- [ ] Attach redacted counts, timestamps, commands, test artifacts and failure categories to the verification record. Verify the target Home Assistant installation and phone-connected path before claiming release readiness; the disposable container pass is recorded separately.

- [ ] Enabling historical import requires the explicit experimental warning and a successful capability probe.
- [x] A compatible SQLite recorder on schema 53 commits selected eligible metrics within the 14-day limit only after each live entity is processed. The protected checkpoint store recorded 16 committed metrics; the UI reported 370 committed points.
- [ ] Metrics with fewer than two eligible points appear under “Skipped (no eligible history)” without setting an error; genuine import errors remain under “Failures.”
- [ ] Unsupported database/schema, invalid limits, and recorder commit failure do not advance historical checkpoints or break live sync.
- [ ] A retry of an already committed backfill request is accepted as committed even when every point is reported skipped.
- [ ] On iOS 26 or newer, the Apple sheet permits selecting individual medications and the app reads only the approved objects and dose events.
- [ ] Medication names disappear from app state after leaving the medication settings screen and never appear in diagnostics or logs.
- [ ] Edited/deleted dose events are reconciled through the medication anchor without advancing a failed webhook checkpoint.
- [ ] Medication types remain unavailable as Home Assistant → Apple Health destinations.

## Privacy, diagnostics, and destructive actions

- [ ] Editing the connection never reveals either stored Keychain credential; blank secure fields preserve existing values.
- [ ] Exported diagnostics contain no base URL, entity ID, webhook secret, bearer token, request/response body, IP address, or health value.
- [ ] Reset Synchronization State requires two confirmations, clears every checkpoint/status store, preserves settings/pairings/credentials, and may resend current data.
- [ ] Delete All Local App Data requires two confirmations, stops background work, removes all three exact Keychain records (webhook, API token, and device-only archive uploader), removes protected app files, warns that archive access will require an administrator transfer, and returns to onboarding.
- [ ] Neither destructive action deletes Apple Health samples, Home Assistant entities, or recorder history.

## Completion record

- [ ] Attach a redacted summary containing pass/fail per item, observation duration, app commit, environment versions, and non-sensitive failure categories.
- The 19–21 September 2026 observation of the scoped-change-detection work is recorded in `scoped-sync-device-observation.md`, including the items it did not exercise.
- [ ] Keep any failure open; do not replace it with a simulator result.
- [ ] Only after every applicable item passes over at least 24 hours, update documentation to state the exact tested conditions rather than promising a universal schedule.
