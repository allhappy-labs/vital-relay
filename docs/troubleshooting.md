# Troubleshooting

## The two connection tests disagree

They use different credentials and endpoints. “Health Bridge Webhook” sends the webhook secret to `/api/webhook/health_bridge`; “Authenticated API” sends the long-lived access token as a bearer token to `/api/`. Replace or retest only the failing credential. HTTP 401/403 usually indicates the credential for that specific path; 404 usually indicates a base-path or integration-routing problem.

## A local URL is rejected

Remote HTTP is never accepted. Plain HTTP must use a loopback, link-local, RFC1918, unique-local IPv6, exact `.local` hostname, Tailscale MagicDNS `host.tailnet.ts.net` name, or Tailscale address and requires the warning confirmation. For a confirmed machine-style Tailscale MagicDNS HTTP URL, the app resolves the name on-device and proceeds only when the result is inside Tailscale's `100.64.0.0/10` or `fd7a:115c:a1e0::/48` ranges. The built app declares only those two ranges as ATS insecure-HTTP exceptions; it does not allow arbitrary HTTP loads. An HTTP reverse proxy that requires the original `Host` header is not supported by this compatibility path; configure trusted HTTPS instead. Use HTTPS for Home Assistant Cloud, public DNS, and ordinary reverse proxies. Self-signed TLS certificates are not bypassed; install a trusted certificate instead.

## Sync reports no applied metrics

A successful HTTP status is insufficient. Vital Relay requires Health Bridge to return `ok: true`, `applied: true`, the matching request ID and live protocol, and a positive updated-entity count. Confirm that a metric has authorized HealthKit data in its current window and that Health Bridge is current. On an initial synchronization, an anchored query can contain old changes while the metric's current window contains no value; the app commits that initial anchor and safely skips the metric so the same historical changes do not cause a permanent compatibility failure. A final deleted latest-value sample after an anchor was already committed cannot clear a live sensor because the protocol has no deletion sentinel; reset/reconcile deliberately rather than sending an invented value.

## Background sync did not run at a specific time

Intervals are minimums, not run times. iOS decides when HealthKit observers and Background App Refresh wake the app. Check Settings → Background Sync → System: Background App Refresh must be On, Low Power Mode Off, and the app must not have been swiped away. Apple Health can't be read while iPhone is locked; those runs record “Export deferred — iPhone locked” and retry about 15 minutes later. Recent Sync Events show the actual trigger (Health update, Background refresh, Shortcut), duration, request count, skipped wake-ups, and “Interrupted” for runs iOS suspended or ended before they finished. Under the trigger, a second line reads “Full sweep” for a run that checked every selected metric, or “Health update” for a run scoped to just the metrics HealthKit reported as changed plus anything not checked in the last hour. Only a Health-update wake can be scoped that way; every other trigger is always a full sweep, and so is a Health-update wake whenever HealthKit doesn't say what changed, whenever a full sweep is due — four times your Background Sync interval — at least 30 minutes and at most a day, so 30 minutes on Responsive, an hour on Balanced, four hours on Battery Saver and a day on Daily — before any full sweep has ever completed (a fresh install, or right after resetting local data — not merely reopening the app), and after the local day changes. A run that ran out of time before finishing still sends whatever it had already collected instead of losing it; the metrics it never reached stay stale and lead the next run. For more frequent runs, add Shortcuts Time of Day automations.

## A sync log entry says "N starved"

Starved metrics appear in Settings → Background Sync → Recent Sync Events, on full-sweep entries only: "Full sweep · 88 metrics checked · 2 starved". They are selected metrics that sweep found unchecked for longer than the audit threshold — two hours, or twice the Background Sync interval you chose when that is longer, so two hours on Responsive, Balanced and Battery Saver and two days on Daily. The count describes the state the sweep *started* from, not the state it left behind, so one Sync Now cannot clear it: sync twice and judge the second run's count. A count above zero is normal for the first few sweeps after installing, and on an iPhone whose background wake-ups land further apart than the threshold — neither is a bug by itself, which is why the count is a line in the log rather than a status row. It only signals a real problem when it stays above zero sweep after sweep. To force a fresh full sweep on demand, open the app and tap Sync Now, which always covers every selected metric. If the count is still non-zero after a second Sync Now, or stays non-zero across several automatic sweeps, report it.

## Home Assistant's Last Sync Time updates rarely

Health Bridge moves `last_sync_time` only when a live request applies at least one entity, and at most once every 10 seconds. Runs with nothing new, locked-device runs, failed requests and import-only work never move it. A scoped Health-update run moves it exactly like a full sweep when HealthKit reported a real change to export. A daily metric also causes one export shortly after local midnight even without a new sample, because its window is refreshed once per local day; that alone can move `last_sync_time`. Enable **Publish sync attempts to Home Assistant** to get a sensor that updates on every attempt.

## Home Assistant → Apple Health did not write

Check that the entity state is numeric and not empty, `unknown`, `unavailable`, or `none`; its reported unit matches the pairing source unit (or is absent for an explicitly unitless source such as UV index); the transform is finite; the converted value is within plausible bounds; and write permission was granted for that destination. Apple-computed/read-only destinations are intentionally hidden. An unchanged entity timestamp/value is skipped as a duplicate.

## Historical import is unavailable

The current protocol is experimental and accepts only SQLite recorder schema 53, history-only writes, and up to the latest 14 days. Unsupported recorder/schema responses disable historical import without affecting live sync. Do not change or fork the integration to bypass this guard.

A result with committed metrics or points means Health Bridge confirmed recorder commits; those metric checkpoints remain committed. A metric with fewer than two eligible points in the 14-day window is shown under “Skipped (no eligible history)” and does not set an error. “Failures” is reserved for actual HealthKit query, validation, network, protocol, compatibility, cancellation, or checkpoint failures. A no-change live prerequisite is valid and does not prevent historical import when the live metric was processed cleanly.

## Medications are absent

Medication sync requires iOS 26 or newer and Apple’s per-medication authorization. The app can read approved medications and dose events but cannot create either. Medication names are intentionally forgotten when leaving the settings screen.

## Diagnostics or reset fails

Diagnostics never falls back to dumping internal state. Retry the allowlisted export. A partial reset/delete result reports only the number of failed local operations; repeat the action after unlocking the phone. Delete All Local App Data does not remove Apple Health or Home Assistant data.

## Verification cannot find a simulator

This workspace is intentionally pinned to the already-installed iPhone 17 Pro simulator on iOS 26.5. Do not create a device, install an Xcode component, fetch an external package, or download a runtime. Confirm the existing device ID with `rtk xcrun simctl list devices available` and use the exact existing ID in the commands from [testing.md](testing.md).
