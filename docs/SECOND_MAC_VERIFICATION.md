# Second-Mac verification runbook

Updated 11 October 2026. For a trusted Mac with healthy Xcode and simulator services. Nothing is transferred or built automatically. The iOS checkout includes third-party examination PDFs and videos whose redistribution/storage permissions remain unresolved. Keep transfer private/local until reviewed. The source-only Web handover package cannot build the complete app and has no bundled resources.

## Host and runtime prerequisites

Use Xcode 26.6 (17F113) on macOS Tahoe 26.2 or later, with the iOS 26.5 SDK and iOS 26.5 Simulator runtime. This matches the current project record and [Apple's Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes). Confirm free space against the runtime download/installation estimate shown by Xcode, plus the checkout's approximately 425.3 MiB resource tree, DerivedData, temporary stores and result bundles; the exact runtime download size is host/component dependent.

Before transfer/build, record:

```sh
sw_vers
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
xcrun simctl runtime list -v
xcrun simctl list runtimes
xcrun simctl list devices available
```

Get the iOS 26.5 runtime image identifier from verbose runtime listing and verify it:

```sh
xcrun simctl runtime verify <iOS-26.5-runtime-image-UUID>
```

Proceed only when verification succeeds and the runtime is registered. Confirm real destinations:

```sh
xcodebuild -project revisr.xcodeproj -scheme revisr -showdestinations
```

Use an available iOS Simulator UDID printed on that host; runtime `Ready` alone is not proof. Do not erase an existing device. For a clean-user walkthrough, create a separate simulator device or use a newly created test device so existing stores remain intact.

## Private branch transfer

On the source Mac, review local state and record the exact branch SHA. Use an owner-controlled encrypted removable drive for this private transfer:

```sh
git -C /Users/kushagra/Documents/revisr status --short --branch
git -C /Users/kushagra/Documents/revisr rev-parse codex/ios-completion
git -C /Users/kushagra/Documents/revisr bundle create /Volumes/<encrypted-drive>/revisr-ios.bundle codex/ios-completion main codex/public-foundation-recovered
git -C /Users/kushagra/Documents/revisr bundle verify /Volumes/<encrypted-drive>/revisr-ios.bundle
shasum -a 256 /Volumes/<encrypted-drive>/revisr-ios.bundle
```

The Git bundle preserves reachable history and the three named refs. It omits untracked workspace-state and validation-report files. Decide how to handle any intended uncommitted changes before transfer; do not accidentally include personal stores, DerivedData or recovery archives. Tracked resources, including bundled papers and videos, are reachable from these commits. Transfer only by a private trusted channel while rights review is pending.

On the second Mac, verify the received checksum and clone the selected branch:

```sh
shasum -a 256 /Volumes/<encrypted-drive>/revisr-ios.bundle
git clone --branch codex/ios-completion /Volumes/<encrypted-drive>/revisr-ios.bundle revisr
cd revisr
git status --short --branch
git rev-parse HEAD
git show-ref --heads
```

Compare HEAD with the source SHA. Keep `main` at `ae50956356403e1cdc66db117f0f37f693fa5070` and `codex/public-foundation-recovered` at `8002a6f53dd5a0423fd9bdb2a10df0d812010b0f`; do not merge either into the development branch. The untracked Xcode workspace-state path is machine-local. Xcode can recreate workspace metadata without changing tracked source.

## Build and XCTest verification

Use separate DerivedData and logs outside the checkout. Unsigned generic-device builds check iOS compilation/resources and do not install on a phone:

```sh
xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/revisr-second-mac-debug CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee /tmp/revisr-second-mac-debug.log

xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/revisr-second-mac-release CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee /tmp/revisr-second-mac-release.log
```

Run the complete XCTest target on the verified simulator and retain the result bundle:

```sh
xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Debug \
  -destination 'platform=iOS Simulator,id=<verified-device-UDID>' \
  -derivedDataPath /tmp/revisr-second-mac-tests \
  -resultBundlePath /tmp/revisr-second-mac-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee /tmp/revisr-second-mac-tests.log
xcrun xcresulttool get test-results summary --path /tmp/revisr-second-mac-tests.xcresult
```

Record exact command, exit status, Xcode/SDK/device, pass/fail/skip counts, warnings and result-bundle path. If test setup fails, mark tests blocked. Six historical migration tests still require original `.qa` fixtures; leave them unresolved if absent and do not synthesize substitutes.

## Isolated end-to-end walkthrough

Use a newly created disposable simulator with a fresh app container. Do not reset an existing device or install to a physical iPhone. Use synthetic test data and save screenshots/logs outside the repo.

For each of TMUA, SMC and BMO:

1. Complete onboarding; force quit/relaunch and verify exam, date, weekly target and availability persist.
2. Confirm the correct pair of diagnostic papers, PDF access, question navigation and durations. Verify paper two is locked until paper one completes.
3. Save an answer/proof, leave and resume. Confirm responses/notes persist and offline time is not counted.
4. Submit and self-mark TMUA/SMC. Enter only 0–10 self-estimated BMO marks. Complete both papers and inspect the report; BMO must not appear examiner-verified and evidence must be qualified.
5. Generate the personalized programme. Inspect Today, Plan, Progress and Topics. Complete one question task, relaunch, and verify completion, attempt history and progress persist.
6. Trigger a valid schedule refresh after settings/work change. Confirm completed work and history remain, future work follows the three-day freeze/settings policy, and active task IDs are unique.
7. Confirm a missing local PDF/solution blocks affected work honestly and protected, benchmark, or otherwise ineligible questions are not selected.
8. Inspect light/dark mode, standard and accessibility-large Dynamic Type, VoiceOver labels/navigation, Reduce Motion, keyboard/safe-area handling, and smaller/larger iPhone sizes. Record issues with reproduction steps.

Capture onboarding, diagnostic introduction, active papers, report, Today, Plan, Progress, Topics, Settings and rest/empty states. Save screenshots by screen and appearance mode. Historical migration requires the original fixtures and is a separate validation.

## Performance capture

Use the same simulator, OS/runtime, build configuration, store data and measurement method for before/after. Use a fresh store for cold launch and fixed synthetic long plan (for example, 730 days). Capture at least five cold launches and report median/range, time to usable screen, long-plan navigation/scroll, PDF open/dismiss, programme generation/refresh, and memory before/after repeated navigation. Preserve Instruments traces and scripts with the report. Source changes alone do not establish a speedup.

If signature verification, runtime registration, destination discovery or simulator boot fails, stop before app tests. Retain relevant diagnostics and use Apple Support rather than changing runtimes during this validation.
