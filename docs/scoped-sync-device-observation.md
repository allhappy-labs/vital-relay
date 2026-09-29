# Scoped change detection: device observation, 19–21 September 2026

Evidence for the background-sync reliability and scoped-change-detection work. Device: iPhone 14
(`iPhone14,7`), iOS 26.6, Background Sync frequency Balanced, 88 selected metrics. Times are the
device's local time. Every figure below is read from `sync-status-v1.json` pulled off the device
with `devicectl`; nothing here is a simulator result.

This records what was observed, not a pass on every checklist item. Items the observation did not
exercise — Home Assistant downtime, network transitions, medication sync, inbound pairings — stay
open in `real-device-checklist.md`.

## Baseline, before the change (build `a8dfe70`, 19 September)

Five runs between 07:46 and 13:36. Every one was a full 88-metric sweep; no scoped run occurred at
any point in the device's recorded history. Two runs overran their 18 s budget without reporting
it — a 25.45 s collection and a 32.87 s single-request send — and `starvedMetrics` read 88 on every
sweep.

| Time | Trigger | Scope | Synced | Collect | Send | Starved |
| --- | --- | --- | --- | --- | --- | --- |
| 07:46 | observer | firstRunAfterLaunch | 0 | 25.45 s | — | 88 |
| 08:17 | observer | firstRunAfterLaunch | 5 | 2.48 s | 0.26 s | 1 |
| 09:36 | appRefresh | trigger | 0 (locked) | 0.03 s | — | 0 |
| 10:22 | observer | sweepDue | 0 | 1.15 s | 32.87 s | 88 |
| 13:36 | observer | sweepDue | 9 | 3.77 s | 0.13 s | 88 |

## After the change (build `217b0cb`, 19–20 September)

Installed 16:43. The first scoped run in the device's history appeared within a minute.

| Time | Trigger | Scope | Synced | Deferred | Collect | Send |
| --- | --- | --- | --- | --- | --- | --- |
| 20:12 | observer | staleMetrics | 4 | 0 | 0.79 s | 0.07 s |
| 21:34 | observer | sweepDue | 2 | 0 | 1.39 s | 0.04 s |
| 22:34 | observer | staleMetrics | 2 | 0 | 1.39 s | 0.04 s |
| 23:35 | observer | staleMetrics | 4 | 0 | 1.28 s | 0.13 s |

Runs roughly hourly rather than 3–5 hours apart; three of four scoped; `starved=0` on the sweep,
where every sweep on the old build read 88.

### The defect this exposed

The morning after an overnight lock, two sweeps did badly: 10:59 collected 24 of 88, and 11:59
collected nothing at all in 18.67 s with zero requests sent. `collectSeconds` brackets
`collectMetrics` alone, and every non-probe collector there is bounded at `expiresAt - sendReserve`
= 10 s, so 18.67 s could only be the device-lock probe — which was bounded at the whole budget. A
locked HealthKit answers promptly with an error and the `.locked` short-circuit works (the 09:50
run: `skip=88`, 0.02 s), but a query that *hangs* ran to the 18 s bound and left no budget to admit
the other 87 metrics. Rotation changes which metric goes first, so any slow type could do this to
any wake.

## After the probe fix (build `64f0d26`, 20–21 September)

Probe bounded at 5 s; a probe that times out is no longer treated as a lock and no longer ends the
run.

| Time | Trigger | Scope | Synced | Deferred | Collect |
| --- | --- | --- | --- | --- | --- |
| 14:15 | observer | sweepDue | 2 | 86 | 9.69 s |
| 14:16 | manual | trigger | 60 | 0 | 7.10 s |
| 15:37 | observer | staleMetrics | 4 | 0 | 0.48 s |
| 17:19 | observer | staleMetrics | 2 | 0 | 1.86 s |
| 18:19 | observer | sweepDue | 4 | 0 | 1.63 s |
| 19:28 | observer | staleMetrics | 4 | 0 | 0.97 s |
| 21:05 | observer | staleMetrics | 2 | 0 | 1.58 s |
| 22:05 | observer | staleMetrics | 4 | 0 | 1.14 s |
| 04:36 | observer | sweepDue | 51 | 28 | 9.63 s |

The 04:36 sweep is the direct comparison with the defect above: the same post-idle conditions that
previously produced `collected=0, deferred=88, requests=0` now produce **60 collected, 51 sent, 28
deferred**. The deferred metrics keep their anchors and freshness, so the next run covers them.

## What the observation establishes

- Scoped runs happen, and are the common case in normal use: 9 of 13 observer runs across the two
  post-change builds, finishing in about 1–2 s.
- Full sweeps still happen on schedule — 21:34, 18:19 and 04:36 — at four times the configured
  interval (one hour on Balanced).
- One Health Bridge request per run, including the batched 60-metric manual sync.
- `deferredMetrics` distinguishes truncation from failure on the device, which is what made the
  probe defect findable at all; on the old build the same run reported nothing amiss.
- No failures of any category were recorded across any run on either post-change build.

## What it does not establish, and the known limits

- **HealthKit is slow after a long idle.** The first sweep after several hours still needs about
  9.6 s and defers part of the selection. That is graceful degradation, not loss, but it is not
  fixed — only bounded. The remaining question is whether the slowness is HealthKit's change query
  or the checkpoint store; the device data cannot separate them.
- **iOS does not wake a sleeping phone.** Gaps of 21:35 → 07:50 and 22:05 → 04:36 are the OS
  declining to run, and no app-side change addresses them.
- **`starvedMetrics` reads 88 after any long gap**, because an 11-hour gap exceeds any threshold
  derived from the configured interval. It measures wake sparsity as much as skipping, which is why
  it is diagnostics-only and no longer shown in Settings.
- Home Assistant downtime, network transitions, medication sync, inbound pairing sync, and
  force-quit relaunch behaviour were not exercised in this window.
