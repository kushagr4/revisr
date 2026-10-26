# iOS testing policy

Permanent rule, set on 26 October 2026: **Revisr iOS testing targets iPhone 13 and newer only. No iPad testing.** It applies to every simulator run: unit tests, XCUITest, accessibility audits, screenshots and regression runs.

## Rules

- Test only on iPhone 13 or newer simulators: the iPhone 13 family and later, including e, mini, Plus, Pro, Pro Max and Air models.
- Never test on iPhone 12 or older, on iPhone SE models, or on any iPad. Never create such simulators.
- Reuse the dedicated test devices below. Do not create a simulator per test or scenario. Reset only the app's disposable test data: the UI tests' isolated stores, `--uitest-store` and `--uitest-reset`, never the student's store.
- Routine runs use one standard device. Use the larger device only when a screen-size or layout check needs it.
- Every `xcodebuild` test command names its destination explicitly, by the UDID from `Scripts/approved_simulator.py`. Do not leave the destination to Xcode's default.
- Keep simulators shut down when not in use. Delete a simulator only with the owner's approval, and only after copying any app data worth keeping.
- Native logic that needs no simulator (`docs/fixtures/run-production-logic-smoke.sh`, `Scripts/tests`) runs as normal.

## Test devices

| Role | Simulator | Model | Runtime |
|---|---|---|---|
| Standard (all routine runs) | Revisr Flexible TMUA QA | iPhone 17 Pro, 6.3" | iOS 26.5 |
| Larger layout checks only | Revisr R1 Pro Max QA | iPhone 17 Pro Max, 6.9" | iOS 26.5 |

Other simulators on this Mac (the default iPhone 17 family, iPhone 16e, iPhone Air, and "CityDone Phase11E iPhone 15 Pro") hold other projects' apps and possibly personal Revisr data. Do not use them for Revisr test runs.

## Commands

```sh
# Standard device
DEST="platform=iOS Simulator,id=$(python3 Scripts/approved_simulator.py)"
xcodebuild test -project revisr.xcodeproj -scheme revisr -destination "$DEST"            # unit tests
xcodebuild test -project revisr.xcodeproj -scheme revisrUITests -destination "$DEST"     # XCUITest

# Larger device, layout checks only
DEST="platform=iOS Simulator,id=$(python3 Scripts/approved_simulator.py --large)"
```

`approved_simulator.py` accepts only iPhone 13+ device types, and refuses iPads and SE models. If neither named device exists, it falls back to an existing approved iPhone, and it never creates a simulator.

## Product configuration (unchanged)

The app and both test targets already set `TARGETED_DEVICE_FAMILY = 1` (iPhone only), with deployment target iOS 17.0. This policy changes testing, not the product. If Revisr is published, an iPhone-only App Store app can still be installed on iPads in iPhone compatibility mode. Excluding iPads from distribution entirely is a separate product and App Store Connect decision. It has not been made, and no configuration was changed for it.

## History

- R1 (26 October 2026) ran some checks on an iPhone SE (3rd generation) simulator before this policy existed. That simulator has been deleted, and future small-screen checks need your approval first.
- The cleanup on the same day removed all iPad simulators and redundant Revisr QA simulators, after backing up their app data (see `R1_RELEASE_READINESS.md` §Simulator cleanup).
