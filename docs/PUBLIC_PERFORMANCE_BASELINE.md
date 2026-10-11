# Revisr Phase 4 performance baseline

Measured 10 October 2026 before broad optimisation, with an 11 October source-only update. The source-tree resource count is available; runtime timings are currently blocked by an unstable CoreSimulatorService.

| Area | Method | Result | Status |
|---|---|---|---|
| Toolchain | `xcode-select -p`, `xcodebuild -version` | Xcode 26.6, build 17F113 | measured |
| Simulator inventory | `xcrun simctl list devices available` | iOS 26.2 and 26.5 devices enumerated at one point | intermittent |
| Cross-project check | `xcodebuild -list -project /Users/kushagra/Documents/calculock/Calculock.xcodeproj` | Same CoreSimulatorService failure, so not Revisr-specific | measured |
| Reversible recovery | Quit/relaunch Simulator app; no device erase/reset | Service still failed immediately on `simctl` | failed |
| Privileged recovery | Targeted `launchctl` restart requested | Escalation review rejected because of environment usage limit; no command executed | blocked |
| Full tests | unsigned Debug simulator `xcodebuild test` | CoreSimulatorService connection lost before destination selection | blocked |
| Targeted Phase 3 tests | existing successful run | 8/8 passed | measured before Phase 4 edits |
| Resource tree | Python `Path.rglob` byte count | 445,984,453 bytes; videos are ~74% | measured |
| Cold launch | install and time first usable screen | not measured | blocked |
| SwiftData seed/fetch | instrumented runtime | not measured | blocked |
| PDF opening | instrumented runtime | not measured | blocked |
| Plan rendering | long-window runtime timing | not measured; repeated per-day filtering was removed in this pass | pending |

The Phase 4 code changes avoid adding caches or concurrency without a measurement. Plan now groups tasks by day once before building its date list. Follow-up work should repeat cold-launch, diagnostics PDF open, 730-day plan rendering and programme refresh measurements after CoreSimulatorService is stable, using the same simulator model and a clean store.

## 11 October 2026 continuation

Plan's filtering and grouping were moved out of the lazy calendar-row closure into one snapshot per `body` evaluation. This is a source-level reduction from per-date whole-list grouping to one filter/group pass plus date lookups; no timing or memory improvement is claimed without a working simulator. Progress now builds one completion snapshot per view evaluation so the completion numerator, denominator and attempt-ID set share the same filtered task state.

Fresh generic build commands attempted:

```sh
xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/revisr-ios-completion-debug-unsigned CODE_SIGNING_ALLOWED=NO build
xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/revisr-ios-completion-release-unsigned CODE_SIGNING_ALLOWED=NO build
```

Both failed during asset processing with `No available simulator runtimes for platform iphonesimulator` after CoreSimulatorService became invalid. These runs provide no source compilation, benchmark or XCTest result. Swift syntax parsing passed for 132 files; two standalone atomic-generation tests passed. A direct iOS SDK Swift typecheck attempt could not load SwiftData's `@Model` macro plugin under the sandbox (`sandbox_apply: Operation not permitted` / malformed plugin response), so type checking remains unverified. Simulator-dependent launch, scroll, PDF, scheduling refresh and memory measurements remain blocked.
