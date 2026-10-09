# Set up Vital Relay

Vital Relay sends the Apple Health data you choose from your iPhone straight to your own Home Assistant. There is no account and no cloud service in between. Setup takes about ten minutes and has two parts: prepare Home Assistant, then connect the app.

You will need:

- an iPhone with iOS 18 or newer (iOS 27 for full-history import);
- Home Assistant that your iPhone can reach, with [HACS](https://hacs.xyz/) installed;
- a Home Assistant user who can create a long-lived access token.

## 1. Install Health Bridge in Home Assistant

Vital Relay talks to Home Assistant through the Health Bridge integration. The [allhappy-labs fork](https://github.com/allhappy-labs/Health_Bridge) adds full-history archive import; the original [Health Bridge](https://github.com/gregt1993/Health_Bridge) supports live sync only.

1. Back up Home Assistant (**Settings → System → Backups**).
2. In HACS, open **⋮ → Custom repositories**, add `https://github.com/allhappy-labs/Health_Bridge` with type **Integration**, then open it and choose **Download**.
3. Restart Home Assistant.

Already using the original Health Bridge? Follow the [fork's upgrade steps](https://github.com/allhappy-labs/Health_Bridge#install-or-upgrade) instead, so your existing entry and entities are kept.

## 2. Add a Health Assistant Link entry

1. Go to **Settings → Devices & services → Add integration** and choose **Health Bridge**.
2. Pick **Health Assistant Link**.
3. Copy the **Security Token** shown there and keep it somewhere safe. This is the *webhook secret* the app asks for.

If you already have a Health Assistant Link entry, keep it and reuse its token. Don't create a second one.

## 3. Create a long-lived access token

1. In Home Assistant, open your profile (your name in the sidebar) → **Security**.
2. Under **Long-lived access tokens**, choose **Create token**, name it `Vital Relay`, and copy it. Home Assistant shows it only once.

The webhook secret and the access token are different credentials and are never interchangeable. The app stores both in the iPhone Keychain.

## 4. Connect the app

Open Vital Relay and follow the three onboarding steps:

1. **Privacy** — read what the app does with your data.
2. **Metrics** — choose the Apple Health data to send, then allow read access when iOS asks. You can change this later.
3. **Connect** — fill in:

   | Field | What to enter |
   | --- | --- |
   | Base URL | The address you use to open Home Assistant, such as `https://home.example.com` or `https://example.ui.nabu.casa`. |
   | Health Bridge user ID | A short name for this person, such as `alex`. Letters, numbers, `-` and `_` only. It becomes part of the entity names in Home Assistant. |
   | Webhook secret | The Security Token from step 2. Tap **Test Health Bridge Webhook**. |
   | Long-lived access token | The token from step 3. Tap **Test Authenticated API**. |

   When both tests succeed, tap **Save and Continue**.

4. On the dashboard, tap **Sync Now**. Your metrics appear in Home Assistant as `Health Bridge (<user ID>)` sensors.

**Local HTTP.** Remote addresses must use HTTPS. If Home Assistant is only reachable over plain HTTP on your home network (for example `http://homeassistant.local:8123`), turn on **Allow confirmed local HTTP**. This works only for private-network, `.local` and Tailscale addresses.

## 5. Optional extras

- **Background sync** (Lifetime Unlock): Settings → Export to Home Assistant → Background Sync. iOS decides when background runs happen, and Apple Health can't be read while the iPhone is locked. For more frequent runs, add Shortcuts **Time of Day** automations that run *Sync Health with Home Assistant*.
- **Full-history import** (Lifetime Unlock, iOS 27, allhappy-labs fork): Settings → Export to Home Assistant → Historical Import. Tap the approval request, then in Home Assistant open **Settings → Devices & services → Health Bridge → Configure → Archive uploader approvals**. Compare the fingerprint shown on the iPhone, type it to approve, and start the import. The archive stays in Home Assistant even if you delete the app; see [archive operations](https://github.com/allhappy-labs/Health_Bridge/blob/main/docs/archive-operations.md).
- **Home Assistant → Apple Health**: Settings → Import to Apple Health lets you write selected sensor values, such as weight from a smart scale, into Apple Health.

## Troubleshooting

| Message | Fix |
| --- | --- |
| *The Home Assistant host could not be found* / *timed out* | Check the Base URL in Safari on the same iPhone and network. |
| *Webhook secret error* | Copy the Security Token from the Health Assistant Link entry again, or set a new one there under **Configure → Change secret token**. |
| *Health Bridge webhook was not found* | Health Bridge isn't installed or Home Assistant hasn't been restarted. |
| *Token error* | Create a new long-lived access token; tokens can't be viewed again after creation. |
| *The secure connection could not be verified* | Use a valid HTTPS certificate. Self-signed certificates aren't trusted. |

For more, see [troubleshooting](docs/troubleshooting.md), [privacy](docs/privacy.md) and the [technical setup reference](docs/setup.md).
