# App Review notes

HA Health Sync synchronizes selected Apple Health data with a Home Assistant instance configured and controlled by the user. The app requires iOS 18 or later, Home Assistant, and the Health Bridge integration.

## Suggested reviewer note

Candidate identity: `com.marynavdovenko.HAHealthSync`, Apple team `9XN7WN8JN2`. This is a distinct app from the old bundle and requires fresh setup and Health consent; no in-place migration is claimed.

The app has no developer-operated account or demo account. Onboarding asks the reviewer to configure a Home Assistant base URL, a Health Bridge webhook secret, and, for authenticated imports, a Home Assistant long-lived access token. Apple Review may use its own reachable Home Assistant installation with Health Bridge; no real server URL or credential is included in this repository or note.

Apple Health permissions are requested only for the data types the reviewer selects. Export reads selected HealthKit types. Import writes only supported HealthKit destinations explicitly configured from Home Assistant. On supported iOS versions, medication authorization uses Apple's separate per-object flow and remains read-only.

The data path is direct between the review iPhone and the Home Assistant destination entered by the reviewer. The developer does not operate an intermediary service and cannot access the transmitted data. Diagnostics contain status, counts, timestamps, versions, and issue categories rather than health readings or credentials.

Manual sync is free and can be tested with in-app Sync Now after configuration. The non-consumable lifetime unlock (`com.marynavdovenko.HAHealthSync.lifetimeUnlock`) enables automatic background sync, all Shortcuts sync, and both historical imports. Open Settings → Lifetime Unlock to purchase or use Restore Purchases. The displayed price comes from StoreKit; cancellation or a pending purchase does not unlock features. Review should test free manual sync before purchase, purchase and restore, and locked Shortcuts behavior. Refund or revocation stops future paid work without deleting Home Assistant data.

Original-sample import requires iOS 27, selected Health permissions, a compatible Health Bridge fork, and approved uploader ownership. It creates a durable copy in the user's Home Assistant archive with no automatic expiration. One protected pending raw batch is retained locally until acknowledgement or local reset. Local reset and Health permission revocation do not delete the remote archive; export, deletion, and backup retention are managed separately in Home Assistant.

Background synchronization is best effort and scheduled by iOS; it must not be treated as an immediate or guaranteed test outcome. A locked device can temporarily make protected Apple Health data unavailable.

Reset Synchronization State removes checkpoints and status while preserving configuration, pairings, and credentials. Delete All Local App Data removes the app's configuration, pairings, checkpoints, status, and both Keychain credential records from the iPhone. Neither action deletes Apple Health samples or Home Assistant data.

Simulator demonstrations use synthetic data. Do not provide Apple Review with personal health values, a private Home Assistant URL, an access token, or a webhook secret in App Store Connect notes. If review access must be supplied, enter it only in the private App Review fields after confirming the exact test environment and its limited permissions.
