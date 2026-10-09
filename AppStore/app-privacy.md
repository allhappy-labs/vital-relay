# App Privacy draft

## Recommended App Store Connect answer

Answer **No, we do not collect data from this app**.

This recommendation uses Apple's App Privacy meaning of collection: data must be transmitted off the device in a way that lets the developer or a third party access it for longer than necessary to service the request. Vital Relay processes data on the iPhone or sends selected data, at the user's direction, directly to the Home Assistant destination the user configured. Neither the developer nor project-operated infrastructure receives or can access that transfer. Original-sample import makes a durable copy in the user's Home Assistant archive with no automatic expiration. Home Assistant administrators and configuration backups may access that copy; local reset and permission revocation do not delete it. A protected, backup-excluded pending raw batch is retained on the phone until acknowledgement or local reset.

Apple handles the non-consumable purchase and restoration through StoreKit. The app verifies entitlement locally and does not transmit transaction payloads to a developer-operated purchase server or include them in diagnostics. Apple handles payment information; the app does not collect payment-card details. Reassess the App Privacy questionnaire against this exact data flow and Apple's current definitions before submission.

The app does not have a developer-operated account, analytics, advertising, remote logging, external backend, cloud database, or tracking. The checked-in privacy manifest declares no tracking, collected-data categories, tracking domains, or required-reason API categories.

## Facts to recheck immediately before submission

- HealthKit read access remains limited to user-selected types.
- HealthKit write access remains limited to supported destinations configured by the user.
- Health Bridge and Home Assistant traffic still goes only to the user-configured destination.
- The webhook secret and Home Assistant access token remain device-only Keychain records.
- Archive retention, pending raw batches, administrator export/deletion, and backup behavior match the public policy.
- StoreKit remains the only purchase authority, without purchase telemetry or a developer receipt service.
- Ordinary synchronization still does not persist raw health readings, medication names, Home Assistant response bodies, or imported entity values.
- Diagnostics remain limited to allowlisted versions, states, counts, timestamps, and issue categories, with credentials, URLs, entity identifiers, and health values excluded or redacted.
- No SDK, service, or infrastructure has been added that lets the developer access app data.
- `HAHealthSync/Resources/PrivacyInfo.xcprivacy`, `docs/privacy.md`, and the public Privacy Policy remain consistent.

If a later build introduces developer-accessible accounts, telemetry, logging, storage, support uploads, or any other service that receives app data, this answer is invalid and must be reassessed before that build is submitted.

## Separate disclosures and confirmations

HealthKit access and use must still be described accurately in the app's purpose strings, product behavior, review notes, and public Privacy Policy. Apple Health, the user's Home Assistant, and integrations installed by the user remain separately governed environments; their behavior does not make data accessible to this app's developer.
