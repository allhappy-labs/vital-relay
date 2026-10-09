# Setup

## Requirements

- macOS with the current installed Xcode toolchain;
- iOS 18 or newer;
- Health Bridge for live sync; the reviewed local `2.1.1a1` fork based on upstream v2.1.0 for protocol-2 archive import;
- no third-party Swift packages;
- for this workspace, use only the already-installed `iPhone 17 Pro` simulator on iOS 26.5.

## Credentials

Vital Relay deliberately uses two credentials that are not interchangeable:

1. **Health Bridge webhook secret** — the secret entered while configuring the Health Bridge integration. It is sent only inside requests to `/api/webhook/health_bridge`.
2. **Home Assistant long-lived access token** — generated from the Home Assistant user profile. It is sent only as `Authorization: Bearer <token>` to authenticated Home Assistant REST endpoints.

Both values are stored as separate generic-password records in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. They are not stored in app configuration, UserDefaults, SwiftData, logs, screenshots, fixtures, or crash text.

## Onboarding

1. Review the privacy explanation.
2. Select only the Apple Health metrics to share. They are grouped as Activity, Body Measurements, Vitals, Sleep, and Other. Changing this later requests authorization only for newly selected types; removing a selection needs no new HealthKit prompt.
3. Request Health access for the selected types.
4. Enter the Home Assistant base URL and the Health Bridge user ID.
5. Enter the webhook secret and test the Health Bridge webhook.
6. Enter the long-lived access token and test the authenticated API.
7. Save the connection and run Sync Now.
8. Optionally open Settings → Home Assistant → Apple Health to configure inbound pairings and request write access only for those destinations.

The webhook test creates the notification implemented by Health Bridge. Each connection result is shown separately so an invalid integration secret cannot be confused with an invalid Home Assistant token.

After onboarding, Settings → Edit Connection changes the base URL or Health Bridge user ID without exposing stored credentials. Leaving either secure field blank preserves that Keychain value; entering a value replaces it and enables its corresponding connection test.

## Live metric behavior

The initial registry contains 34 selectable Health Bridge metrics:

| Category | Metrics | Health Bridge output |
| --- | --- | --- |
| Activity | Steps, walking/running distance, active calories, basal calories, flights climbed, exercise time, stand time, time in daylight | count, metres, kcal, floors/count, minutes, and daylight seconds |
| Body Measurements | Body mass, height, body fat percentage, lean body mass | kg, metres, fractional percentage, kg |
| Vitals | Heart rate, resting heart rate, walking heart rate average, HRV, blood oxygen, respiratory rate, VO2 max, wrist temperature | bpm, milliseconds, fractional percentage, breaths/min, mL/kg/min, degrees Celsius |
| Sleep | Total, REM, core, deep, awake, and unspecified sleep; sleep start; wake time; latest sleep detail | duration in seconds, Unix timestamps, and Health Bridge stage code |
| Other | Mindful minutes, dietary water, dietary energy, blood glucose, last Apple workout | mindful duration in seconds, mL, kcal, mmol/L, and the versioned workout object |

The Health Bridge identifiers containing `*_hours` are historical names: the app deliberately sends sleep durations in seconds because the integration performs the seconds-to-hours conversion. Percentages are fractions from 0 through 1, not values from 0 through 100.

Daily totals use the device calendar's local-midnight boundaries. The next boundary is calculated by adding one calendar day, so daylight-saving days can correctly span 23 or 25 hours. Duplicate HealthKit sample UUIDs are removed. Samples from all HealthKit sources, including user-entered samples, participate unless they were written by Vital Relay itself; excluding this app's source prevents an imported Home Assistant value from being immediately exported back.

Overlapping sleep and mindful intervals are unioned before their duration is calculated. Detailed sleep stages are mapped explicitly rather than forwarding Apple's enum raw values. The workout metric sends only the latest workout and omits unavailable optional statistics.

Each metric has an independent HealthKit query anchor. A candidate anchor is committed only after Health Bridge returns a matching versioned acknowledgement with `ok: true`, `applied: true`, and a positive updated-entity count. Retryable failures use bounded exponential backoff with jitter while permanent authentication, validation, TLS, and protocol failures are not retried.

Deletion handling is conservative. A deletion followed by a replacement recomputes and sends the replacement; an emptied cumulative metric sends zero. When deleting the only latest sample leaves no authoritative value, the app reports a compatibility failure and preserves the previous anchor because the live Health Bridge contract has no deletion sentinel. Resetting local synchronization state or historical reconciliation will be needed once that workflow is implemented.

## Home Assistant to Apple Health pairings

Inbound pairings are independent from outbound metric selection. Creating or enabling a pairing never selects the equivalent Apple Health → Home Assistant metric. Enabled pairings run during Sync Now, the App Shortcut, and every automatic background run. Saving to Apple Health works while iPhone is locked, so imports can complete even when exports are deferred.

Each pairing contains a lowercase Home Assistant entity ID, one writable HealthKit destination, the source unit reported by Home Assistant, HealthKit's fixed native destination unit, an optional bounded transform, and an enabled state. Write authorization is a separate explicit action and requests only destinations used by configured pairings.

The current writable allowlist is:

- body mass, height, body-fat percentage, lean body mass, and body temperature;
- heart rate, blood oxygen, respiratory rate, and UV exposure;
- dietary water, energy, carbohydrates, fat, and protein;
- blood glucose and insulin delivery.

Read-only, Apple-computed, clinical, sleep, workout, medication, and unverified types are hidden. The source-backed rationale and installed-SDK evidence are recorded in [healthkit-write-allowlist.md](healthkit-write-allowlist.md).

For each enabled pairing, the app fetches `GET /api/states/<entity_id>` with the long-lived access token. It rejects empty, nonnumeric, `unknown`, `unavailable`, and `none` states; mismatched units; missing units except for an explicitly unitless source such as UV index; non-finite transformations; and values outside destination-specific plausible bounds. Supported transformations are identity, multiply, add, and multiply-plus-add. The transformed value is converted through typed units into HealthKit's native unit.

The sample timestamp is Home Assistant's `last_updated`. A stable SHA-256-derived sync identifier/version is placed in Apple's HealthKit sync metadata, plus an application origin marker containing no entity or value. A per-pairing checkpoint is committed only after HealthKit confirms the save. Exact repeated state is skipped; a failed or cancelled save retains the old checkpoint. If checkpoint persistence fails after a confirmed save, retrying is safe because the same HealthKit sync identity is reused.

Outbound HealthKit queries exclude both this app's HealthKit source and its Home Assistant origin marker. This prevents an imported state from cycling through the Health Bridge webhook. Pairing checkpoints and definitions use protected, atomic, backup-excluded local files; fetched raw state is not persisted.

## URL security

- Remote Home Assistant and Home Assistant Cloud addresses must use HTTPS.
- Plain HTTP can be enabled only after acknowledging a security warning and only for a loopback, link-local, RFC1918, unique-local IPv6, `.local`, Tailscale MagicDNS `host.tailnet.ts.net`, or Tailscale `100.64.0.0/10` host.
- Public HTTP, URL credentials, malformed URLs, and misleading `.local.example.com` suffixes are rejected.
- TLS certificate validation is never disabled. Self-signed certificates are not silently trusted.
- Reverse-proxy base paths are preserved while `/api/`, `/api/states/...`, and `/api/webhook/health_bridge` are appended safely.

## Privacy model

Data flows directly from Apple Health on the iPhone to the configured Home Assistant instance. The app has no external service. Configuration and checkpoint files use iOS file protection and are excluded from backup. Ordinary synchronization does not persist request bodies or readings locally. Optional protocol-2 archive import deliberately creates a durable server-side copy of selected original samples, as described below.

## Experimental historical import

On iOS 27 or later, a successful protocol-2 capability probe against the compatible fork enables **All readable history**. The current fork advertises archive schema 2, 107 directly readable metrics from 99 source types, and independent archive/statistics availability. Its 101 numeric metrics project to hourly long-term statistics; six metrics remain available as original-sample timeline records only. The 19 mappings added since upstream v1.2.1 are listed in [the protocol contract](health-bridge-protocol.md). A supported server metric is still omitted if its HealthKit type is unavailable on this device. The app scans each type's own readable boundary; an absent boundary or empty query cannot identify whether read access was granted or denied. A limited boundary can be expanded later, and the app resumes older intervals. If it cannot prove the boundary for deletion reconciliation, it pauses tombstones and reports reconciliation required.

Protocol 2 sends original quantity, category, and workout samples with UUID, time interval, source and unit/detail provenance. The fork stores them in `<HA config>/.storage/health_bridge_archive.sqlite`, outside ordinary recorder purge, and projects statistics separately. An archive commit acknowledgement means the originals are durable; wait for separate `statistics current` status and readback before treating trends as complete. The archive has no automatic retention period and can grow substantially with dense multiyear samples. Protect Home Assistant configuration, backups, and exports. Use a configuration-inclusive Home Assistant backup; the fork's pre-backup hook checkpoints SQLite WAL, and a restore must be checked with the matching fork. JSON Lines export is an inspection format, not a complete restorable database backup. The fork's `docs/archive-operations.md` describes installation, backup, restore, and rollback. A disposable Home Assistant Core 2026.9.3 container passed install, backup containing a restorable archive, recorder purge, raw/statistics readback, and clean shutdown at fork `2fe7916`; public HACS delivery, HA OS/Supervisor restore, production installation, and phone-connected import remain unverified. The separate native macOS/Python shutdown crash is still open.

Archive browsing and JSON Lines export require an authenticated Home Assistant administrator. The archive card requires explicit user-scoped confirmation to delete that user's originals, tombstones, receipts, coverage, and pending projection work. It does not delete recorder history/statistics, Apple Health, backups, or downloaded exports. Local reset and local-data deletion clear archive progress but leave server data. Revoking HealthKit access also leaves already archived data. Only one authoritative uploader should be selected for a Health Bridge user until multi-device ownership is decided and verified.

On iOS 18–26, or when protocol 2 is unavailable, the app retains its existing protocol-1, latest-14-days recorder import behavior. Live synchronization remains available. Existing recorder rows cannot be reconstructed into original HealthKit samples.

Historical import is off by default and requires an explicit warning confirmation. Protocol-1 fallback uses a capability probe, selects eligible metrics, creates their live entities first, requires a matching `committed: true` acknowledgement, and preserves checkpoints on failure. It writes recorder history only, subject to the installed integration's negotiated limits.

An incompatible recorder or schema disables only the protocol-1 historical-import action. See [health-bridge-protocol.md](health-bridge-protocol.md) for the wire contracts.

## Medications on iOS 26 or newer

Settings → Medications presents Apple's per-object authorization flow. Vital Relay reads only approved medication concepts and their dose events. It cannot create medications or dose events, and medication is never offered as a Home Assistant → Apple Health destination. Authorized names are displayed only while the medication screen is open and are then discarded; protected checkpoints contain opaque app-derived identifiers and the HealthKit anchor, not names or dose values.

## Diagnostics and local data

Diagnostics export is allowlist-first: app/build/OS and protocol versions, feature and connection booleans, counts, timestamps, and error categories only. It excludes base URLs, entity IDs, credentials, request/response bodies, and health values, then redacts the serialized document again before export.

Reset Synchronization State removes anchors, inbound/backfill/medication checkpoints, and status history while preserving connection configuration, selected metrics, pairings, and both Keychain credentials. Delete All Local App Data additionally removes those settings, pairings, and credentials and returns to onboarding. Both actions require two confirmations and neither deletes Apple Health samples, Home Assistant entities, or recorder history.

## Shortcut and background behavior

The App Shortcut phrase is “Sync Health with Home Assistant.” It runs the same shared bidirectional coordinator as Sync Now, is never throttled, and has a 25-second budget. A run with nothing new reports “Nothing new to sync.”; a locked iPhone reports “Unlock iPhone to read Apple Health.”

Background Sync offers one global frequency for both directions: Responsive (5 minutes), Balanced (15 minutes, default), Battery Saver (1 hour), or Daily (24 hours). Automatic runs may start up to `min(10 minutes, 20%)` early, so Battery Saver runs are allowed after 50 minutes. That keeps hourly HealthKit deliveries from being skipped.

Background work is owned by a launch-time runtime, not the dashboard. It registers App Refresh, installs HealthKit observers, and always submits the next App Refresh request after every run from any trigger while background work is enabled. After a locked-device, offline, timeout, DNS, lost-connection, out-of-time or cancelled run, the next request is `min(15 minutes, interval)` away; otherwise it is the next eligible time. After an offline, timeout, DNS, lost-connection, out-of-time or cancelled run, automatic runs are allowed again after that retry interval less its 20% tolerance (12 minutes for Balanced and slower presets) instead of the full frequency; after a locked-device run the next automatic run is never held back. A run left in flight by a killed app is recorded as interrupted on the next launch and counts as cancelled for this same retry allowance, so the app does not wait out the full interval before trying again. HealthKit runs have 18 seconds and App Refresh runs 25 seconds. Ordinary HealthKit wakes sync only the metrics whose type changed plus any selected metric not checked in the last hour; a full sweep of every selected metric runs once four times your Background Sync interval — at least 30 minutes and at most a day, so 30 minutes on Responsive, an hour on Balanced, four hours on Battery Saver and a day on Daily has passed since the last one, before any full sweep has ever completed (a fresh install, or right after resetting local data), after the local day changes, whenever HealthKit does not report which types changed, and for Background App Refresh, Sync Now, pull to refresh, and Shortcut runs. A daily total refreshes once after local midnight even without a new sample — the refresh is keyed to when that metric was last checked or sent, not to when it is queried, so it is not repeated later the same day — and medication sync runs on full sweeps, not on scoped runs. Changed metrics are sent in one Health Bridge request of up to 50 keys.

iOS decides when background work actually runs. Apple Health cannot be read while iPhone is locked, Low Power Mode pauses Background App Refresh, and swiping the app away in the app switcher stops background launches until the app is opened again. Settings → Background Sync → System shows Background App Refresh, Low Power Mode, the earliest next automatic sync and the last automatic attempt.

For more frequent runs, create Shortcuts **Time of Day** automations that run “Sync Health with Home Assistant” (Settings → Background Sync → Sync more often with Shortcuts).

**Sync attempt sensor (optional).** Settings → Background Sync → Publish sync attempts to Home Assistant writes `sensor.health_bridge_sync_attempt_<user>` through `POST /api/states` after every attempt, including no-change, locked and interrupted ones. Its state is the attempt start time; attributes are the trigger, outcome, counts, first failure category, duration and skipped wake-ups. No health values are sent. Home Assistant requires an administrator's long-lived token for this endpoint, and states written this way disappear after a Home Assistant restart until the next attempt.
