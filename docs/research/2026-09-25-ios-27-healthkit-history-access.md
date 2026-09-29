# iOS 27 HealthKit historical access

Research date: 2026-09-25. Scope: whether iOS 27 lets a third-party app export all historical Apple Health data, and what that means for HA Health Sync. Sources are Apple documentation and the installed Xcode 27 SDK.

## Conclusion

The intuition is directionally right, but the distinction matters:

- **iOS 27 lets a person grant a third-party app access to their full available history** for the HealthKit sample types the app requests. The authorization flow also lets the person choose a limited recent window instead. This is not a new bulk-export API. ([Apple: Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data))
- The app must still request each HealthKit type and query/backfill each type using normal HealthKit queries. Authorization remains user-controlled and type-specific. ([Apple: Executing sample queries](https://developer.apple.com/documentation/healthkit/executing-sample-queries), [Apple: Synchronize health data with HealthKit](https://developer.apple.com/videos/play/wwdc2020/10184/))
- Therefore HA Health Sync *can* be extended to import all available history for its supported metrics when the person selects full history, but iOS 27 does not make that automatic and does not mean every kind of data in Health is readable by the app.

## What changed in iOS 27

After the type-selection screen, HealthKit now presents a second authorization screen where the person chooses either a recent limited window or full history. Time-bound authorization applies to sample types.

The new `HKHealthStore.getEarliestAuthorizedSampleDate(for:completion:)` API reports the earliest readable date only for types with limited access. Apps should clamp date-range queries to that boundary. ([Apple API documentation](https://developer.apple.com/documentation/healthkit/hkhealthstore/getearliestauthorizedsampledate%28for%3Acompletion%3A%29))

Important privacy behavior:

- A returned date positively identifies limited access for that type.
- No dictionary entry can mean either full access or no read access. HealthKit intentionally does not let an app distinguish those cases.
- The user chooses full history; `requestAuthorization` has no flag that lets an app demand or preselect it.
- Samples before a limited-access boundary are unknown, not evidence that no older data exists.

The installed Xcode 27 SDK confirms the API is new in iOS 27:

```objc
- (void)getEarliestAuthorizedSampleDateForTypes:(NSSet<HKObjectType *> *)types
                                     completion:(... )completion
    API_AVAILABLE(ios(27.0), watchos(27.0), macCatalyst(27.0), macos(27.0), visionos(27.0));
```

Source: `HealthKit.framework/Headers/HKHealthStore.h` in Xcode 27.0 (build 27A266a). See also Apple’s [iOS & iPadOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes).

## Separate feature: Health app XML export

The Health app itself has a user-initiated **Export All Health Data** action that creates an XML archive and opens the share sheet. That is separate from HealthKit API access: third-party apps cannot invoke it as a one-call archive export API. ([Apple iPhone User Guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/27/ios/27))

This XML feature is not the iOS 27 novelty; Apple documents the same action in its legacy [iPod touch User Guide](https://support.apple.com/guide/ipod-touch/iph5ede58c3d/ios).

## Consequence for this repository

The current app does **not** export all history:

- Historical import is deliberately capped at roughly 14 days by `BackfillRequest.maximumAge` and enforced again by `BackfillCoordinator`.
- Only `MetricRegistry.backfillEligible` metrics participate. Workouts, timestamps, and medication sensors are currently excluded in the UI.
- These are app/Health Bridge protocol constraints, not iOS 27 HealthKit constraints.

Supporting full available history would require a separately designed app and Health Bridge migration: handle the iOS 27 authorization boundary, page or chunk per-type queries and uploads, preserve resumable checkpoints/idempotency, remove or replace the 14-day server guard safely, and communicate that the app cannot prove “full” versus “denied” access for an omitted type.

## Answer

**Yes:** on iOS 27, a user can explicitly grant this app full historical access to authorized HealthKit sample types. **No:** iOS 27 does not provide a bulk “export all Health data” API to third-party apps, and this app’s existing historical export remains limited to 14 days until its backfill protocol and implementation are expanded.
