# iOS build and test recovery

Updated 11 October 2026 on `codex/ios-completion`. This report records one explicit device-SDK build attempt, native smoke execution of production logic, and the available cross-platform verification options. It does not claim a complete iOS build or XCTest run.

## Checkpoint and toolchain

- Repository: `/Users/kushagra/Documents/revisr`
- Branch at start: `codex/ios-completion`
- Starting commit: `f2a3fb07fbbe1ed4a6c5ac9bbe56edbed79b0a25`
- Original recovered commit: `8002a6f53dd5a0423fd9bdb2a10df0d812010b0f`
- `main`: `ae50956356403e1cdc66db117f0f37f693fa5070`
- Selected developer directory: `/Applications/Xcode.app/Contents/Developer`
- Xcode: 26.6 (17F113); Swift compiler: Apple Swift 6.3.3
- Available SDKs: iOS 26.5 (`iphoneos26.5`) and iOS Simulator 26.5 (`iphonesimulator26.5`)
- Project deployment target: iOS 17; supported platforms: `iphoneos` and `iphonesimulator`.

The original recovery checkout remains at `8002a6f`. `main` was not moved. The pre-existing untracked validation report and Xcode workspace state were preserved.

## Compilation attempt

Previous Debug and Release commands used `-destination 'generic/platform=iOS'` and failed in asset processing with `No available simulator runtimes for platform iphonesimulator`. Their console logs were not present at the previously reported temporary log paths; the failure stage and message are preserved in `PUBLIC_PERFORMANCE_BASELINE.md` and `POST_RECOVERY_VALIDATION.md`.

One distinct, explicit device-SDK attempt was made:

```sh
xcodebuild -project revisr.xcodeproj -scheme revisr \
  -configuration Debug -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/revisr-device-sdk-debug-f2a3 \
  CODE_SIGNING_ALLOWED=NO build
```

Xcode selected `iphoneos26.5` and emitted an arm64 iOS 17 Swift driver invocation. During `CompileAssetCatalogVariant`, `actool` reported:

```text
error: No available simulator runtimes for platform iphonesimulator. SimServiceContext supportedRuntimes=[]
```

CoreSimulatorService had become invalid; Xcode logged connection refused and inability to connect to `simdiskimaged`. The build exited 65. The build directory contains no app Swift object files or `.swiftmodule`; only the dependency-scan diagnostic artifact was produced. No Swift diagnostic came from this `xcodebuild` run. It did not establish a complete app compile or link. No simulator or physical device was used, no signing setting was changed, and no runtime repair was attempted. No further Xcode build was repeated after the same environment failure.

### Production Swift compiler findings

To test independently executable code, a native Swift harness directly compiled the production files `PublicPlanningEngine.swift`, `DiagnosticAnalysis.swift`, `PublicPreparation.swift`, `ModelEnums.swift` and `AdmissionsEnums.swift`. Swift 6.3.3 reported type-checking complexity errors in the topic-priority map expression and question-selection nil-coalescing expression. The production planner was minimally rewritten to use an explicit priority loop and intermediate selection value. The policy, ordering, selection precedence and generated tasks are unchanged. The production files then compiled and the smoke assertions passed. The harness is now preserved at `docs/fixtures/production-logic-smoke.swift` and its runner at `docs/fixtures/run-production-logic-smoke.sh`.

The original standalone compile used `swiftc -module-cache-path /private/tmp/revisr-swift-module-cache -o /private/tmp/revisr-production-logic-smoke` with the five production files listed above and `/private/tmp/revisr-production-engine-smoke.swift`. The expanded harness is now reproducible from the checkout with:

```sh
docs/fixtures/run-production-logic-smoke.sh
python3 docs/fixtures/validate-public-domain-fixture.py
```

This native compile does not compile the SwiftUI views, the full app target, or SwiftData persistence. In-memory value types in the harness stand in for SwiftData-backed input records and the paper-policy declaration; the production diagnostic and planner functions themselves run directly.

## Tests that executed

| Production logic exercised | Result | Input and limits |
|---|---|---|
| `PublicProgrammeAvailability.isAvailable` | Passed | Synthetic Monday/Wednesday schedule verified available dates, a missing Tuesday schedule entry (`nil`), and an explicitly unavailable Sunday (`false`). The actual helper ran. |
| `PublicPlanningEngine.generate` | Passed | Synthetic eligible questions and diagnostic levels verified priority order, exact task/date allocation, weekday bounds, durations, no duplicate question IDs, and no unfilled available days. The actual allocator ran. |
| `DiagnosticAnalysis.report` | Passed | Synthetic paper/response/question records verified TMUA two-paper topic classification, SMC's 25 + 4/−1 score, and BMO self-estimated marks plus its evidence qualification. The actual analysis function ran. |
| Planning/diagnostic boundaries | Passed | Actual planner returned the no-available-day error, allocated one 15-minute final-review task in a one-day window, allowed an assessed failed diagnostic question as error review, and excluded an unassessed diagnostic question. Actual analysis kept one assessed miss at insufficient evidence. |

The fixture file [`docs/fixtures/public-diagnostic-planner-parity.v1.json`](fixtures/public-diagnostic-planner-parity.v1.json) records these deterministic inputs and outputs; `fixtureVersion` is its format version. Run `docs/fixtures/run-production-logic-smoke.sh` from the repo to rebuild and execute the assertions. The fixture is verified for the named production functions and synthetic records. It is not evidence for source-paper selection, catalogue eligibility/import, PDF access, persistence, app navigation, or SwiftUI behavior.

No XCTest executed. The recent tests for retired-task history, empty progress, repeated attempts and saved availability still require the app's XCTest host. The `PublicProgrammeProgressSnapshot` uses SwiftData models and was not independently executed. The missing-PDF completion guard and Topics rationale ordering received source review but no UI regression test ran. The XCTest asserting planner priority order remains unexecuted; the standalone run exercised the production priority and allocation path separately.

Previously reported results of 8/8 targeted Phase 3 tests and 142 passing tests with six skips are historical and were not reproduced against this checkpoint.

## Historical fixture status

The six historical SwiftData migration/release-candidate tests remain unresolved. The current checkout has no `.qa` directory; the preserved recovery checkout has no `.qa` directory or historical `Revisr.store` files; and `git log --all -- .qa` returns no committed fixture history. The recovery checkout contains `revisr/Resources/AdmissionsProgrammeMigration.json`, which is the migration manifest, not the historical store fixture. The previously reported `.qa/chunk4/staging-v1/AdmissionsProgrammeMigration.json` was not recovered. Do not substitute that manifest, synthetic data, or a newly generated store for the original fixtures.

## Regression review

- Retired incomplete tasks excluded and completed history retained: covered by `testProgressSnapshotExcludesRetiredIncompleteTasksAndKeepsCompletedHistory`; not executed.
- Empty progress snapshot: covered by `testEmptyProgressSnapshotHasNoArtificialDenominator`; not executed.
- Repeated question work yields two completed tasks and two linked attempt IDs: covered by `testRepeatedQuestionWorkKeepsSeparateTaskAndAttemptCounts`; not executed.
- Rest day versus missing saved weekday: covered by `testSavedAvailabilityDistinguishesRestDayFromMissingScheduleEntry`; not executed. The same production availability helper's false/nil/true cases passed in the standalone harness.
- Diagnostic priority ordering and BMO qualification: covered in `PublicPlanningEngineTests`; XCTest not executed. Production engine behavior passed the standalone harness.
- Missing PDF cannot enable completion: the view disables completion if the question or local paper URL is absent; source reviewed, but no dedicated executable UI regression ran.
- Deterministic Topics rationale: the view orders candidate tasks by scheduled date and stable ID and then chooses the next incomplete item; source reviewed, but no dedicated test ran.

The six missing store-fixture tests are the only tests previously described as skipped for fixture reasons. Other tests remain unexecuted here because the Xcode test product and host did not build/run.

## Alternative environments

### Recommended: another trusted Mac

This provides the strongest next validation with the least source disclosure. [Apple's Xcode 26.6 requirements](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes) require macOS Tahoe 26.2 or later and include the iOS 26.5 SDK. Use a Mac with Xcode 26.6 (17F113), a verified iOS 26.5 simulator runtime, and adequate free space for the runtime, 430 MiB Revisr Resources tree, DerivedData and test stores. Confirm `xcrun simctl runtime verify` and concrete `xcodebuild -showdestinations` results before building.

Transfer the committed development branch through an encrypted local drive or another owner-controlled channel. Do not include the untracked workspace state, user simulator stores, `.qa` substitutes, signing profiles, or recovery archives. On the second Mac, verify the branch and SHA, then run:

```sh
xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/revisr-debug CODE_SIGNING_ALLOWED=NO build

xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/revisr-release CODE_SIGNING_ALLOWED=NO build

xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Debug \
  -destination 'platform=iOS Simulator,id=<verified-device-UDID>' \
  -derivedDataPath /tmp/revisr-tests CODE_SIGNING_ALLOWED=NO test
```

The simulator UDID should come from that Mac's verified available device list. A second Mac must use an independently healthy runtime; copying simulator data or runtimes from this host is not part of the plan.

### GitHub Actions

The [current GitHub `macos-26` runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md) documents Xcode 26.6 and installed iOS 26.5 simulator devices, so it is a technically plausible runner. Standard macOS runner images have 14 GB storage, which should be checked at job start before building; the project also carries about 430 MiB of Resources. [GitHub's current pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing) lists private-repository macOS runner time at $0.062/minute after applicable included minutes.

This branch is local and has not been pushed. The repository's public/private visibility could not be confirmed because GitHub API access failed. A hosted workflow requires remote source access and would transfer the repository, including third-party examination materials and videos whose redistribution/storage rights have not been reviewed. Do not push or configure hosted CI until visibility, repository access, content rights, storage capacity and any cost are approved. No workflow was created.

### Xcode Cloud

Apple documents [Xcode Cloud build and test workflows](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), but requires a remote Git repository, Apple Developer Program membership and an App Store Connect app record/permissions. Its environment picker is account-dependent. The latest official [Xcode Cloud release notes](https://developer.apple.com/xcode-cloud/release-notes/) available during this review confirm Xcode 26.2 support but do not establish that Xcode 26.6 is available for this account; verify the picker before relying on it. Xcode Cloud also requires remote access to the source tree, so the same resource-rights review applies. No workflow was created.

### Separate macOS user on this host

This is unlikely to help. The runtime signature failure and service connection issue are system-level, and the service failure has affected multiple Xcode projects. A separate account could test user-specific Xcode preferences, but shares the installed runtimes and host services, so it is not a strong route for restoring simulator tests. No account was created.

## Recommended next action

Use another trusted Mac with Xcode 26.6 and a freshly verified iOS 26.5 runtime. This avoids another speculative repair on this host and avoids uploading bundled third-party resources to a new remote service. Once the app and test target build there, run the complete XCTest suite and an isolated simulator walkthrough. Keep all six historical fixture cases unresolved until authentic `.qa` stores are supplied.

## Current status

- Complete iOS app compilation: **not achieved**.
- Genuine Swift compiler issues: **two type-check complexity diagnostics found in the standalone production-source compile and minimally corrected**; the complete Xcode target still has no compilation result.
- Standalone production-logic smoke assertions: **passed** for availability, diagnostic analysis and deterministic planning.
- XCTest suite: **not run**.
- Historical store fixtures: **not recovered**; six related tests remain unresolved.
- Phase 4: **not ready to resume broad UI/performance work** until an actual iOS build and test host are available.
