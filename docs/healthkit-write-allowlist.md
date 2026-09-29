# HealthKit Write Allowlist

Verified on 2026-08-28 against Apple's current HealthKit documentation and the installed iOS 26.5 SDK. This is an explicit allowlist for generic numeric Home Assistant imports; the app does not infer writability from an outbound metric or from an identifier merely existing.

Apple documents the supported save sequence as creating the matching type, quantity, and `HKQuantitySample`, requesting share authorization, then calling `HKHealthStore.save`. Apple's quantity-sample documentation specifically uses height, heart rate, and dietary calories as writable examples. See [Saving data to HealthKit](https://developer.apple.com/documentation/healthkit/saving-data-to-healthkit), [`HKQuantitySample`](https://developer.apple.com/documentation/healthkit/hkquantitysample), and [quantity type identifiers](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier).

The installed SDK evidence is `HealthKit.framework/Headers/HKTypeIdentifiers.h` in `iPhoneSimulator26.5.sdk`. It declares every identifier below as an available numeric quantity type and states its compatible unit and aggregation style. The production adapter still requests only the destination's write permission and treats authorization or save rejection as a failure.

| Destination | Native app unit | Bounds | SDK availability | Apple type evidence |
| --- | --- | ---: | --- | --- |
| Body mass | kg | 0.5–700 | iOS 8 | [`bodyMass`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodymass) |
| Height | m | 0.2–3 | iOS 8 | [`height`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/height) |
| Body fat percentage | fraction | 0–1 | iOS 8 | [`bodyFatPercentage`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodyfatpercentage) |
| Lean body mass | kg | 0.1–500 | iOS 8 | [`leanBodyMass`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/leanbodymass) |
| Body temperature | °C | 20–50 | iOS 8 | [`bodyTemperature`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodytemperature) |
| Heart rate | count/min | 10–350 | iOS 8 | [`heartRate`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartrate) |
| Oxygen saturation | fraction | 0–1 | iOS 8 | [`oxygenSaturation`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/oxygensaturation) |
| Respiratory rate | breaths/min | 1–100 | iOS 8 | [`respiratoryRate`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/respiratoryrate) |
| UV exposure | unitless UV index (HealthKit count) | 0–50 | iOS 9 | [`uvExposure`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/uvexposure) |
| Dietary water | mL | 0–100,000 | iOS 9 | [`dietaryWater`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietarywater) |
| Dietary energy | kcal | 0–100,000 | iOS 8 | [`dietaryEnergyConsumed`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietaryenergyconsumed) |
| Blood glucose | mmol/L | 0.1–100 | iOS 8 | [`bloodGlucose`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bloodglucose) |
| Dietary carbohydrates | g | 0–10,000 | iOS 8 | [`dietaryCarbohydrates`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietarycarbohydrates) |
| Dietary fat | g | 0–10,000 | iOS 8 | [`dietaryFatTotal`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietaryfattotal) |
| Dietary protein | g | 0–10,000 | iOS 8 | [`dietaryProtein`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietaryprotein) |
| Insulin delivery | IU | 0–10,000 | iOS 11 | [`insulinDelivery`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/insulindelivery) |

## Explicitly excluded

The generic picker excludes Apple exercise time, Apple stand time, resting and walking heart-rate averages, VO2 max, walking steadiness, sleeping wrist temperature, clinical records, medications, sleep analysis, workouts, and every unreviewed type. These include computed or read-only types and specialized records that require semantics beyond a numeric `HKQuantitySample`.

## Conversion policy

The core converter accepts only typed `UnitSymbol` values. It supports compatible conversions for mass, length, temperature, energy, volume, glucose concentration, fraction/percent, time, heart rate, respiratory rate, international units, and unitless UV index values. It rejects unknown dimensions, cross-dimension conversion, and any non-finite input or result. Pairing validation applies a bounded transform first, conversion second, and the destination's native-unit bounds last. For UV index sensors that omit `unit_of_measurement`, an absent or empty source unit is accepted only when the pairing explicitly uses the unitless source unit.

This simulator-backed evidence verifies type construction and policy only. A physical iPhone is still required to verify the authorization sheet and an actual save for every destination.
