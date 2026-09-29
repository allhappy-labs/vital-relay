# Background sync scheduling on iOS: what is achievable and what to change

Research date: 2026-09-13. Scope: why the "hourly" (Battery Saver) preset produced about 7 Home Assistant "Last Sync Time" updates on a day the app was never opened, what iOS can actually deliver, and what this repo should change.

Source rules: every platform claim links to an Apple primary source (documentation, DTS forum posts, WWDC transcripts, support.apple.com) or to Home Assistant source code or docs. Code claims cite `file:line` at commit `01f5ba8`. Items marked **UNVERIFIED** have no primary source or still need a device test.

---

## 1. TL;DR

- **iOS has no way to run code every hour on a guaranteed schedule.** Apple DTS says: "There's no general-purpose mechanism for: … Running code periodically at a guaranteed interval" ([Quinn, forum 685525](https://developer.apple.com/forums/thread/685525)).
  - Every mechanism available to us is opportunistic: BGAppRefresh, HealthKit background delivery, silent push, and Shortcuts automations.
  - All of them stop after the user force-quits the app. Push, refresh and HealthKit wakes stop outright; for Shortcuts this is **UNVERIFIED**.
- **HealthKit cannot be read while the iPhone is locked.** Apple: "This error occurs when your app queries for HealthKit data while the device is locked. You can, however, still save data." ([errorDatabaseInaccessible](https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible))
  - So even a perfect trigger cannot export data while the phone sits locked.
  - The realistic goal is to use every opportunity iOS grants, catch up right after unlock, and report what happened honestly.
- **HA's "Last Sync Time" does not count sync runs.** The Health Bridge integration moves it only when a live POST applies at least one entity, and at most once every 10 seconds.
  - This app only POSTs metrics whose HealthKit anchor changed.
  - So runs with no new data, runs that fail while locked, and import-only work never appear in HA.
  - The paired updates 12–17 s apart are one sync run: it sends one POST per metric, and those POSTs span more than 10 s (§2.3).
- **The code has real bugs that lose opportunities.** The most likely ones:
  - (a) Observer queries and the refresh "enabled" flag are set up only in a SwiftUI view's `.task`, which may never run on a background launch.
  - (b) A cold background launch completes the refresh task without resubmitting it, which ends the refresh chain.
  - (c) The strict `lastAttemptedAt + 60 min` gate drops HealthKit wakes that arrive a few minutes early. Since steps are delivered at most hourly, this can turn "hourly" into roughly 2-hour gaps.
  - (d) A locked-device failure is not retried soon after the device unlocks.

**Recommendations, ranked by impact per effort:**

| # | Change | Impact | Effort |
|---|---|---|---|
| 1 | Set up background work at app launch, not in a view: register the task, install observers, arm the refresh flag, and resubmit the refresh request on every exit path (§5.1) | High | S |
| 2 | Loosen the cadence gate for automatic triggers (e.g. allow at 80–90% of the interval) and retry soon after a locked-device failure (§5.2) | High | S |
| 3 | Keep each run within the ~30 s budget: batch metrics into one webhook POST, use short request timeouts for background triggers, and give App Refresh a hard deadline (§5.3) | High | M |
| 4 | Diagnostics: record the actual trigger source and outcome, and optionally publish a "last attempt" heartbeat to HA (§5.4) | High (for diagnosis) | S–M |
| 5 | Honest UX: show Background App Refresh and Low Power Mode state, the force-quit warning, the lock limitation, and "earliest next attempt" wording (§5.5) | Medium | S |
| 6 | Optional: a guide for Shortcuts Time-of-Day automations, and stop reporting "no new data" as a failure (§5.6) | Medium | S |
| 7 | Optional: a BGProcessingTask for overnight catch-up while charging (§5.7) | Low–Medium | S |
| 8 | Not recommended now: a silent-push relay driven by HA automations (§4) | Medium, still best-effort | L, needs a server and a privacy change |

---

## 2. Observed behavior and diagnosis

### 2.1 Current triggers (as implemented)

| Trigger | Where | Notes |
|---|---|---|
| HealthKit `HKObserverQuery` + `enableBackgroundDelivery(frequency: .immediate)` | `HAHealthSync/Adapters/Background/HealthKitObserverManager.swift:250-256`, `:269` | One observer per selected type. Callbacks are coalesced for 250 ms (`:52`, `:177-186`), then run through a 20 s bounded sync (`:51`, `:203-217`). The completion handler is always called via `defer` (`:163`). |
| `BGAppRefreshTask` `com.olhapi.HAHealthSync.refresh` | `HAHealthSync/Adapters/Background/AppRefreshManager.swift:30`, `:121-126`, `:165-169` | The single permitted ID is declared at `HAHealthSync/Resources/Info.plist:23-26`, with `UIBackgroundModes` = `fetch` only (`:31-34`). |
| App Intent "Sync Health with Home Assistant" | `HAHealthSync/AppIntents/SyncHealthWithHomeAssistantIntent.swift:4-19` | Declares `supportedModes = .background` on iOS 26 (`:10-11`). Bypasses the cadence gate. |
| Manual Sync Now / pull to refresh | `HAHealthSync/App/AppModel.swift:937-957` | Bypasses the gate. |
| Silent push, BGProcessingTask, URLSession background session | none | Not implemented. |

Other facts from the code:

- **Entitlements.** `com.apple.developer.healthkit.background-delivery` is present (`HAHealthSync/HAHealthSync.entitlements:7-8`).
- **Frequency preset.** The "hourly" preset is `.batterySaver`, with `minimumInterval` 3600 s (`Packages/HealthSyncCore/Sources/HealthSyncCore/BackgroundSync/BackgroundSyncFrequency.swift:22,31`).
- **Cadence gate.** It applies only to `.background` triggers: `lastAttemptedAt + interval > now` returns `.throttled` (`Packages/HealthSyncCore/Sources/HealthSyncCore/BidirectionalSync/BidirectionalSyncCoordinator.swift:36-40`, `:64-85`). It is skipped when the last failure was `.deviceLocked` (`:80-82`). The attempt is recorded before any work starts (`:92`).
- **Both directions run in background.** Background runs include inbound (HA→Health) imports, run concurrently with export (`BidirectionalSyncCoordinator.swift:115-120`). `docs/setup.md:59` still says "Background inbound execution is intentionally disabled"; that doc is stale.
- **Refresh scheduling.** `earliestBeginDate = max(now, lastAttemptedAt + interval)`, or `now + interval` if there was no prior attempt (`AppRefreshManager.swift:75-80`). The pending request is cancelled and resubmitted on every `reconcile` (`:68`). Submit errors are swallowed by `try?` (`:122`).
- **Refresh handler.** A performed run reschedules and completes with `success: report.succeeded` (`:102-108`). A throttled run reschedules at `nextEligibleAt` and completes with success (`:109-112`). The expiration handler cancels the Swift task (`:116-118`). `setTaskCompleted` is only called after `coordinator.sync` returns, which depends on how quickly cancellation propagates.
- **Data protection is not the problem.** All protected stores use `completeUntilFirstUserAuthentication` (e.g. `HAHealthSync/Adapters/Persistence/ProtectedSyncStatusStore.swift:10-14`). Keychain items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`HAHealthSync/Adapters/Keychain/KeychainCredentialStore.swift:54`). Both are readable in the background after the first unlock, as Apple recommends ([FileProtectionType](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files), [kSecAttrAccessibleAfterFirstUnlock](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock)). The lock limit is HealthKit's own encryption (§3.3).
- **Locked-device handling.** A locked device makes the anchored query throw `databaseInaccessible` (`HAHealthSync/Adapters/HealthKit/HealthKitAnchoredQueryService.swift:47-51`). `SyncCoordinator` then skips all remaining metrics and records `.deviceLocked` (`Packages/HealthSyncCore/Sources/HealthSyncCore/OutboundSync/SyncCoordinator.swift:235-238`). Nothing is POSTed.
- **Inbound writes use only `HKHealthStore.save`** (`HAHealthSync/Adapters/HealthKit/HealthKitSampleWriter.swift:117`). Apple allows saving while locked, so imports can succeed while the phone is locked.

### 2.2 Why HA shows few updates: Last Sync Time is a commit marker

- **When HA moves it.** Health Bridge calls `_update_last_sync_time_entity` only after a live request applied at least one entity. The source comment says "This is a commit marker, not an attempt marker" ([`__init__.py` L660-L663 @3d22725](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L660-L663)).
- **HA-side rate limit.** Updates less than 10 s after the previous one are skipped: `_LAST_SYNC_MIN_INTERVAL_SECONDS = 10` ([L73](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L73), [L751-L771](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L751-L771)).
- **When the app POSTs.** Only for metrics whose anchored query reports changes (`SyncCoordinator.swift:243-246`).

So these runs **do not update Last Sync Time**:

1. Runs with no new HealthKit samples.
2. Runs where HealthKit was locked (`.deviceLocked`, no POST).
3. Throttled wakes (no run at all).
4. Runs where HA was unreachable, e.g. Tailscale down (POSTs fail).
5. Inbound-only work (it uses the REST API, not the webhook).

**HA's logbook is therefore a lower bound on runs, not a count of them.** The app's own Recent Sync Events list (up to 100 entries, `Packages/HealthSyncCore/Sources/HealthSyncCore/OutboundSync/BackgroundRegistration.swift:96`) is the better record. It still does not distinguish observer from refresh launches (§5.4).

### 2.3 Paired updates 12–17 s apart

- **One POST per metric.** The outbound engine sends each changed metric as its own sequential webhook POST (`SyncCoordinator.swift:202-382`, single-key payload at `Packages/HealthSyncCore/Sources/HealthSyncCore/Networking/HealthBridgeWebhookClient.swift:23-42`).
- **What HA records.** The first POST of a run updates Last Sync Time. POSTs in the next 10 s are dropped by HA. The first POST at 10 s or later updates it again.
- **So a pair is one run lasting roughly 10–20 s.** Each POST adds its HealthKit query time plus a Tailscale round trip.
- **Why never three.** The observer path is capped at 20 s (`HealthKitObserverManager.swift:51`), which fits a maximum of two records per run.
- **Ruled out:**
  - *Two directions:* inbound does not touch the webhook.
  - *Two triggers:* concurrent triggers join the active run (`BidirectionalSyncCoordinator.swift:31-33`), and a second background trigger within the hour is throttled.
  - *Retry:* it reuses the same request and only adds at most 1–4 s (`Packages/HealthSyncCore/Sources/HealthSyncCore/OutboundSync/RetryPolicy.swift:13-17`).
- **Status:** inferred from code; confirming it needs per-run POST timestamps (§5.4).
- **Side effect.** Long runs also threaten the ~30 s background budget and the 20 s observer cap. When the cap cancels a run mid-way, later metrics stay uncommitted until the next run.

### 2.4 Code issues that lose background opportunities

1. **Background setup lives in a view.** Observers are installed, and `AppRefreshManager.latestEnabled` is set, only in `AppModel.load()` (`HAHealthSync/App/AppModel.swift:136-166`). That is called from `.task` on the `WindowGroup` root view (`HAHealthSync/App/HAHealthSyncApp.swift:18-20`).
   - Apple requires observer queries to be set up in `application(_:didFinishLaunchingWithOptions:)` ([enableBackgroundDelivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))).
   - No Apple source says a WindowGroup view renders, or its `.task` runs, during a background launch (**UNVERIFIED either way**).
   - If it doesn't run:
     - a relaunch by HealthKit has no executing observer query, so the callback is never delivered or completed, and HealthKit applies backoff and stops after three failures (§3.2);
     - a refresh launch hits the next issue.
   - Days with the app still alive in memory would look fine; days after the process is evicted would degrade. That matches "fewer updates as the day goes on" but is not proven.
2. **The refresh chain can end.** `AppRefreshManager.handle` completes with `success: false` and **does not resubmit** when `latestEnabled == false` (`AppRefreshManager.swift:85-88`). On a cold background launch `latestEnabled` defaults to `false` (`:36`) until `load()` runs. Apple: "every single BG task request object corresponds to exactly one launch … So, I'll schedule another request as soon as I get launch for an existing one" ([WWDC19 707](https://developer.apple.com/videos/play/wwdc2019/707/)). Without a resubmit there is no further refresh until the app is opened.
3. **The strict gate drops early HealthKit wakes.** An observer wake that arrives even seconds before `lastAttemptedAt + 3600` returns `.throttled`, and the observer path ignores that result (`HealthKitObserverManager.swift:209`).
   - Step count is capped at hourly delivery (§3.2), so wake times cluster about an hour apart and many will land just inside the window.
   - The next wake is then roughly another hour later, which is how multi-hour gaps can appear.
   - The refresh request may cover the gap, but only if iOS grants it.
4. **No quick retry after a lock failure.** After a `.deviceLocked` run, the gate is skipped for the next trigger (`BidirectionalSyncCoordinator.swift:80-82`). But the refresh request is still rescheduled at `startedAt + 60 min` (`AppRefreshManager.swift:102-107`), so there is no near-term retry for after the user unlocks.
5. **No time budget on the refresh path.** The observer path has a 20 s cap; App Refresh has none. `SyncCoordinator` is built without an `ExecutionDeadline` (`HAHealthSync/App/AppRuntime.swift:65-73`), and webhook requests time out after 30 s (`HealthBridgeWebhookClient.swift:142`) with up to 3 attempts. One unreachable HA host can exceed the ~30 s refresh budget. Apple warns that apps that don't signal completion in time "may be quit by the system and throttled for future background task requests" ([WWDC22 10142](https://developer.apple.com/videos/play/wwdc2022/10142/)).
6. **Registration timing.** `register()` runs from the `@State` initializer of the `App` struct (`AppRuntime.swift:105`, `HAHealthSyncApp.swift:6`). Apple requires registration "before the end of applicationDidFinishLaunching(_:)" ([register](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:))). This probably holds, since the App initializer runs during launch, but it is **UNVERIFIED**.
7. **Refresh not rescheduled after other runs.** After an observer or Shortcut run, the refresh request is not rescheduled. A stale earlier request may launch just to be throttled, wasting a launch.
8. **Shortcut reports false failures.** A Shortcut run with nothing to export or import returns failure `.healthKit`, "Apple Health data unavailable" (`Packages/HealthSyncCore/Sources/HealthSyncCore/OutboundSync/AppIntentSyncHandling.swift:51-58`). An hourly automation would report false failures.

---

## 3. iOS platform constraints (primary sources)

### 3.1 BGAppRefreshTask

- **The start date is only a lower bound.** "the system doesn't guarantee launching the task at the specified date, but only that it won't begin sooner." ([earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate))
- **One pending refresh request per app.** "There can be a total of 1 refresh task and 10 processing tasks scheduled at any time"; resubmitting "replaces the previous task request." ([submit(_:)](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:))) Apple now suggests `submitTaskRequest:completionHandler:` "to capture all error conditions".
- **About 30 s of runtime.** "provides your app up to 30 seconds of background runtime." ([Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app))
- **Completion and expiration are required.**
  - "Not calling setTaskCompleted(success:) before the time for the task expires may result in the system killing your app." ([setTaskCompleted](https://developer.apple.com/documentation/backgroundtasks/bgtask/settaskcompleted(success:)))
  - "Not setting an expiration handler results in the system marking your task as complete and unsuccessful" ([expirationHandler](https://developer.apple.com/documentation/backgroundtasks/bgtask/expirationhandler)).
- **Scheduling depends on how the user uses the app.**
  - "How often your app is launched and at what times depends on how the user has historically used your app." "if the user doesn't come back to your app in the meantime, we may choose to not launch your task at all" ([WWDC19 707](https://developer.apple.com/videos/play/wwdc2019/707/)).
  - "background execution isn't guaranteed. Instead, it's opportunistic, often discretionary, and tightly managed." Users influence scheduling via "Low Power Mode, Background App Refresh, and Low Data Mode"; "Frequently used apps have an increased chance of being scheduled" ([WWDC25 227](https://developer.apple.com/videos/play/wwdc2025/227/)).
- **Low Power Mode disables it.** "Background App Refresh is disabled automatically when a device is operating in low-power mode." ([backgroundRefreshStatus](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus)) Low Power Mode includes "Pausing discretionary and background activities" ([isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)).
- **Force quit blocks background launches.** "iOS also sets a flag that prevents the app from being launched in the background. That flag gets cleared when the user next launches the app manually." Also: "if you expect that the app refresh mechanism will grant you background execution time, say, every 15 minutes, you'll be disappointed … there are common scenarios where it won't grant you _any_ background execution time at all!" ([Quinn, forum 685525](https://developer.apple.com/forums/thread/685525))
- **Requires the fetch mode.** "Executing app refresh tasks requires setting the fetch UIBackgroundModes capability." ([BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask))
- **UNVERIFIED:** the WWDC20 "Background execution demystified" list of seven factors. The video is no longer on Apple's site, per [forum 707503](https://developer.apple.com/forums/thread/707503).

### 3.2 HealthKit background delivery

- **Frequency is a ceiling, not a schedule.** "The system wakes your app from the background at most once per time period specified." Wakes happen only when there is new data.
- **Some types are capped at hourly.** "Some sample types have a maximum frequency of HKUpdateFrequency.hourly. The system enforces this frequency transparently. For example, on iOS, stepCount samples have an hourly maximum frequency."
- **Entitlement.** Required on iOS 15+; without it the call "fails with an HKError.Code.errorAuthorizationDenied error."
- **Set up at launch.** "set up all your observer queries in your app delegate's application(_:didFinishLaunchingWithOptions:) method."
  - Sources for the four items above: [enableBackgroundDelivery(for:frequency:withCompletion:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)).
- **Always call the completion handler.** "If you don't call the update's completion handler, HealthKit continues to attempt to launch your app using a backoff algorithm … If your app fails to respond three times, HealthKit assumes your app can't receive data and stops sending background updates." (same page; [HKObserverQueryCompletionHandler](https://developer.apple.com/documentation/healthkit/hkobserverquerycompletionhandler))
  - DTS confirms: "the system will stop giving you an update, which is an as-designed behavior." ([forum 801627](https://developer.apple.com/forums/thread/801627))
- **Frequency cases:** `.immediate`, `.hourly`, `.daily`, `.weekly` ([HKUpdateFrequency](https://developer.apple.com/documentation/healthkit/hkupdatefrequency)).

### 3.3 HealthKit while locked

- **The store is encrypted when locked.** "the device encrypts the HealthKit store when the user locks the device. As a result, your app may not be able to read data from the store when it runs in the background." ([Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy))
- **Reads fail; saves still work.** "The HealthKit data is unavailable because it's protected and the device is locked … You can, however, still save data." ([errorDatabaseInaccessible](https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible))
- **DTS confirms.** "your app is not allowed to read health data while a device is locked" ([forum 824819](https://developer.apple.com/forums/thread/824819)).
- **UNVERIFIED:**
  - whether a grace period after locking lets reads succeed for a few minutes;
  - whether HealthKit re-delivers observer updates once the device is unlocked (the code comment at `HealthKitObserverManager.swift:193-194` assumes it does).

### 3.4 Silent (background) push

- **Best effort and throttled.** "the system doesn't guarantee their delivery … may throttle … don't try to send more than two or three per hour."
  - Required headers: `apns-push-type: background` and `apns-priority: 5`. The app gets 30 seconds.
  - "If something force quits or kills the app, the system discards the held notification." ([Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app))
- **APNs auth.** APNs validates "either the provided authentication token or your server's certificate" ([Sending notification requests](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)). So the sender needs this app's APNs key. That conclusion is inferred from the auth model; no single sentence states it.
- **What HA supports.** HA `mobile_app` registration accepts any `push_url` plus `push_token` (`probatio.Inclusive(ATTR_PUSH_URL, "push_cloud"): cv.url`, [const.py L107-L115 @09e3474f](https://github.com/home-assistant/core/blob/09e3474f/homeassistant/components/mobile_app/const.py#L107-L115)). `notify.py` POSTs to that URL ([notify.py @09e3474f](https://github.com/home-assistant/core/blob/09e3474f/homeassistant/components/mobile_app/notify.py)).
  - A third-party app could therefore register as a mobile_app device and receive `notify.mobile_app_*` calls through its **own** relay.
  - The official relay only serves the official Companion app, which is limited to "500 push notifications per day per device" ([Companion docs](https://companion.home-assistant.io/docs/notifications/notification-details)).
  - Commands such as `request_location_update` are implemented by the Companion app, not by HA core ([notification commands](https://companion.home-assistant.io/docs/notifications/notification-commands)).

### 3.5 Other mechanisms

- **BGProcessingTask:** "run only when the device is idle … terminates any background processing tasks running when the user starts using the device"; can require external power ([BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)). Suitable for deferrable, device-idle work, not an hourly schedule ([WWDC19 707](https://developer.apple.com/videos/play/wwdc2019/707/)).
- **BGContinuedProcessingTaskRequest (iOS 26):** "Submission needs to occur as a result of a person's action, such as tapping a button" ([doc](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)). WWDC25 says "Avoid automatic workloads like maintenance, backups, or photo syncing" ([WWDC25 227](https://developer.apple.com/videos/play/wwdc2025/227/)). Not usable for periodic sync.
- **Shortcuts Time of Day automations:**
  - Repeat options are "Daily … Weekly … Monthly" ([Event triggers](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios)). Hourly means about 24 separate automations (inference).
  - Time of Day automations can run without asking: "Turn off Ask Before Running, then tap Don't Ask … The automation will not notify you when it's triggered." ([Enable or disable a personal automation](https://support.apple.com/guide/shortcuts/enable-or-disable-a-personal-automation-apd602971e63/ios))
- **App Intents:**
  - The default `authenticationPolicy` `.alwaysAllowed` "allows the intent to run without authentication, including when the device is locked" ([authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)). HealthKit reads still fail while locked.
  - Background intents get 30 s unless using `LongRunningIntent` (iOS 27) ([LongRunningIntent](https://developer.apple.com/documentation/appintents/longrunningintent)).
- **SwiftUI and background launches.**
  - `Scene.backgroundTask(_:action:)`: "When the system wakes your app … it will call any actions associated with matching tasks" ([doc](https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:))).
  - WWDC25: "You must register BackgroundTasks immediately during launch."
  - No primary source says a WindowGroup view's `.task` runs on a background launch (**UNVERIFIED**).
- **App Review.**
  - 2.5.4: "Multitasking apps may only use background services for their intended purposes" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). This rules out keep-alive tricks with location or audio.
  - 2.4.2: "Apps should not rapidly drain battery".
- **Device-only debugging.** `_simulateLaunchForTaskWithIdentifier:` and `_simulateExpirationForTaskWithIdentifier:` work on devices only. They must not ship: "Including a reference to these functions in apps submitted to the App Store is cause for rejection." ([Starting and terminating tasks during development](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development))
- **The official HA Companion app uses the same mechanisms.** It uses `BGAppRefreshTaskRequest` with a 15-minute earliest interval, plus `HKObserverQuery` with `.immediate` background delivery ([HealthKitService.swift @3b84e5b6](https://github.com/home-assistant/iOS/blob/3b84e5b6/Sources/Shared/API/Webhook/Sensors/Health/HealthKitService.swift)). It has no special cadence mechanism.

---

## 4. Options evaluated

| Mechanism | Cadence guarantee | Requirements / cost | User setup | App Store fit |
|---|---|---|---|---|
| HealthKit observer + background delivery (existing) | None. Wakes only on new data, at most hourly for capped types such as steps, and no reads while locked | Correct launch-time setup; completion handler called on every path | Health permissions | Yes (entitlement present) |
| BGAppRefreshTask (existing) | None. `earliestBeginDate` is a lower bound, driven by usage, battery, Low Power Mode, the Background App Refresh switch and force quit | One pending request; resubmit on every launch; finish within ~30 s | Background App Refresh on; don't force-quit | Yes |
| BGProcessingTask (`requiresExternalPower`) | None. Runs when idle, typically overnight | Second task ID; minutes of runtime; killed when the user picks up the phone | None | Yes |
| Shortcuts Time-of-Day automations → App Intent | Fires near the set times (exact reliability **UNVERIFIED**). Outbound reads still fail while locked; inbound writes work | Background-capable intent (exists); intent must not report "no data" as failure | Create up to 24 automations with "Don't Ask" | Yes |
| Silent push from HA automation → developer relay → APNs | None. Throttled; Apple says ≤2–3/hour; dropped after force quit; locked-read limit still applies | APNs key, hosted relay, mobile_app registration flow, privacy policy change (HA→relay→Apple instead of direct-only) | HA automation calling `notify.mobile_app_*` hourly | Yes if used for real content updates; requires a server |
| BGContinuedProcessingTask (iOS 26) | N/A. Must start from a user action | — | — | Not for periodic sync |
| Keep-alive via location/audio/VoIP | N/A | — | — | No (2.5.4) |

Conclusion: fix and fully use the two existing mechanisms first. Add Shortcuts as an opt-in "closer to hourly while in use" path. Push is the only server-initiated option; it is still best-effort and conflicts with the app's direct-to-HA privacy promise.

---

## 5. Recommended plan

### 5.1 Set up background work at launch, not in a view

- **Launch-time setup.** Add a `UIApplicationDelegateAdaptor`, or an explicit bootstrap started from `HAHealthSyncApp.init`. It should, independently of any view:
  1. register the BG task;
  2. asynchronously load configuration from the protected stores;
  3. call `HealthKitObserverManager.reconcile(enabled:metrics:)`;
  4. call `AppRefreshManager.reconcile(...)`.
- **Slim down `AppModel.load()`.** Keep it for UI state only; background reconcile becomes idempotent and callable from both places (`HAHealthSync/App/AppModel.swift:136-166`, `HAHealthSync/App/AppRuntime.swift:96-105`).
- **Alternative for refresh.** Move the refresh handler to SwiftUI's `.backgroundTask(.appRefresh("com.olhapi.HAHealthSync.refresh"))` on the `WindowGroup` scene. That removes the manual `register` path, but observers still need launch-time installation.
- **Don't rely on in-memory state in `AppRefreshManager.handle`.** Replace the `latestEnabled` guard (`AppRefreshManager.swift:85-88`) with a config read. **Always resubmit before completing**, including disabled, error, cancelled and expired paths.
- **Expiration handler.** Call `setTaskCompleted(success: false)` directly in the handler, guarded so it runs once, instead of waiting for cancellation to propagate (`:116-118`).
- **Submit errors.** Use `submitTaskRequest(_:completionHandler:)`, or log the `try?` failure (`:121-126`), so `tooManyPendingTaskRequests` and `unavailable` are visible.
- **Reschedule after every run.** After *every* performed run (observer, Shortcut, manual), reschedule the refresh request from the new `lastAttemptedAt`. For example, have `BidirectionalSyncCoordinator` publish an "attempt finished" callback that `AppRefreshManager` observes.

### 5.2 Cadence gate and lock-aware retries

- **Add tolerance to automatic triggers.** In `BidirectionalSyncCoordinator.nextEligibleDate` (`:64-85`), allow a run when `elapsed ≥ interval × 0.8`, or `interval − max(5 min, 10%)`. Apply it to all automatic triggers, so hourly-capped HealthKit wakes and early refresh launches aren't dropped. Keep the exact interval for display. Update the spec at `docs/superpowers/specs/2026-08-28-configurable-bidirectional-sync-frequency-design.md:97-123`.
- **Don't discard a throttled observer wake.** Keep the refresh request pinned at `nextEligibleAt` (`HealthKitObserverManager.swift:209` currently discards the outcome).
- **Retry soon after a lock failure.** If the report contains `.deviceLocked`, schedule the refresh request at `now + 15 min` instead of `startedAt + interval` (`AppRefreshManager.swift:102-107`).
- **Consider not recording a lock-only failure as the attempt.** This app-side guard is separate from the gate bypass that already exists at `BidirectionalSyncCoordinator.swift:80-82`.
- **Optional:** when the app next becomes active (`scenePhase == .active`), run an automatic catch-up if the interval has elapsed. This helps users who unlock and open other apps less than it helps app users, but it costs nothing.

### 5.3 Fit each run into the background budget

- **Batch the outbound payload.** Build one live request whose `data` contains every changed metric (plus workout and medications if the protocol allows). Commit anchors only on an acknowledgement with `updated_entities > 0`.
  - The Health Bridge live contract accepts multiple top-level keys (`docs/health-bridge-protocol.md:44-87`).
  - But the acknowledgement reports only counts, so a partial `skipped_entities` cannot be mapped back to keys. Fall back to per-metric POSTs only when `skipped_entities > 0`.
  - This removes the paired HA records and cuts runtime to about one round trip.
  - Changes go in `Packages/HealthSyncCore/Sources/HealthSyncCore/OutboundSync/SyncCoordinator.swift:202-382` and `Networking/HealthBridgeWebhookClient.swift`.
- **Apply a hard deadline to background triggers.** Pass an `ExecutionDeadline` of about 25 s for refresh and intent runs, and about 18 s for observer runs (`AppRuntime.swift:65-73`). Reduce per-request timeouts for background triggers, e.g. 8–10 s instead of 30 s (`HealthBridgeWebhookClient.swift:142`, `HomeAssistantClient.swift:50,95,132`), so an unreachable Tailscale host fails fast.
- **Order work by priority.** Do cheap, high-value metrics first so partial runs still commit something.

### 5.4 Diagnostics

- **Distinguish the trigger.** Split `SyncTrigger.background` (`Packages/HealthSyncCore/Sources/HealthSyncCore/OutboundSync/SyncTypes.swift:3-8`) into `.healthKitObserver`, `.appRefresh`, `.processing` and `.shortcut`, keeping the gate classification. Decode the legacy `background` value for compatibility.
- **Record outcomes that currently vanish.** Throttled outcomes, with `nextEligibleAt`, should be stored as lightweight events. Today they are "normal control flow" and invisible.
- **Record per-run facts.** Protected-data availability at start, number of POSTs, first and last POST time, and duration.
- **Record launch context.** `UIApplication.backgroundRefreshStatus`, `ProcessInfo.isLowPowerModeEnabled`, and whether this was a cold launch.
- **Add a unified log.** Use `os.Logger` in category `background` for task launch, expiry, completion and submit errors (`URLSessionTransport.swift:6` shows the existing pattern). Keep entries value-free.
- **Optional HA heartbeat.**
  - After each attempt, including throttled, locked and no-data runs, `POST /api/states/sensor.health_bridge_sync_attempt_<user>` with state = timestamp and attributes `trigger`, `outcome`, `exported`, `imported`, `failure_category`.
  - The HA REST API "Updates or creates a state … it does not have to be backed by an entity" ([HA REST API](https://developers.home-assistant.io/docs/api/rest/)). The access token already exists for inbound sync.
  - This makes HA Activity show every run, not just commits. Put it behind a setting, and document that it is in-memory until the recorder stores it.

### 5.5 UX

- **Status rows in Background Sync settings** (`HAHealthSync/Features/Settings/BackgroundSyncSettingsView.swift`):
  - Background App Refresh status, with a deep link to Settings when `.denied`; don't warn on `.restricted`, per Apple.
  - Low Power Mode, observed via `NSProcessInfoPowerStateDidChange`.
- **Copy to state plainly:**
  - "Apple Health can't be read while iPhone is locked; sync catches up after unlock."
  - "Don't swipe the app away — iOS stops background sync until you open it again."
- **Show "Earliest next automatic attempt: HH:MM", never "Next sync at".** Also show the last attempt by trigger source.
- **Explain HA's Last Sync Time.** It updates only when new data is sent; point to the heartbeat sensor if enabled.

### 5.6 Shortcuts automation path (opt-in)

- **Stop reporting "no new data" as a failure.** Return success with zero counts (`AppIntentSyncHandling.swift:51-58`). Report a locked device as a distinct, calm result.
- **Add an in-app guide:** Shortcuts → Automation → Time of Day → set the time → Daily → run "Sync Health with Home Assistant" → Don't Ask. Repeat for each desired hour, e.g. waking hours only.
- **Consider a count-bounded intent option.** It would respect the configured interval, e.g. skip if the last attempt was under 50 minutes ago, so user automations and background work don't double up.

### 5.7 BGProcessingTask catch-up (optional)

- **Add a second identifier.** Create `com.olhapi.HAHealthSync.catchup`, a `BGProcessingTaskRequest` with `requiresExternalPower = true` and `requiresNetworkConnectivity = true`, submitted with the refresh request. Add it to `Info.plist` `BGTaskSchedulerPermittedIdentifiers`; `processing` must be added to `UIBackgroundModes`. Apple: "Executing processing tasks requires setting the `processing` UIBackgroundModes capability" ([BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)).
- **Expected value is low.** It is useful only if the device is unlocked-idle on the charger, since HealthKit reads still need unlock (§3.3).

---

## 6. Open questions / verify on device

1. Does `WindowGroup` `.task` run on background launches in this app? Test with `_simulateLaunchForTaskWithIdentifier:` after the app has been terminated (not just suspended) and with Xcode's "Wait for executable to be launched". Log whether `AppModel.load()` executed before `handle`.
2. On the 2026-09-13 data: export Diagnostics and Recent Sync Events for that day.
   - How many background runs happened versus the 7 HA records?
   - How many were `.deviceLocked`, how many had 0 exported, and how many had failures?
   - This confirms or refutes §2.2–2.4.
3. Were the 4:00 AM and 10:00 AM runs reading HealthKit while locked (implying a grace period or recent unlock) or while unlocked? **UNVERIFIED** whether any post-lock read window exists.
4. Does HealthKit re-deliver an observer update after unlock following an `errorDatabaseInaccessible` callback? The code assumes it does (`HealthKitObserverManager.swift:193-194`).
5. Measure the actual duration and POST count per run over Tailscale, to confirm the 10–20 s run explanation for paired records.
6. Were Background App Refresh on and Low Power Mode off all day? Was the app force-quit at any point?
7. Do Time-of-Day automations with "Don't Ask" run a `.background` intent reliably while locked on iOS 26? Do they post any notification? Apple's guide says no notification; not tested.
8. Is `submit` failing silently, e.g. `unavailable` when Background App Refresh is off? Add logging per §5.4.
9. Does registering from the `App` struct's `@State` initializer happen before `didFinishLaunching` ends on iOS 26? It seems likely but has not been tested.
10. `docs/setup.md:59` contradicts current code (background inbound is enabled). Fix it when implementing.

---

## 7. Verification (2026-09-14)

Code claims were re-read at `01f5ba8`. The HA-side claims were re-read from Health Bridge `__init__.py` @`3d22725`. Device evidence was copied from the phone's protected status store and from a throwaway probe build (branch `probe/background-launch`, not merged) on the iPhone 14 (iOS 26.6).

### 7.1 Confirmed

- **Last Sync Time.** It is a commit marker with a 10 s smoothing window (`__init__.py` L73, L660-L663, L751-L771).
- **Paired HA records are one run.** Evidence from on-device status events, Sep 13 local time:

  | Run | Metrics exported | HA records |
  |---|---|---|
  | 16:33 | 9 | 2 (16:33:26, 16:33:38) |
  | 13:38 | 4 | 1 |
  | 10:00 | 5 | 1 |
  | 04:00 | 5 | 1 |

- **Locked device blocks export.** Sep 13 recorded three `deviceLocked` runs that exported 0 metrics: 09:56, 11:04 and 12:26.
- **Code issues confirmed:**
  - §2.4 #2: the refresh handler completes without resubmitting when `latestEnabled == false`.
  - §2.4 #3: the strict one-hour gate.
  - §2.4 #5: no deadline on the refresh path, and 30 s request timeouts.
  - §2.4 #8: Shortcut "no data" is reported as a failure.

### 7.2 Corrected: §2.4 #1 is a race, not "view never runs"

The probe logged launch milestones to a file. The app was terminated with `devicectl` (not a user force-quit). iOS then relaunched it for the pending refresh request, at 22:35:43Z against an `earliestBeginDate` of 22:35:25Z:

```
22:35:43Z pid=6385 state=0 app-init
22:35:43Z pid=6385 state=2 view-task              ← WindowGroup .task DOES run in background
22:35:43Z pid=6385 state=2 refresh-handle enabled=false   ← handler ran before load() finished
22:35:43–45Z  60 observer-event changed …         ← observers being installed by load()
(no load-finished, no observer-outcome)
```

- **`.task` does run in the background.** On a background launch, the `WindowGroup` `.task` does run, with `applicationState == .background`.
- **The refresh handler loses the race.** `AppRefreshManager.handle` runs before `AppModel.load()` reaches `reconcile`, so the refresh task is completed as unsuccessful and never resubmitted.
- **The run is frozen mid-way.** The initial observer callbacks started a sync: `lastAttemptedAt` became 22:35:44Z. iOS then suspended the process, since the refresh task had already been completed. Neither the run nor `load()` finished; process 6385 stayed alive but suspended, and no event was recorded.

### 7.3 New findings

1. **Cancelled or suspended runs vanish from history.**
   - `ProtectedSyncStatusStore.record(report:)` begins with `try Task.checkCancellation()` (`ProtectedSyncStatusStore.swift:77`).
   - So any run cancelled by the observer cap or by task expiry never records an event or `lastFailure`. The coordinator returns a `.checkpoint` report that is never persisted.
   - A suspended run records nothing until it resumes.
   - Sep 13 evidence: HA received data at 20:04, but the phone has no event after 16:33, while `lastAttemptedAt` is 23:35.
2. **The observer "20 s cap" is not a hard bound.** `withTaskGroup` implicitly awaits all child tasks before returning. `cancelAll()` only signals cancellation, so the observer completion handler runs only after the sync unwinds (`HealthKitObserverManager.swift:203-217`).
3. **Every run does one anchored query per metric, one after another.** The device has 88 selected metrics, so each run makes about 88 HealthKit queries before any network time.
4. **Installing observers causes a burst of initial callbacks.** Executing each observer query delivers one callback per type (85 observed). They coalesce into one run, which the gate can throttle. These callbacks are not background deliveries, so iOS grants no background time for them.
