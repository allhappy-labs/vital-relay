# App Review notes

Vital Relay synchronizes selected Apple Health data with a Home Assistant instance configured and controlled by the user. The app requires iOS 18 or later, Home Assistant, and the Health Bridge integration.

## Suggested reviewer note

Candidate identity: `com.marynavdovenko.HAHealthSync`, Apple team `9XN7WN8JN2`. This is a distinct app from the old bundle and requires fresh setup and Health consent; no in-place migration is claimed.

The app has no developer-operated account or demo account. Onboarding asks the reviewer to configure a Home Assistant base URL, a Health Bridge webhook secret, and, for authenticated imports, a Home Assistant long-lived access token. Vital Relay is a companion for a self-hosted Home Assistant server that each user runs on their own hardware; the developer operates no server and cannot provide access to a private home installation. A physical-iPhone screen recording will be provided before submission. It should show onboarding and Health permission, manual Sync Now, values arriving in Home Assistant, Lifetime Unlock purchase and Restore Purchases, background sync settings, and historical import progress. Apple Review may also use its own Home Assistant installation with Health Bridge; no real server URL or credential is included in this repository or note.

Demo video: to be added before submission.

Apple Health permissions are requested only for the data types the reviewer selects. Export reads selected HealthKit types. Import writes only supported HealthKit destinations explicitly configured from Home Assistant. On supported iOS versions, medication authorization uses Apple's separate per-object flow and remains read-only.

The data path is direct between the review iPhone and the Home Assistant destination entered by the reviewer. The developer does not operate an intermediary service and cannot access the transmitted data. Diagnostics contain status, counts, timestamps, versions, and issue categories rather than health readings or credentials.

Manual sync is free and can be tested with in-app Sync Now after configuration. The non-consumable lifetime unlock (`com.marynavdovenko.HAHealthSync.lifetimeUnlock`) enables automatic background sync, all Shortcuts sync, and both historical imports. Open Settings → Lifetime Unlock to purchase or use Restore Purchases. The displayed price comes from StoreKit; cancellation or a pending purchase does not unlock features. Review should test free manual sync before purchase, purchase and restore, and locked Shortcuts behavior. Refund or revocation stops future paid work without deleting Home Assistant data.

Original-sample import requires iOS 27, selected Health permissions, a compatible Health Bridge fork (public MIT source at https://github.com/allhappy-labs/Health_Bridge, installable through HACS), and approved uploader ownership, which the Home Assistant administrator confirms in the integration's Configure menu. It creates a durable copy in the user's Home Assistant archive with no automatic expiration. One protected pending raw batch is retained locally until acknowledgement or local reset. Local reset and Health permission revocation do not delete the remote archive; export, deletion, and backup retention are managed separately in Home Assistant.

Background synchronization is best effort and scheduled by iOS; it must not be treated as an immediate or guaranteed test outcome. A locked device can temporarily make protected Apple Health data unavailable.

Reset Synchronization State removes checkpoints and status while preserving configuration, pairings, and credentials. Delete All Local App Data removes the app's configuration, pairings, checkpoints, status, and both Keychain credential records from the iPhone. Neither action deletes Apple Health samples or Home Assistant data.

Simulator demonstrations use synthetic data. Do not provide Apple Review with personal health values, a private Home Assistant URL, an access token, or a webhook secret in App Store Connect notes. No live review server is provided; the demo video stands in for one. If Apple asks for more, reply through App Review with an additional recording rather than credentials to a private home.
