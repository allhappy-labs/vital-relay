# HA Health Sync

HA Health Sync is an iPhone app that syncs selected Apple Health data directly with your own [Home Assistant](https://www.home-assistant.io/) through the [Health Bridge archive fork](https://github.com/allhappy-labs/Health_Bridge). It has no app account or hosted health-data service. The app and integration are separate projects; this app does not replace Apple's Health permissions or Home Assistant authentication.

## What it does

- **Free:** connect to Home Assistant, select metrics and inbound pairings, and use **Sync Now**.
- **Lifetime unlock:** enable best-effort background and Shortcuts sync plus historical import. The app displays the local App Store price and offers Restore Purchases; this is a one-time purchase, not a subscription. StoreKit/App Store availability is required for a normal purchase.
- **Historical import:** on iOS 27, a compatible Health Bridge protocol-2 fork can archive each selected metric from its earliest readable HealthKit date, including original quantity, category, and workout samples. Older iOS versions or protocol-1 servers retain the experimental latest-14-days recorder import. A Home Assistant administrator must approve this iPhone as the archive uploader before protocol-2 writes.

Background execution depends on iOS scheduling and is not guaranteed at a fixed interval. HealthKit access is per type; the app imports only data that iOS makes readable. Medication data uses a separate opt-in authorization flow and is not included in the original-sample archive.

## Requirements

- iPhone with iOS 18 or newer; iOS 27 for full-history archive import.
- A Home Assistant instance with Health Bridge. The archive fork is qualified locally against Home Assistant Core 2026.9.3 / Python 3.14.2 or newer; other server versions need compatibility testing.
- A Health Bridge **Health Assistant Link** entry and its webhook secret, plus a Home Assistant long-lived access token for authenticated API requests. Keep both credentials private and separate.

The archive fork is currently a source prerelease, not a verified HACS release. Follow [its install and upgrade guide](https://github.com/allhappy-labs/Health_Bridge/blob/main/docs/archive-operations.md), including a Home Assistant backup. The upstream HACS entry supports legacy live sync but does not provide this protocol-2 archive.

## Set up the app

1. Install the compatible Health Bridge fork if you want full history. Back up Home Assistant first. Add or keep a **Health Assistant Link** entry; do not recreate an existing entry just to upgrade the integration.
2. Build and install the app with Xcode until a verified App Store/TestFlight listing is available. Open the app, choose the Apple Health metrics you want, and grant their read access. Grant write access separately only if you configure Home Assistant → Apple Health pairings.
3. Enter your Home Assistant URL, Health Bridge user ID and webhook secret. Create a long-lived access token in your Home Assistant user profile and enter it in the app's separate API credential field. Test both connections, save, then tap **Sync Now**.
4. For historical import, open Settings → Historical Import. On iOS 27, confirm Compatibility says **Archive protocol 2 available**, request archive-uploader approval, and compare the phone's fingerprint with the administrator archive card before approval. Choose the metrics and **All readable history** only after reviewing the privacy notice. If Compatibility says protocol 1, import remains limited to 14 days.

The original-sample archive is durable server data. Revoking Health access or deleting the app does **not** erase it; Home Assistant administrators and backups may retain it. See [archive operations](https://github.com/allhappy-labs/Health_Bridge/blob/main/docs/archive-operations.md) for browsing, export, backup and deletion. Protect the Home Assistant server and its backups accordingly.

## Build and test from source

Open `HAHealthSync.xcodeproj` in a current Xcode with the required iOS SDK, select your own Apple Development team, and use an app identifier and provisioning profile with HealthKit/background-delivery capabilities. The checked-in app bundle ID is `com.marynavdovenko.HAHealthSync`; use an identifier you control for your own build. Never commit tokens, provisioning profiles or signing keys.

```bash
swift test --package-path Packages/HealthSyncCore
xcodebuild build -project HAHealthSync.xcodeproj -scheme HAHealthSync \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

The app uses Apple frameworks and its checked-in local Swift package, with no third-party Swift package download. For simulator tests, formatting and release checks, see [testing](docs/testing.md); for architecture and privacy, see [architecture](docs/architecture.md) and [privacy](docs/privacy.md).

## Project status

The protocol-2 app and fork passed local automated and disposable Home Assistant Core tests. A real iOS 27 phone-to-server archive import, target Home Assistant backup/restore, live StoreKit purchase, and App Store distribution are **not yet verified**. See the [full-history verification record](docs/full-history-archive-verification.md) and [release checklist](AppStore/release-checklist.md). Do not rely on this prerelease as the only copy of health history.

## License and upstream

HA Health Sync is licensed under [MIT](LICENSE). The Health Bridge fork is a separate MIT-licensed derivative of [gregt1993/Health_Bridge](https://github.com/gregt1993/Health_Bridge), preserving its upstream history and attribution. MIT permits commercial reuse and modified distributions; it does not require contributors to publish their changes.
