# Privacy and security model

Vital Relay has no account system, analytics, advertising, remote logging, external backend, cloud database, or third-party dependency. Health data travels directly between Apple Health on the iPhone and the Home Assistant base URL chosen by the user.

## Data flow

Apple Health → Home Assistant reads only selected HealthKit types, aggregates in memory, sends a versioned request directly to the Health Bridge webhook, verifies its acknowledgement, and then commits the corresponding anchor. Home Assistant → Apple Health fetches only configured entity IDs with the long-lived access token, validates and converts the state in memory, writes an allowlisted HealthKit sample, and then commits a duplicate-prevention checkpoint.

Raw health readings, webhook bodies, Home Assistant response bodies, medication names, and imported entity values are not persisted for ordinary synchronization. Protected checkpoints contain only the minimum opaque identity, timestamp, normalized checkpoint value, or encoded HealthKit anchor necessary for correctness.

The optional iOS 27 full-history import has a different retention boundary. It sends selected original quantity, category, and workout samples directly to the compatible Health Bridge fork. The app retains protected coverage, anchor, and authorization-boundary metadata plus one complete bounded, token-free pending raw batch, including its original samples, provenance, and deletions. This journal permits an exact retry after a lost acknowledgement; the pending raw batch is removed after a verified acknowledgement is committed locally or local synchronization state is reset. A non-secret uploader fingerprint and approved owner generation bind restored checkpoint work to the phone and approval epoch that created it; a replacement or later reapproved phone must not replay stale samples it cannot verify. The fork keeps long-lived originals, provenance, tombstones, receipts, and projection state in a dedicated SQLite archive outside recorder retention. Administrators and configuration backups can access those records. The archive has no automatic expiration. Its authenticated administrator export is plaintext JSON Lines and must be protected separately. Numeric hourly statistics are derived in Home Assistant; six timeline-only metrics have no numeric statistic. Existing recorder samples cannot be turned back into originals.

If the optional sync attempt sensor is enabled, the app also writes one Home Assistant state, `sensor.health_bridge_sync_attempt_<user>`, with the access token after each attempt. It contains only a timestamp, trigger, outcome, counts, a failure category, duration and a skipped-wake count, and it goes only to the configured Home Assistant.

## Purchases

Manual sync is free. A non-consumable lifetime unlock enables automatic sync, Shortcuts sync, and historical imports. Apple handles purchase and Restore Purchases through StoreKit. Verified entitlements stay on device; transaction payloads are not sent to a developer server or included in diagnostics. The app does not handle payment-card data. Loss of entitlement stops future paid work but does not delete the durable copy in the user's Home Assistant archive. Export, deletion, privacy controls, and Health permission revocation remain available without purchase.

## Credentials and transport

The Health Bridge webhook secret and Home Assistant long-lived access token are separate generic-password Keychain records using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The webhook secret is used only in the webhook JSON body. The access token is used only in `Authorization: Bearer` for authenticated REST requests.

Remote addresses require HTTPS. Plain HTTP is limited to explicitly confirmed loopback, link-local, RFC1918, unique-local IPv6, or `.local` hosts. TLS validation is never disabled and self-signed certificates are not silently accepted. URL user-info is rejected.

## Local storage

Configuration, selections, pairings, query anchors, legacy import checkpoints, medication checkpoints, and bounded privacy-safe status events are stored under Application Support with `completeUntilFirstUserAuthentication` file protection, atomic replacement, and backup exclusion. Protocol-2 archive checkpoints and the single pending raw batch instead use `.completeFileProtection`, atomic replacement, and backup exclusion; they require protected data to be available, including after the first unlock. Acknowledged originals are not retained locally. The app does not use UserDefaults, SwiftData, iCloud documents, CloudKit, or a cloud database for these records.

## Logging and diagnostics

OSLog messages contain event categories and counts only. They do not contain URLs, IP addresses, entity IDs, authorization headers, tokens, secrets, response bodies, medication names, or health values.

Diagnostics are constructed from an explicit allowlist: app/build/OS and protocol versions, boolean feature/connection states, counts, timestamps, and error categories. Stored credentials are read only to seed a final redaction pass and are never inserted into the report. URL, authorization, credential, state/value, entity-ID, and IP patterns are redacted defensively.

Background logs use the `background` category and record launches, expiry, submissions, eligibility and interrupted attempts without values.

## Permissions

Onboarding requests read permission only for selected metrics. Settings requests write permission only for destinations used by configured pairings. Read-only and Apple-computed types are excluded from the write selector. On iOS 27, full-history discovery uses each selected HealthKit type's own earliest readable boundary. A missing boundary or no returned samples cannot distinguish full access from denied read access, so the app does not label either as denial. A changed boundary may require rescanning older intervals; absence-based archive tombstones pause when the readable boundary cannot be proved. On iOS 26 or newer, medications use Apple's separate per-object authorization sheet and remain read-only; they are outside the original-sample archive.

## Removal

Reset Synchronization State preserves configuration, pairings, and all three credentials while clearing synchronization checkpoints/status. Delete All Local App Data removes app configuration, pairings, checkpoints/status, the webhook/API Keychain records, and the device-only archive uploader Keychain record. Both clear local archive progress. Neither operation deletes Apple Health samples or any Home Assistant data. The fork permits version-2 archive writes and UUID inventory only from the one HA-administrator-approved iPhone for each Health Bridge user. A replacement needs an explicit administrator-approved transfer; the old phone loses archive access, while its originals remain archived until the new phone re-uploads individual readable UUIDs before any deletion. Losing the device-only credential, including through complete local deletion, requires that transfer before archive import resumes. An authenticated Home Assistant administrator must separately confirm user-scoped archive deletion in the fork's archive card. That action does not erase recorder history/statistics, backups, or prior exports; each requires its own workflow. Revoking HealthKit permission likewise does not erase earlier exports.

The checked-in privacy manifest declares no tracking, collected-data categories, tracking domains, or required-reason API categories. This describes the app's own behavior; Apple Health and Home Assistant remain governed by their respective user-controlled environments.
