# Revisr source recovery audit

Recovery completed: 11 October 2026 (Europe/London). This audit describes an isolated reconstruction from local Codex session records. It does not claim simulator-level behavioral validation or Phase 4 completion.

## Location and baseline

- Recovered project: `/Users/kushagra/Documents/revisr-recovery-20261011/checkout`
- Recovery manifest and checksums: [`manifest.json`](../manifest.json)
- Session snapshots: [`source-archives/`](../source-archives/)
- Source baseline: commit `ae50956356403e1cdc66db117f0f37f693fa5070` (`Initial Revisr commit`), branch `main`.
- Original repository `/Users/kushagra/Documents/revisr` remains on `main` at that commit. Its pre-existing untracked `revisr.xcodeproj/project.xcworkspace/` remains present; no original tracked source or Git state was changed.
- The copy was made with `cp -cR`, which uses clone-on-write where the filesystem supports it. Bundled resources were copied with the checkout.

## Session inventory and chronology

The manifest records each archive path, the pre-recovery observed size/hash, a preserved snapshot size/hash, and session timestamps. The primary archive was still being appended to during this audit: its initial manifest hash matches the prefix of the backed-up snapshot; the backup records the later complete snapshot used for reconstruction.

| Session archive | Observed bytes | Snapshot SHA-256 | Session record range (UTC) | Completed FileChange records |
|---|---:|---|---|---:|
| `rollout-2026-10-09T20-25-51-01a12221-0362-72e0-b416-235ec6446647.jsonl` | 15087223 | `9b8185c512ae22c07d9fb22ac5883b9a120c5c51c5e55f3ee0023cc3591b4bbb` | 2026-10-09T19:25:52.074Z – 2026-10-11T10:45:55.487Z | 71 |
| `rollout-2026-10-09T20-28-15-01a12223-36c3-78e1-8c9c-364130e1c4e0.jsonl` | 568459 | `f4c2e95fae68abd76f3f3904cdd8c69fd5a25d6b002d7ca39489d19b00a7156c` | 2026-10-09T19:28:15.632Z – 2026-10-09T20:00:44.279Z | 0 |
| `rollout-2026-10-09T21-08-00-01a12247-99cb-7241-b530-17bdd636b044.jsonl` | 528582 | `b4ce62b36a80105d3a58b0bffdcffbc158ee98f98ec7f3c3046cc3c642ace1cf` | 2026-10-09T20:08:00.258Z – 2026-10-09T21:14:14.126Z | 0 |
| `rollout-2026-10-09T22-16-46-01a12286-8fed-75a2-b2c9-0bb0957b4abb.jsonl` | 94092 | `3d45646226352866530448c7ffb70891920a97a17e1f9c99cc9986789d65c826` | 2026-10-09T21:16:46.487Z – 2026-10-09T21:16:48.435Z | 0 |
| `rollout-2026-10-09T22-19-24-01a12288-f7b2-7830-ad65-fe16a47de72f.jsonl` | 191372 | `f1c7d8ee98b72329b8ef4271b6873a82b4b1eeebe8c78fb5a0ce2fd2f0853b43` | 2026-10-09T21:19:24.125Z – 2026-10-10T00:18:44.575Z | 0 |
| `rollout-2026-10-10T14-21-25-01a125f9-b86d-7303-9e73-31d1c676608d.jsonl` | 47723 | `3144dd8c46ad8895bd692846bd42ce30c425fb021df523afc2fb51cd995ad5be` | 2026-10-10T13:21:25.304Z – 2026-10-10T13:21:25.403Z | 0 |

Only the primary development session contains source-changing `FileChange` events: 71 records, all marked `completed`, spanning 9 October 19:28 UTC to 10 October 00:19 UTC. Those records contain 21 additions with full file contents and 76 updates with unified diffs. No recorded source deletions or renames were found. The five later continuation/audit sessions contain validation, reports or discussion, with no additional source `FileChange` records. The command histories were separately checked for file-writing operations; one additional successful `AdmissionsImportService.swift` indentation transformation was present with terminal exit code 0 and was reproduced from its bounded source anchors. Archived shell text was not executed.

All changes were sorted by session timestamp. Each update patch was applied to the prior version in memory first; all context and line counts matched. Only after the full sequence passed was the reconstructed content written into this checkout. No source file was inferred from a feature description.

## Recovered file inventory

`complete source snapshot plus verified patch sequence` means the session recorded the complete added file, followed by zero or more completed patches. `original baseline plus verified patch sequence` means the exact file from the stated base commit was updated by completed patches. The last column contains the final recovered file SHA-256; full operation counts and byte sizes are in the manifest.

| File | Evidence | SHA-256 |
|---|---|---|
| `README.md` | original baseline plus verified patch sequence; 0 snapshot, 3 patch(es) | `sha256:7e7657b0d1be6f06a1355ee5a70a9893a179c96bc1335db800c3fa3308ed62bb` |
| `docs/DIAGNOSTIC_CONTENT_AUDIT.md` | complete source snapshot plus verified patch sequence; 1 snapshot, 0 patch(es) | `sha256:64db8e1579476605a995aca7fa54ab43444edc097ffb5302e77420153d29be6a` |
| `docs/PUBLIC_PERFORMANCE_BASELINE.md` | complete source snapshot plus verified patch sequence; 1 snapshot, 1 patch(es) | `sha256:04b7578f275b93cf258e99fe07a89bd0bd656490b7c4eada96c7eda9065c316d` |
| `docs/PUBLIC_PRODUCT_ROADMAP.md` | complete source snapshot plus verified patch sequence; 1 snapshot, 12 patch(es) | `sha256:c47a059ea262b9e22801090f2e2e6293ce531b2417798fa29998bac1a65c077f` |
| `docs/PUBLIC_RESOURCE_SIZE_AUDIT.md` | complete source snapshot plus verified patch sequence; 1 snapshot, 0 patch(es) | `sha256:519f8bae1500a20bc419df61f284008d2d180287483bae0bb73fd92a065fe3d8` |
| `docs/PUBLIC_UX_AUDIT.md` | complete source snapshot plus verified patch sequence; 1 snapshot, 0 patch(es) | `sha256:d8e511deda21ce4b1d6e6cd6631d339f43052c41cad6a8a3b55e98cad1f7534c` |
| `revisr/App/AppContainer.swift` | original baseline plus verified patch sequence; 0 snapshot, 2 patch(es) | `sha256:1e277473d041dab29ff8f8a89b9eaa6aef60792c7a5e4037341f643aa9f037c6` |
| `revisr/App/RevisrApp.swift` | original baseline plus verified patch sequence; 0 snapshot, 3 patch(es) | `sha256:68d74f8b9151c093c822cc7a19f6c65e25d7790a03747cb45541ef307d2cf224` |
| `revisr/DesignSystem/RevisrColors.swift` | original baseline plus verified patch sequence; 0 snapshot, 1 patch(es) | `sha256:4c9dc40d16aac76e4ab2f594670286a35d1b983d5176b09640389c700de77917` |
| `revisr/DesignSystem/RevisrMetrics.swift` | original baseline plus verified patch sequence; 0 snapshot, 1 patch(es) | `sha256:4c2a62c17b10904841ee5b3d42b85a2bdf92dabba5b0646e82b09efa0a65f0fb` |
| `revisr/DesignSystem/RevisrTypography.swift` | original baseline plus verified patch sequence; 0 snapshot, 1 patch(es) | `sha256:bf3db7f49cbd054a8fd7e3d50f7d04aaa3a2af145b30a3fcf1bcbb855135325c` |
| `revisr/Features/Admissions/DiagnosticViews.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 8 patch(es) | `sha256:1aa23e706a8f02f415f174214049b151a17ad4c9478104e0450ea60a4f0d4853` |
| `revisr/Features/Admissions/PublicPreparationSetupView.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 6 patch(es) | `sha256:c73ceec369ede5c4cd649d8251a5da2ed32a15463b2aefe49f0a0059d9c7400a` |
| `revisr/Features/Admissions/PublicProgrammeViews.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 5 patch(es) | `sha256:a770514047d64628c1fa0176564009a684f2ceba42a6125e2baf623f2c438f05` |
| `revisr/Models/Admissions/DiagnosticModels.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 1 patch(es) | `sha256:c3fa4425ffbabf02f7ee5131d07ec241c3b3da3342f454b2beb9d5b1c0258430` |
| `revisr/Models/Admissions/PublicPreparation.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 2 patch(es) | `sha256:d213c400ee2d759060c1756afb3b385b8e96079114f06d67fd1f2a57e34c584c` |
| `revisr/Models/Admissions/PublicProgrammeModels.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 0 patch(es) | `sha256:e01d20682a7e24348ae61a9bbca6e2a572397056019baf6e3aa0cd5341a78cac` |
| `revisr/Models/AppSettings.swift` | original baseline plus verified patch sequence; 0 snapshot, 3 patch(es) | `sha256:4e7515fb1f1a393cb336bef68723a542c728e1b56a0f04520f85fc5df27856c9` |
| `revisr/Services/Admissions/AdmissionsImportService.swift` | original baseline plus verified patch sequence; 0 snapshot, 2 patch(es); confirmed successful bounded terminal transform | `sha256:122a29f8d89917eecb2b4c0b88c0e0521e1e30ae41b0591c17d3e4a0f466fc77` |
| `revisr/Services/Admissions/DiagnosticAnalysis.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 3 patch(es) | `sha256:3f9d454f2d286ab03b5b21ceb02916419d7afd2d119cda7f6ee1999b0540718a` |
| `revisr/Services/Admissions/DiagnosticAssessmentService.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 2 patch(es) | `sha256:e0786b4f36256d35c54cdb6747df5648bf00ec46128006de61d6f3e2a80c2290` |
| `revisr/Services/Admissions/DiagnosticPaperSelector.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 3 patch(es) | `sha256:20e04718d85f05e33f998d49ae9166e8ca5c8dc570d043bbcf69ccbacc27e297` |
| `revisr/Services/Admissions/PublicPlanningEngine.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 4 patch(es) | `sha256:86af8cb09284f5430775c26e872f30f943b4c0f9e09b102f8936c7bba2925233` |
| `revisr/Services/Admissions/PublicPreparationService.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 3 patch(es) | `sha256:4bd72d67b00b0d7953c0b0804d7722558fb34f8adfd4ecd1437dd8eb2fa86c65` |
| `revisr/Services/Admissions/PublicProgrammeService.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 2 patch(es) | `sha256:ac90987a0fdc5c661747a7ada1a82caa97ed962d695d42995f0bc51e2eece123` |
| `revisr/Services/SeedDataService.swift` | original baseline plus verified patch sequence; 0 snapshot, 4 patch(es) | `sha256:567f73e597a8bd3c1993bfa360f7501c44700e5ed30e3ff92aaeec1236d8b4a4` |
| `revisrTests/Admissions/DiagnosticWorkflowTests.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 1 patch(es) | `sha256:e93004577fad42d5d552eb21bd6bbb37fd80faca54dc714e3adfde890d507c3c` |
| `revisrTests/Admissions/PublicPlanningEngineTests.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 1 patch(es) | `sha256:7689bb9e740de0b86b6fc83d495a63d455dd02b14187c33275b77c428442823e` |
| `revisrTests/Admissions/PublicPreparationFoundationTests.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 0 patch(es) | `sha256:a247861d3e323facb491a43a4ed31fefda345fce908f3f67bdbe87a346004253` |
| `revisrTests/Admissions/PublicProgrammeServiceTests.swift` | complete source snapshot plus verified patch sequence; 1 snapshot, 2 patch(es) | `sha256:2836e25aecf1bbb03018c00db3de8ef070b585c3b337e85e718069d3fd39c3b8` |

This covers 30 recovered files: 21 additions and 9 updates to baseline files. The extra document `docs/SOURCE_RECOVERY_AUDIT.md` is this recovery report and was created after replay; it is not represented as historical project content.

## Integration checks

- `AppContainer.schema` contains the recovered diagnostic and public programme SwiftData model types.
- `SeedDataService.bootstrapForLaunch` distinguishes a clean public setup from an existing legacy store and routes through the corresponding seed path.
- `RevisrApp` routes unfinished onboarding to `PublicPreparationSetupView`; the public setup flow routes into diagnostics and then the public programme tabs. The legacy `RootTabView` remains available for existing users.
- The recovered services and views reference the recovered question, diagnostic and programme models. Existing bundled manifests and resources came from the baseline checkout.
- The Xcode project has filesystem-synchronized source groups for `revisr` and `revisrTests`, and the shared scheme declares `revisrTests`. No `project.pbxproj`, signing or bundle identifier change was required or recorded.
- The new model/schema additions and legacy-store semantics compile, but migration behavior was not exercised in this recovery run.

## Verification results

| Check | Result | Evidence / limitation |
|---|---|---|
| Swift syntax parse | Pass | Xcode-bundled `swiftc -frontend -parse` over every Swift file in `revisr` and `revisrTests`. |
| Patch integrity | Pass | Every recorded update hunk matched the expected preceding source exactly. |
| Whitespace | Pass | `git diff --check` passed; all recovered changed Swift/Markdown files were separately scanned for trailing whitespace. |
| Debug iOS SDK build | Pass | `xcodebuild -project revisr.xcodeproj -scheme revisr -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/revisr-recovery-ios-device build`; output in `/tmp/revisr-recovery-ios-device-build.log`. This used the existing signing settings and signed only temporary build products; no app was installed. |
| Release iOS SDK build | Pass | Same generic iOS destination with `-configuration Release` and `/tmp/revisr-recovery-ios-release`; output in `/tmp/revisr-recovery-ios-release-build.log`. No AppIntents dependency warning only. |
| Test target build | Blocked | `xcodebuild build-for-testing -project revisr.xcodeproj -scheme revisr -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/revisr-recovery-tests-build` failed because no provisioning profile was available for `com.kushagra.revisr` and `revisrTests` required a team/profile while automatic signing was disabled. No signing settings were changed. |
| Unit/UI tests | Not run | No simulator execution; the historical six store-migration fixture tests also remain unresolved. |
| Simulator build / visual inspection | Not run in recovery | CoreSimulatorService still reports connection invalid/refused and `simdiskimaged` unavailable; earlier simulator attempts failed on runtime discovery. No device was used. |

The successful generic iOS Debug and Release builds are real SDK compilation and linking results. They do not validate simulator startup, UI behavior, accessibility, migrations or tests.

Historical transcripts reported a Phase 3 targeted run of 8/8 tests and, later, 142 passing tests with six historical-store fixture tests skipped. These remain historical evidence only; neither result was reproduced here.

## Phase assessment and remaining uncertainty

| Phase | Expected | Recovered | Confidence |
|---|---|---|---|
| Phase 1 | Public onboarding and legacy-safe bootstrap | Setup view, profile model/service, AppSettings changes, seed/import routing and foundation tests recovered. | High source-recovery confidence; runtime behavior not re-executed. |
| Phase 2 | Two-paper diagnostics | Diagnostic views/models, paper selector, assessment service, analysis, integration and workflow tests recovered. | High source-recovery confidence; diagnostic flow not simulator-tested. |
| Phase 3 | Adaptive planning | Planning engine, persistent programme/task models, service, public tabs and scheduling tests recovered. | High source-recovery confidence; adaptation behavior not re-executed. |
| Phase 4 | Partial UI improvements | Recorded design tokens, public onboarding/diagnostic/programme UI refinements, status/evidence labels, calendar grouping and audit documentation recovered. Phase 4 remains incomplete. | High confidence for recorded source changes; visual/performance completion unverified. |
| Documentation | Roadmap and audits | Five requested docs and updated README recovered from their latest recorded operations. | High. |
| Tests | Added test coverage | Four new phase test files recovered and included by synchronized test group; sources parse. | High source-recovery confidence; tests were not executed in this recovery run. |

The recovered source state corresponds to the last recorded successful source operation at `2026-10-10T00:19:46.700Z`. Subsequent relevant session archives contain no additional successful source edits. Phase 4 was explicitly underway: the recovered roadmap calls the work in progress, and the UX/performance docs describe simulator-dependent follow-up as unmeasured or pending. No screenshot, VoiceOver, Dynamic Type, Reduce Motion, long-programme scrolling, launch-time, memory, PDF-lifecycle or end-to-end adaptation validation was performed as part of recovery.

Source recovery confidence is high because the session records contain complete additions and all sequential updates apply cleanly against the stated baseline. Runtime confidence remains limited by the CoreSimulatorService failure and the unavailable test signing setup. The six historical migration tests must remain unresolved until their original fixtures are available.

## Recommended next steps

1. Preserve this recovery directory and its manifest as the reviewable recovery checkpoint.
2. When CoreSimulatorService is restored, run the full suite and isolated simulator walkthrough against this checkout, including legacy migration coverage when original fixtures are available.
3. Review the recovered diff against the archived handover and then separately authorize any promotion into the main development repository.
4. Continue Phase 4 visual and performance work only after runtime validation; do not mark Phase 4 complete from these recovery checks.
