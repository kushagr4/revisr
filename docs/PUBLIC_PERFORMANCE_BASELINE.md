# Revisr Phase 4 performance baseline

Measured 10 October 2026 before broad optimisation. The source-tree resource count is available; runtime timings are currently blocked by an unstable CoreSimulatorService.

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
