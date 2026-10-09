# Health Bridge protocol contract

Original protocol-1 research snapshot: 2026-08-27 (Europe/Zurich). Current archive supplement: 2026-09-26.

## Current version and archive supplement

The detailed protocol-1 examples below document the older v1.2.1 source snapshot. Upstream Health Bridge v2.1.0 at `399c6aa3c7af32d0d2faa49ae71286695532c0cb` retains live and backfill protocol 1 and both Health Assistant Link and Phone Assistant Link. Its tagged registry adds **19 keys** (92 to 111), despite release notes saying 18: `running_power`, `running_stride_length`, `running_ground_contact_time`, `running_vertical_oscillation`, `cycling_power`, `cycling_cadence`, `cycling_speed`, `running_speed`, `cycling_functional_threshold_power`, `swimming_stroke_count`, `underwater_depth`, `water_temperature`, `workout_effort_score`, `estimated_workout_effort_score`, `distance_rowing`, `distance_paddle_sports`, `distance_cross_country_skiing`, `distance_downhill_snow_sports`, and `distance_skating_sports`. The app now has direct mappings for these 19; running-device availability still controls which types can be selected. Upstream v2.1.0 also adds recorder-only protocol-1 text backfill for workouts and sleep boundaries. Its current v1 limits differ from the older snapshot below: at most 14 days plus grace, 2,500 points per request, and 721 per entity on SQLite recorder schema 53. Neither upstream v1 path stores original sample UUIDs or long-term statistics. See the [upstream refresh](research/2026-09-25-health-bridge-upstream-refresh.md) for the source audit.

The local `2.1.1a1` archive fork adds a separate Health Assistant Link protocol 2 and archive schema 3. Its catalog advertises 107 direct metrics from 99 HealthKit types; 101 numeric metrics have hourly projection rules and six are original-sample timeline only. Four live keys have no direct archive source: `uv_exposure_sed`, `net_calories`, `last_sync_time`, and `test_connection`. An advertised type is not proof that a device supports it or grants readable history. Phone Assistant Link and the existing live/backfill v1 routes remain separate. The fork's canonical contract is `docs/protocol/archive-v2.md` in the Health Bridge checkout, with versioned JSON fixtures and a catalog. Clean fork `863a371` passed 265 tests and a disposable installed Home Assistant Core 2026.9.3 container gate with all 16 ownership/archive checks and two clean shutdowns. Public HACS distribution, HA OS/Supervisor restore, production installation, and iOS 27 end-to-end acceptance remain open.

The 19 new direct mappings below are copied from the fork's tested `archive-catalog-v2.json` fixture; units are canonical archive tokens, not necessarily `HKUnit.unitString`:

| Health Bridge metric | HealthKit sample type | Canonical unit |
| --- | --- | --- |
| `running_power` | `HKQuantityTypeIdentifierRunningPower` | W |
| `running_stride_length` | `HKQuantityTypeIdentifierRunningStrideLength` | m |
| `running_ground_contact_time` | `HKQuantityTypeIdentifierRunningGroundContactTime` | ms |
| `running_vertical_oscillation` | `HKQuantityTypeIdentifierRunningVerticalOscillation` | cm |
| `cycling_power` | `HKQuantityTypeIdentifierCyclingPower` | W |
| `cycling_cadence` | `HKQuantityTypeIdentifierCyclingCadence` | rpm |
| `cycling_speed` | `HKQuantityTypeIdentifierCyclingSpeed` | m/s |
| `running_speed` | `HKQuantityTypeIdentifierRunningSpeed` | m/s |
| `cycling_functional_threshold_power` | `HKQuantityTypeIdentifierCyclingFunctionalThresholdPower` | W |
| `swimming_stroke_count` | `HKQuantityTypeIdentifierSwimmingStrokeCount` | count |
| `underwater_depth` | `HKQuantityTypeIdentifierUnderwaterDepth` | m |
| `water_temperature` | `HKQuantityTypeIdentifierWaterTemperature` | degC |
| `workout_effort_score` | `HKQuantityTypeIdentifierWorkoutEffortScore` | appleEffortScore |
| `estimated_workout_effort_score` | `HKQuantityTypeIdentifierEstimatedWorkoutEffortScore` | appleEffortScore |
| `distance_rowing` | `HKQuantityTypeIdentifierDistanceRowing` | m |
| `distance_paddle_sports` | `HKQuantityTypeIdentifierDistancePaddleSports` | m |
| `distance_cross_country_skiing` | `HKQuantityTypeIdentifierDistanceCrossCountrySkiing` | m |
| `distance_downhill_snow_sports` | `HKQuantityTypeIdentifierDistanceDownhillSnowSports` | m |
| `distance_skating_sports` | `HKQuantityTypeIdentifierDistanceSkatingSports` | m |

Protocol-2 clients first send `archive_capability` over the authenticated Health Bridge webhook with their device-only uploader credential. The response advertises archive schema, supported types/metrics, limits, independent archive/statistics availability, `ownership_contract_version: 1`, and this phone's ownership state/generation. An unbound or replacement phone requests `archive_owner_claim`; a Home Assistant administrator compares the short fingerprint shown on phone and archive card, then explicitly approves the first binding or transfer. Only the approved phone may send `archive_batch`, `archive_status`, or `archive_inventory`. Transfer revokes the prior credential but preserves old-phone-only originals. `archive_batch` carries one sample type, bounded original quantity/category/workout records with UUID, interval, source and unit/detail provenance, deletions, and per-type coverage. The client advances coverage or anchor only after an exact committed request and batch acknowledgement. The fork stores originals and receipts outside recorder; projection may still be pending or failed, so `archive_status` and actual readback establish statistics completion. Revision-guarded `archive_inventory` and conditional deletion-only batches also bind to the approved owner generation. A missing iOS 27 read boundary can mean full access or denied access, so absence-based tombstones pause unless the boundary is proved. This is not inferred from an empty sample query.

Originals remain queryable after recorder purge through the authenticated administrator archive API/card and export as JSON Lines, including non-secret uploader-generation provenance. User-scoped archive deletion is an explicit administrator action and does not erase recorder statistics/history or backups. Revoking HealthKit access does not erase an archive. Medication records use the existing separate opt-in authorization/live flow; they are not part of protocol-2 original-sample import. The iOS app falls back to the 14-day protocol-1 recorder import when iOS 27 or an ownership-contract-compatible protocol 2 fork is unavailable, while live protocol 1 remains usable. One approved iPhone per Health Bridge user is enforced for version-2 archive operations; a second phone cannot perform archive deletion merely because its HealthKit library differs.

The protocol-1 figures and examples below are retained as historical source evidence for v1.2.1. For current v2.1.0/fork limits and behavior, use the supplement above and the fork's canonical documents.

This document separates the wire contract confirmed in the Health Bridge repository from Apple platform behavior confirmed in Apple documentation. Repository code, not the companion app's behavior or this document, remains the protocol source of truth.

## Source snapshot

- GitHub reports `main` as the default branch. Its inspected HEAD was [`3d227252e80cdd42827f026082230215197bd583`](https://github.com/gregt1993/Health_Bridge/commit/3d227252e80cdd42827f026082230215197bd583) (`Update README.md`, 2026-08-23).
- GitHub's latest release was [`v1.2.1`](https://github.com/gregt1993/Health_Bridge/releases/tag/v1.2.1), whose tag resolves to [`8e28ccb1c7d96f73c89de7698b39562530998fb6`](https://github.com/gregt1993/Health_Bridge/commit/8e28ccb1c7d96f73c89de7698b39562530998fb6) (`Add sleep_unspecified_hours and sleep_details metrics`, 2026-08-23).
- Integration version: **1.2.1**, from [`manifest.json`](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/manifest.json#L1-L12).
- Live protocol version: **1**, from [`_LIVE_PROTOCOL_VERSION`](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L71-L75).
- Backfill protocol version: **1**, from [`BACKFILL_PROTOCOL_VERSION`](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/history_backfill.py#L24-L40).
- The required Python files and manifest have identical Git blob IDs on `main` and `v1.2.1`. The required README differs only by one recommendation added on `main` (add a lock-screen widget); that change is not part of the protocol. The inspected [`README.md`](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/README.md) documents setup but does not document the versioned live or backfill wire contracts.

The five required files were read in full at both refs: `custom_components/health_bridge/__init__.py`, `const.py`, `history_backfill.py`, `manifest.json`, and `README.md`.

## Webhook endpoint and authentication

The integration registers webhook ID `health_bridge`; Home Assistant exposes registered webhook IDs at:

```text
POST <normalized-base-url>/api/webhook/health_bridge
Content-Type: application/json
```

The registration is source-confirmed in [`_setup_webhook`](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L402-L438) and at the [`async_register` call](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L680-L682).

The JSON body carries the integration secret in `token`. The integration trims leading/trailing whitespace from both the configured and received token, compares them before state mutation, and returns HTTP 401 with plain text `invalid token` on failure. This token is not a Home Assistant REST bearer token. `user_id` comes from the body and defaults to `unknown` for live requests; backfill separately requires a nonempty string of at most 128 characters. [Authentication and routing source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L417-L445).

There is no separate display-name field in the repository contract. For live requests, the integration uses `user_id` in the device name, entity unique IDs, and suggested object IDs. The app may label this setting for humans, but it must send the configured identifier as `user_id` and should restrict it to a conservative slug even though live code does not validate it.

## Versioned live request

Use the explicit versioned form:

```json
{
  "token": "example-secret",
  "user_id": "example-user",
  "request_type": "live",
  "protocol_version": 1,
  "request_id": "live.20260827T200000Z.01234567",
  "data": {
    "steps": [
      {
        "timestamp": "2026-08-27T20:00:00Z",
        "value": 8421
      }
    ]
  }
}
```

Confirmed semantics:

- `request_type` defaults to `live` when missing or falsey, but new clients should send it explicitly.
- Sending either `request_id` or `protocol_version` opts into explicit-live validation, after which both must be valid. `protocol_version` must equal integer `1`.
- `request_id` must match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`: 1–64 ASCII letters/digits/dot/underscore/hyphen, beginning with a letter or digit.
- `data` must be a nonempty JSON object. For ordinary metrics, the value is a nonempty array of datapoint objects. The integration uses **only the last array element** and does not sort it; therefore the client must place the intended current value last.
- An ordinary datapoint uses `value` for sensor state and `timestamp` as its state timestamp. A missing/null `value` skips that top-level metric.
- The live handler does not reject unknown metric keys; it creates them with empty metadata. The canonical supported set and units are nevertheless the registry in `const.py`, and clients should send only that set plus the separately handled `medications` key.

These rules are implemented in [live metadata validation](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L440-L492) and [metric application](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L567-L639).

Legacy live payloads that omit both `request_id` and `protocol_version` remain accepted. Their response still reports live protocol `1` but echoes `request_id: null`. Do not use this mode: it cannot prove request/acknowledgement correspondence.

### Successful live acknowledgement

HTTP success alone is insufficient. A successful applied request returns HTTP 200 with this shape:

```json
{
  "ok": true,
  "applied": true,
  "integration_version": "1.2.1",
  "request_type": "live",
  "protocol_version": 1,
  "request_id": "live.20260827T200000Z.01234567",
  "received_entities": 1,
  "updated_entities": 1,
  "skipped_entities": 0,
  "last_sync_updated": true
}
```

The client must require `ok == true`, `applied == true`, `request_type == "live"`, protocol `1`, exact request-ID equality, and `updated_entities > 0`. `integration_version` can be null if Home Assistant could not load it. `last_sync_updated` can legitimately be false because the integration rate-limits the synthetic `last_sync_time` entity to one update per 10 seconds; it is not the live commit flag. `received_entities` counts top-level keys, while medication updates count each accepted medication in `updated_entities`, so the three counts are diagnostics rather than an invariant sum. [Acknowledgement source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L641-L678).

If zero entities are applied, the integration returns HTTP 422 and:

```json
{
  "ok": false,
  "applied": false,
  "error": "no_entities_applied",
  "request_type": "live",
  "protocol_version": 1,
  "request_id": "live.20260827T200000Z.01234567",
  "received_entities": 1,
  "updated_entities": 0,
  "skipped_entities": 1
}
```

Do not advance HealthKit anchors for this response.

### Live error responses

| HTTP | Body | Meaning |
|---:|---|---|
| 400 | `{"ok":false,"error":"invalid_payload"}` | Top-level parsed JSON is not an object. |
| 401 | plain text `invalid token` | Missing/mismatched webhook secret. |
| 422 | `unsupported_request_type` | `request_type` is neither `live` nor `backfill`. |
| 422 | `invalid_health_data` | `data` is not an object. |
| 422 | `unsupported_live_protocol` | Explicit live protocol is not integer `1`. |
| 422 | `invalid_request_id` | Explicit live request ID fails the regex. |
| 422 | `empty_health_data` | `data` is empty/falsey. |
| 422 | `no_entities_applied` plus counts | Nothing reached a runtime entity. |
| 503 | `sensor_platform_not_ready` | Integration sensor callbacks are not ready. |

Malformed JSON is logged and the handler returns `None`; the source does not establish a stable JSON/status contract for that case. Treat any non-JSON or otherwise unmatched response as failure. [Error branches](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L406-L492).

### Webhook connection test

Any `data` object containing a `test_connection` key takes the connection-test branch after token and explicit-live metadata validation. A fixture-compatible body is:

```json
{
  "token": "example-secret",
  "user_id": "example-user",
  "request_type": "live",
  "protocol_version": 1,
  "request_id": "test.01234567",
  "data": { "test_connection": [{ "value": true }] }
}
```

Its HTTP 200 response is:

```json
{
  "ok": true,
  "integration_version": "1.2.1",
  "backfill_protocol": 1,
  "backfill_ack": "committed",
  "statistics_policy": "history_only"
}
```

This special response does not echo the live `request_id` or live protocol and does not contain `applied`; validate it as a distinct connection-test contract, not as a live-sync acknowledgement. It also creates a persistent Home Assistant notification. [Connection-test source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L471-L486).

## Canonical metric identifiers and output units

The integration's canonical registry contains 92 keys. Units below are the resulting Home Assistant native units declared by [`METRIC_ATTRIBUTES_MAP`](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/const.py#L20-L561). “None” means no unit. “Backfill” is source-derived: a canonical metric is eligible only when its registry entry has a truthy `state_class`.

| Category | Health Bridge identifier | Home Assistant native unit | Backfill |
|---|---|---:|:---:|
| Internal | `last_sync_time` | None (timestamp) | No |
| Workout | `last_apple_workout` | None (text + attributes) | No |
| Activity | `steps` | steps | Yes |
| Activity | `distance` | m | Yes |
| Activity | `active_calories` | kcal | Yes |
| Activity | `flights_climbed` | floors | Yes |
| Activity | `walking_speed` | m/s | Yes |
| Activity | `walking_step_length` | m | Yes |
| Activity | `walking_asymmetry_percentage` | % | Yes |
| Activity | `walking_double_support_percentage` | % | Yes |
| Activity | `swimming_distance` | m | Yes |
| Activity | `cycling_distance` | m | Yes |
| Activity | `wrist_temperature` | °C | Yes |
| Activity | `walking_steadiness` | % | Yes |
| Activity | `cardio_recovery` | bpm | Yes |
| Activity | `physical_effort` | MET | Yes |
| Activity | `insulin_delivery` | IU | Yes |
| Activity | `six_minute_walk_test_distance` | m | Yes |
| Activity | `stair_ascent_speed` | m/s | Yes |
| Activity | `stair_descent_speed` | m/s | Yes |
| Body | `body_mass` | kg | Yes |
| Body | `height` | m | Yes |
| Body | `body_fat_percentage` | % | Yes |
| Body | `lean_body_mass` | kg | Yes |
| Body | `waist_circumference` | m | Yes |
| Vitals | `body_temperature` | °C | Yes |
| Vitals | `heart_rate` | bpm | Yes |
| Vitals | `resting_heart_rate` | bpm | Yes |
| Vitals | `walking_heart_rate_average` | bpm | Yes |
| Vitals | `heart_rate_variability` | ms | Yes |
| Vitals | `vo2_max` | mL/kg/min | Yes |
| Vitals | `blood_pressure_systolic` | mmHg | Yes |
| Vitals | `blood_pressure_diastolic` | mmHg | Yes |
| Vitals | `oxygen_saturation` | % | Yes |
| Vitals | `uv_index` | None | Yes |
| Vitals | `uv_exposure_sed` | SED | Yes |
| Vitals | `net_calories` | kcal | Yes |
| Nutrition | `dietary_carbohydrates` | g | Yes |
| Nutrition | `dietary_fat` | g | Yes |
| Nutrition | `dietary_protein` | g | Yes |
| Nutrition | `dietary_water` | mL | Yes |
| Lab | `blood_glucose` | mmol/L | Yes |
| Activity | `basal_energy_burned` | kcal | Yes |
| Sleep | `sleep_duration` | h | Yes |
| Sleep | `sleep_rem_hours` | h | Yes |
| Sleep | `sleep_core_hours` | h | Yes |
| Sleep | `sleep_deep_hours` | h | Yes |
| Sleep | `sleep_awake_hours` | h | Yes |
| Sleep | `sleep_unspecified_hours` | h | Yes |
| Sleep | `sleep_details` | stage | Yes |
| Breathing | `respiratory_rate` | breaths/min | Yes |
| Mindfulness | `mindful_minutes` | s | Yes |
| Activity | `time_in_daylight` | s | Yes |
| Sleep | `asleep_time` | None (timestamp) | No |
| Sleep | `wake_time` | None (timestamp) | No |
| Audio | `headphone_audio_exposure` | dBA | Yes |
| Audio | `environmental_audio_exposure` | dBA | Yes |
| Activity | `stand_time` | min | Yes |
| Activity | `exercise_time` | min | Yes |
| Nutrition | `dietary_energy_consumed` | kcal | Yes |
| Nutrition | `dietary_fiber` | g | Yes |
| Nutrition | `dietary_sugar` | g | Yes |
| Nutrition | `dietary_cholesterol` | mg | Yes |
| Nutrition | `dietary_calcium` | mg | Yes |
| Nutrition | `dietary_chloride` | mg | Yes |
| Nutrition | `dietary_iron` | mg | Yes |
| Nutrition | `dietary_magnesium` | mg | Yes |
| Nutrition | `dietary_manganese` | mg | Yes |
| Nutrition | `dietary_phosphorus` | mg | Yes |
| Nutrition | `dietary_potassium` | mg | Yes |
| Nutrition | `dietary_sodium` | mg | Yes |
| Nutrition | `dietary_zinc` | mg | Yes |
| Nutrition | `dietary_caffeine` | mg | Yes |
| Nutrition | `dietary_copper` | mg | Yes |
| Nutrition | `dietary_niacin` | mg | Yes |
| Nutrition | `dietary_pantothenic_acid` | mg | Yes |
| Nutrition | `dietary_riboflavin` | mg | Yes |
| Nutrition | `dietary_thiamin` | mg | Yes |
| Nutrition | `dietary_vitamin_b6` | mg | Yes |
| Nutrition | `dietary_vitamin_c` | mg | Yes |
| Nutrition | `dietary_vitamin_e` | mg | Yes |
| Nutrition | `dietary_biotin` | µg | Yes |
| Nutrition | `dietary_chromium` | µg | Yes |
| Nutrition | `dietary_folate` | µg | Yes |
| Nutrition | `dietary_iodine` | µg | Yes |
| Nutrition | `dietary_molybdenum` | µg | Yes |
| Nutrition | `dietary_selenium` | µg | Yes |
| Nutrition | `dietary_vitamin_a` | µg | Yes |
| Nutrition | `dietary_vitamin_b12` | µg | Yes |
| Nutrition | `dietary_vitamin_d` | µg | Yes |
| Nutrition | `dietary_vitamin_k` | µg | Yes |
| Internal | `test_connection` | None | No |

`medications` is a special live payload key and is not in `SUPPORTED_METRICS`. Dynamic sensors named `medication_<id>` also are not backfill-eligible.

### Important prompt-to-wire mappings

- Walking/running distance → `distance` in metres.
- Basal calories → `basal_energy_burned` in kilocalories.
- Blood oxygen → `oxygen_saturation` as the fractional input described below.
- Wrist temperature → `wrist_temperature` in degrees Celsius.
- Sleep start → `asleep_time`; wake time → `wake_time`.
- Dietary energy → `dietary_energy_consumed` in kilocalories.
- Blood glucose → `blood_glucose` in mmol/L. A comment in `const.py` says a normalizer converts mg/dL, but the inspected `_normalize_metric_value` implementation has no blood-glucose conversion; mmol/L is therefore the only source-backed wire unit.
- Last workout → `last_apple_workout` special structure.

### Percentage normalization

For `body_fat_percentage`, `walking_asymmetry_percentage`, `walking_double_support_percentage`, `oxygen_saturation`, and `walking_steadiness`, Health Bridge implements this exact transform for both live and backfill:

- numeric `0.0...1.0` → multiply by 100;
- below `0` → clamp to `0`;
- above `100` → clamp to `100`;
- numeric greater than `1` through `100` → leave as supplied.

Therefore the app should send HealthKit fractions (for example `0.975`, not `97.5`) for these metrics. The boundary value `1.0` becomes `100`, which makes an already-percent value of exactly `1` ambiguous; always use the HealthKit fraction convention. [Normalization source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L84-L130).

### Sleep normalization and stage encoding

`sleep_duration`, `sleep_rem_hours`, `sleep_core_hours`, `sleep_deep_hours`, `sleep_awake_hours`, and `sleep_unspecified_hours` must be sent in **seconds**. The integration divides by 3,600 and rounds to two decimal places, while the resulting Home Assistant sensors declare hours. `mindful_minutes` and `time_in_daylight` are different: despite their friendly names, their registry unit is seconds and the integration does not convert them. `stand_time` and `exercise_time` are minutes and are not converted.

`sleep_details` is a numeric hypnogram state code: deep `0`, core/light `1`, REM `2`, awake `3`, unspecified `-1`. These are Health Bridge codes and must be explicitly mapped from `HKCategoryValueSleepAnalysis`; do not transmit Apple's enum raw values by assumption. Each datapoint still uses `timestamp`/`value`. [Sleep unit/normalization source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L76-L92), [stage-code source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/const.py#L318-L330).

The live handler retains only the last `sleep_details` datapoint, so a complete hypnogram requires the experimental backfill protocol; repeated live calls otherwise update current state only.

## Workout structure

The outer value must be a nonempty array; the handler reads its last dictionary even though a nearby source comment calls the workout “a single dict.” This is the safe shape:

```json
{
  "last_apple_workout": [
    {
      "workout_type": "Running",
      "start_time": "2026-08-27T18:00:00Z",
      "end_time": "2026-08-27T18:45:00Z",
      "last_synced": "2026-08-27T20:00:00Z",
      "duration_min": 45.0,
      "distance_km": 8.2,
      "active_energy_kcal": 510.0,
      "average_heart_rate_bpm": 154.0,
      "max_heart_rate_bpm": 178.0
    }
  ]
}
```

Source-confirmed requirements and behavior:

- `workout_type` is required for an applied value.
- State timestamp is `last_synced`, falling back to `end_time`.
- The text state is composed from `workout_type`, then optional `duration_min`, positive `distance_km`, positive `active_energy_kcal`, and positive `average_heart_rate_bpm`.
- Every supplied workout field is retained as a sensor attribute. The built-in card additionally consumes `start_time`, `end_time`, and `max_heart_rate_bpm`, making the example above the repository-consumer-compatible shape.
- The integration does not schema-validate units, dates, or numeric fields. The app must validate them before sending.

[Workout handler and state composer](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L572-L592), [built-in card fields](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/cards/health-bridge-cards.js#L959-L1020).

## Medication structure (iOS 26+)

`medications` is an array of per-medication dictionaries, not timestamp/value datapoints:

```json
{
  "medications": [
    {
      "id": "stable-medication-id",
      "state": "taken",
      "name": "Example medication",
      "taken": 1,
      "scheduled": 1,
      "dose_taken": 500,
      "unit": "mg",
      "summary": "1 of 1 taken"
    }
  ]
}
```

Only `id` (truthy) and `state` (non-null) are required by the integration. It creates one text sensor named from `medication_<id>` whose state is the supplied `state`; all keys other than `id` and `state` become attributes. `name` controls display naming when present. The comment names `pending`, `partial`, and `taken` as intended states and `taken`, `scheduled`, `dose_taken`, `unit`, and `summary` as example attributes, but the implementation does not enforce an enum or attribute schema. Malformed array members are silently ignored and are not reliably reflected in `skipped_entities`. [Medication source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L517-L565).

This wire shape is Health Bridge-specific. It is not the shape of Apple's medication objects.

## Experimental backfill protocol

Backfill is explicitly isolated around unsupported Home Assistant recorder internals. Live sync never invokes those internals unless `request_type` is exactly `backfill`; incompatibility disables backfill without disabling live sync. The module itself describes the behavior as atomic, recorder-queued, fail-closed, and idempotent by entity plus rounded sample second. [Module contract](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/history_backfill.py#L1-L11).

### Request

```json
{
  "token": "example-secret",
  "user_id": "example-user",
  "request_type": "backfill",
  "protocol_version": 1,
  "request_id": "backfill.20260827.01234567",
  "data": {
    "steps": [
      { "timestamp": "2026-08-26T20:00:00Z", "value": 7000 },
      { "timestamp": "2026-08-27T20:00:00Z", "value": 8421 }
    ]
  }
}
```

Constraints:

- Same token authentication and request-ID regex as live; protocol must be integer `1`.
- `user_id` must be nonempty and at most 128 characters.
- `data` must be a nonempty object. Each key must exist in the canonical registry and have a `state_class`; text and timestamp sensors, workouts, and medication sensors are ineligible.
- A live sensor for every metric must already exist. It must also have reached recorder metadata and have a recorded state with attributes.
- Every metric array must contain at least two points. The validation error describes these as one historical point and one live point, but the implementation enforces only the count; the client should still include the current live point so the recorded history joins the live entity state coherently.
- Maximum 721 received points per entity and 2,500 received points per request. Limits are checked before deduplication.
- Timestamps may be numeric epoch seconds or ISO-8601 strings. A timezone-less ISO timestamp is interpreted as UTC. Values must become finite numbers after the same percentage/sleep normalization used by live sync.
- Latest timestamp may be at most 5 minutes in the future. Earliest point and total span are bounded to 14 days plus a 15-minute request-age grace.
- Points are deduplicated by rounded epoch second within a request (last encountered point for that second wins), then against existing recorder rows by entity and rounded second.
- The whole batch is one recorder-thread transaction. Any insert failure rolls back it all.
- Recorder must be ready, recording, not migrating, have backlog at most 1,000, and include every entity. Commit wait timeout is 45 seconds.
- Compatibility is pinned to **recorder schema 53** and **SQLite only**. MariaDB/MySQL and PostgreSQL are rejected, as is any unapproved schema or changed required `States` model.
- Rows are inserted into state history only; `statistics_policy` is `history_only`, so the protocol does not populate Home Assistant long-term statistics.

[Request preparation](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L184-L242), [limits and validation](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/history_backfill.py#L24-L40), [series validation](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/history_backfill.py#L102-L184), [recorder compatibility](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/history_backfill.py#L187-L250), [atomic/idempotent insert](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/history_backfill.py#L299-L417).

### Committed acknowledgement

```json
{
  "ok": true,
  "committed": true,
  "protocol_version": 1,
  "request_id": "backfill.20260827.01234567",
  "recorder_schema": 53,
  "database": "sqlite",
  "received": 2,
  "inserted": 2,
  "skipped": 0,
  "entities": 1,
  "statistics_policy": "history_only"
}
```

Require `ok`, `committed`, protocol, and exact request-ID equality. A valid idempotent retry can commit with `inserted == 0` and all points counted as `skipped`; that is still a successful committed acknowledgement. [Acknowledgement source](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/history_backfill.py#L73-L99).

### Backfill errors

All stable backfill error bodies contain `ok:false`, `committed:false`, `protocol_version:1`, `error`, and `message`, but do **not** echo `request_id`:

| HTTP | `error` | Retry unchanged? |
|---:|---|---|
| 422 | `invalid_backfill` | No. Fix request. |
| 503 | `entity_not_ready` | Yes, after live entity/recorder becomes ready. |
| 409 | `unsupported_recorder` | No until integration compatibility changes. Disable experimental backfill; retain live sync. |
| 503 | `recorder_unavailable` | Yes, bounded retry. |
| 500 | `backfill_commit_failed` | Potentially transient; retry only with bounded policy and the same request ID. |

[Error response and mapping](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L148-L159), [handler mapping](https://github.com/gregt1993/Health_Bridge/blob/3d227252e80cdd42827f026082230215197bd583/custom_components/health_bridge/__init__.py#L245-L273).

## Apple platform contract and limitations

This section is platform guidance, not Health Bridge wire protocol.

### Authorization

Apple requires fine-grained read and share authorization per HealthKit type, `HKHealthStore.isHealthDataAvailable()` before other HealthKit calls, the HealthKit capability, and both read/write usage descriptions when those operations are requested. Apple explicitly recommends requesting only the types needed rather than everything at once. A successful authorization request means the sheet completed without an authorization-processing error; it does not reveal whether read permission was granted. People may grant only a limited recent history window, and can change permissions later. [Apple: Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [Apple: `requestAuthorization`](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization%28toshare%3Aread%3Acompletion%3A%29).

Implementation consequence: selection must drive the requested read set; Home Assistant→HealthKit pairings independently drive the share set. Empty query results cannot be presented as proof of denial.

### Anchored and observer queries

`HKAnchoredObjectQuery` returns saved samples, deleted objects, and a new anchor. Reusing that anchor limits later results to objects newer than the previous result; a nil anchor starts from the available history. [Apple: `HKAnchoredObjectQuery`](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery), [Apple: anchored initializer](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery/init%28type%3Apredicate%3Aanchor%3Alimit%3Aresultshandler%3A%29).

Apple's anchor is only a HealthKit cursor. Apple does not define transactional behavior with a remote destination. Committing the serialized anchor only after a matching Health Bridge applied acknowledgement is therefore this app's required durability policy, not an Apple guarantee. Deleted objects must be processed before advancing the committed anchor.

An `HKObserverQuery` tells the app only that matching data changed; it does not carry the changed samples, so the app must run another query such as an anchored query. For background delivery, set observer queries up during app launch, enable background delivery for the same types, and call every observer completion handler after processing. Apple warns that failing to call it causes backoff and, after three failures, HealthKit stops background updates. [Apple: Executing Observer Queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries), [Apple: `enableBackgroundDelivery`](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery%28for%3Afrequency%3Awithcompletion%3A%29).

Background delivery requires the `com.apple.developer.healthkit.background-delivery` entitlement on current iOS. Its frequency is a **maximum notification frequency**, not a schedule or 30-minute guarantee. Background HealthKit delivery is unsupported in Simulator and must be tested on a physical device.

When locked, HealthKit reads may fail with `errorDatabaseInaccessible`; Apple encrypts the store while locked. Preserve the anchor, complete the observer callback correctly, and retry on a later opportunity. [Apple: `errorDatabaseInaccessible`](https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible), [Apple: Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy).

Apple's reviewed documentation does not promise HealthKit observer execution after the user force-quits the app. Correctness therefore means catching up from the committed anchor on a later launch/manual/Shortcut/background opportunity, not promising a force-quit schedule.

### BackgroundTasks is secondary

Apple says the system chooses when `BGAppRefreshTask`/`BGProcessingTask` runs. App refresh is a short opportunity (up to about 30 seconds in the cited guidance), must honor expiration/cancellation, and is not a precise timer. It is appropriate as a secondary catch-up path, not the primary HealthKit change signal. [Apple: Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app), [Apple: Using background tasks](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app).

### Sleep

HealthKit sleep uses `HKCategoryType.sleepAnalysis` and category values for in-bed, awake, core, deep, REM, and asleep-unspecified. Apple explicitly permits an in-bed sample to overlap the detailed stage partition, while detailed stage samples should not overlap each other; Apple Watch can omit detailed awake samples at session edges. Apple recommends time-zone metadata for sleep samples. [Apple: `HKCategoryValueSleepAnalysis`](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis), [Apple: `sleepAnalysis`](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis).

Implementation consequence: do not naively sum in-bed plus stage records. Deduplicate/merge source intervals, derive asleep totals from asleep-stage unions, and map HealthKit categories explicitly to Health Bridge's stage codes.

### Workouts

`HKSampleQuery` can query `HKWorkout` samples and supports sort/limit for the latest result. Current workout summaries expose activity type, duration, start/end dates, and `statistics(for:)`/`allStatistics`; Apple has deprecated the old `totalDistance` and `totalEnergyBurned` convenience properties in favor of statistics. [Apple: `HKSampleQuery`](https://developer.apple.com/documentation/healthkit/hksamplequery), [Apple: `HKWorkout`](https://developer.apple.com/documentation/healthkit/hkworkout), [Apple: workout activity type](https://developer.apple.com/documentation/healthkit/hkworkout/workoutactivitytype).

The app only reads and summarizes the latest workout; it does not need to create workout sessions. If workout creation is ever added, Apple recommends the workout builder APIs so activity rings update correctly. [Apple WWDC25: Track workouts with HealthKit](https://developer.apple.com/videos/play/wwdc2025/322/).

### Writable destinations and idempotency

Apple's authorization API accepts concrete `HKSampleType` subclasses in the share set, and saving follows each type's documented sample subclass and compatible units. This does **not** imply every HealthKit type is writable. Apple marks individual computed/system types as read-only—for example Apple Walking Steadiness and sleeping wrist temperature cannot be requested for sharing. Clinical records are also read-only. [Apple: Saving data to HealthKit](https://developer.apple.com/documentation/healthkit/saving-data-to-healthkit), [Apple: Walking Steadiness](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applewalkingsteadiness), [Apple: sleeping wrist temperature](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingwristtemperature), [Apple: Accessing Health Records](https://developer.apple.com/documentation/healthkit/accessing-health-records).

Implementation consequence: maintain an explicit, tested writable allowlist based on each destination identifier's Apple documentation. Never infer writability from the fact that a Health Bridge metric is readable, has a numeric unit, or exists in `HKObjectType`. Hide all unverified/read-only/computed destinations.

For imported Home Assistant samples, use `HKMetadataKeySyncIdentifier` together with `HKMetadataKeySyncVersion`. HealthKit uses matching identifiers and increasing versions to prevent duplicates or replace older versions. [Apple: `HKMetadataKeySyncIdentifier`](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier), [Apple: `HKMetadataKeySyncVersion`](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncversion), [Apple WWDC20: Synchronize health data with HealthKit](https://developer.apple.com/videos/play/wwdc2020/10184/).

### Medications (iOS 26+)

Apple's medication APIs are read APIs introduced with iOS 26. `HKUserAnnotatedMedication` describes an authorized medication and customizations; `HKMedicationDoseEvent` is an `HKSample` for scheduled/logged doses. Medication objects require per-object read authorization: the user chooses individual medications, and authorizing one also grants read access to its dose events. Dose events can be queried with sample, anchored, and observer queries; they may be logged retroactively, edited as delete/re-persist operations, or exist for reminders that were never interacted with. [Apple WWDC25: Meet the HealthKit Medications API](https://developer.apple.com/videos/play/wwdc2025/321/).

Use `if #available(iOS 26, *)`. Process medication deletes and edits from anchored results, use the medication concept identifier as the stable relationship key, and transform Apple objects into the separate Health Bridge `medications` dictionary contract. The reviewed Apple sources document reading medications/dose events, not third-party creation of medications or dose events; do not expose medication writes without separate affirmative API documentation.

### App Intents and App Shortcuts

An action conforms to `AppIntent`, returns a result indicating success/failure, and becomes a preconfigured Shortcut through an `AppShortcutsProvider` whose `appShortcuts` supply localized title/description and invocation phrases. [Apple: App intents](https://developer.apple.com/documentation/appintents/app-intents), [Apple: Getting started with App Intents](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework), [Apple: `AppShortcutsProvider`](https://developer.apple.com/documentation/appintents/appshortcutsprovider).

Implementation consequence: `SyncHealthWithHomeAssistantIntent` should call the same actor-isolated coordinator as foreground/background sync and return only privacy-safe summary text. App Intent availability does not override HealthKit authorization, protected-data, network, or iOS background-execution limits.

## Compatibility decisions for Vital Relay

1. Pin fixtures and acknowledgement validators to live protocol 1/backfill protocol 1, but decode additive response fields permissively.
2. Generate request IDs from a safe prefix plus UUID/timestamp characters and cap at 64 characters.
3. Treat only a matched, applied live acknowledgement as permission to commit an outbound HealthKit anchor.
4. Keep the webhook secret and Home Assistant bearer token in separate credential slots and request paths.
5. Preserve per-metric anchors across non-JSON responses, HTTP errors, `applied:false`, mismatches, cancellation, locked-store errors, and transient network failure.
6. Treat backfill as experimental and capability-probed. Disable it for any database other than SQLite, recorder schema other than 53, or `unsupported_recorder`, while leaving live sync enabled.
7. Use a curated HealthKit-write allowlist, stable sync metadata, pairing checkpoints, and source metadata to prevent Home Assistant→HealthKit duplicates and feedback loops.
8. Make no background-frequency guarantee. Surface registration state and attempt/success/error timestamps, and require the documented 24-hour physical-device observation before any reliability claim.
9. Send one ordinary metric per live request. The acknowledgement exposes only aggregate counts, so a multi-metric request cannot prove which individual metric was accepted before committing that metric's anchor. Require `received_entities == 1`, `updated_entities == 1`, and `skipped_entities == 0` for an ordinary metric; validate the medication collection against its separately counted updates.
10. Recompute an authoritative current value after HealthKit deletions. The live protocol can replace a deleted latest sample with the next-latest value and can publish zero for an emptied cumulative aggregate, but it has no documented operation to clear a sensor when a latest-value metric has no remaining sample. Treat that edge as a visible compatibility limitation rather than sending an undocumented sentinel or forking the integration in the first milestones.
