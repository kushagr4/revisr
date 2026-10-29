# R5 · Validation

Everything below was run on the final R5 code unless a row says otherwise. Debug tests ran on the "Revisr Flexible TMUA QA" simulator (iPhone 17 Pro, iOS 26.5). Extra layout and accessibility runs used the existing iPhone 16e and iPhone 17 Pro Max simulators. No iPad, no new simulator and no physical iPhone were used.

## Git

| Repository | Start | R5 commits | State |
|---|---|---|---|
| `revisr` | `9959096` on `claude/revisr-r4-unified-question-bank` | On `claude/revisr-r5-student-experience`: `51f6fe8` planner determinism · `0ed2948` catalogue provenance and provisional topics · `f131c32` planner (worksheets, evidence hierarchy, worksheet time) · `e224fba` student experience (worksheet runner, Today, Questions, Saved, Progress, tests) · documentation commit | Clean; nothing pushed or merged |
| `revisr-content-private` | `1f3b40b` | `9adabe3` topic provenance and provisional drafts | Clean; nothing pushed |

## Unit and integration tests (XCTest)

| Run | Code | Executed | Passed | Skipped | Failed |
|---|---|---:|---:|---:|---:|
| Full suite, determinism-only state | `51f6fe8` | 276 | 270 | 6 | 0 |
| Full suite | Final R5 code before the code-review fixes | 291 | 285 | 6 | 0 |
| The 10 suites the review fixes touch | After the review fixes | 87 | 87 | 0 | 0 |
| Full suite | Final code (`e224fba`) | 291 | 285 | 6 | 0 |

**Skipped tests.** The same six migration tests as in R1–R4 are skipped, because they need local staging stores.

**New suites:**

- `TMUAPlannerDeterminismTests` (6 tests): cross-process golden digests; started worksheets through a refresh; no second invitation; midnight clock changes; same-instant attempts.
- `TMUAStudentExperienceTests` (14 tests): worksheet states and integrity; self-marked results never becoming evidence; revisits; weak-topic weighting; worksheet minutes and capacity; the evidence hierarchy; the refresh summary; classification provenance; bundled drafts; status, Saved and aliases; reserved questions; performance.
- `TMUACatalogueAuditTests` now also asserts no original together with its adaptation, and no outside-specification or unclassified question in a worksheet.

**Cross-process determinism.** The six golden digests matched in every separate process: 2 runs each when recorded, then every later suite run. The R4 audit and an 8-scenario stage probe gave identical output in two processes once the student's ID was pinned (`R5_PLANNER_DETERMINISM.md`).

**Scripts:**

| Check | Result |
|---|---|
| Private `tools/tests` | 17 / 17 (13 before R5, plus 4 new) |
| `build_reconciliation.py --check` | Up to date |

R4's assembler and Drive tests (29 and 9) were not rerun: R5 did not change `Scripts/` or the Drive tools.

## UI tests (XCUITest)

The full suite ran once on the final code (see "Final runs"). Earlier targeted runs while developing:

| Test | Result |
|---|---|
| `TMUAStudentJourneyUITests.testDailyPracticeFromToday` (journey B) | Passed |
| `…testWorksheetResumesAcrossRelaunchAndFinishesFromItsResults` (journey C) | Passed after three test-query fixes (the combined header element, a lazily loaded segmented control, the confirmation dialog query); the app was unchanged. The one app change was to hide a decorative tick that VoiceOver read as "Selected". |
| `…testLibraryFiltersFlagAndSavedKeepTheirState` (journey D) | Passed after scrolling back to the segmented control |
| `…testRefreshAfterChangingAvailabilityKeepsCompletedWork` (journey E) | Passed |
| `TMUAQuestionLibraryUITests` (R4, updated for one-tap self-marking) | Passed |
| `TMUAPublicContentUITests` (R3) | Passed. Updated because saving a paper result now needs a chosen result, and the test checks that Save starts disabled. |
| `TMUAStudentScreensAccessibilityUITests`, default and largest text | Passed: iPhone 17 Pro light and dark; iPhone 16e; iPhone 17 Pro Max |

Journey A (fresh student) is the existing `TMUAFirstRunJourneyUITests.testStarterFirstRunJourney`.

Test expectations were changed only where behaviour changed on purpose: one-tap recording, an explicit paper result, and the combined accessibility header. No check was dropped.

## Public Release content gate (final code)

`xcodebuild -configuration Release` (generic iOS Simulator) runs `Scripts/assemble_tmua_content.py xcode`:

- **Bank and resources.** "Assembled public bank: 0 items, 385 excluded"; "Removed 242 restricted legacy resources"; "Release gate passed for public distribution"; BUILD SUCCEEDED; 29 MB app.
- **Media.** 0 PDF and 0 mp4 files in the app.
- **Leak scan.** 0 files contain `drive.google`, `driveFileID`, `driveId`, `answerLetter`, `answerBasis`, `"rev-`, `study-copy`, `uitest-fixture`, `rationale`, `classify` or `topic-drafts`.
- **Question IDs.** 0 of the 363 Debug bank question IDs appear in the app, and `RevisrContentBank.json` has 0 items (distribution `public`).
- **Reconciliation.** `TMUACatalogueReconciliation.json` holds 184 drafts with only `question`, `topic`, `strand` and `confidence`, plus the outside and unclassified lists. That is metadata about questions already listed in the bundled `AdmissionsManifest.json`.

The public catalogue the build assembles (from `TMUACatalogueTests`, on the same bundle judged as public):

- 1,609 questions, all linked to UAT-UK, Oxford, OCR and UKMT;
- no solutions;
- topics: 1,363 from the index, 19 outside the specification, 227 not yet classified;
- paper fit: 359 from the paper, 1,080 estimated, 170 unknown.

## Debug catalogue after R5

- **Unchanged:** 2,851 questions in total; 363 marked by Revisr; 1,895 self-marked with a solution; 439 record-a-result; 154 external.
- **Topics:**
  - 363 from Revisr records;
  - 2,026 from the index;
  - 184 provisional drafts;
  - 20 outside the specification;
  - 258 not yet classified (R4 counted 462 together).
- **Paper fit:** P1 1,019, P2 953, both 506, unclassified 373. R4 had 1,031 / 903 / 544 / 373; the change is the Tyler correction.
- **Worksheet pool:** 1,407, up from 1,098.

## Accessibility and performance

See `R5_ACCESSIBILITY_AND_PERFORMANCE.md`.

## Final runs

| Run | Code | Result |
|---|---|---|
| Full XCUITest suite | Final code, as committed in `e224fba` | **20 executed, 20 passed, 0 skipped, 0 failed**, no crash, 52 minutes. 14 R2–R4 tests (2 of them updated for intended changes) and 6 new. |
| Full XCTest suite | `e224fba` | **291 executed, 285 passed, 6 skipped** (the staging-store migration tests), **0 failed** |
| Intermediate commits | `0ed2948` and `f131c32` each built and ran their own affected suites before commit | 26 / 26 and 51 / 51 passed |
| Public Release build and content gate | Final code | Passed (above) |

## Storage

| Point | Free space |
|---|---:|
| End of R4 | 17.32 GiB |
| Before R5 cleanup | 14 GiB (rounded) |
| After R5 cleanup | 15.40 GiB |

**Removed.** About 0.95 GB of R5 scratch:

- intermediate result bundles and screenshots;
- page images and copies of papers made for classification;
- code backups used to split commits;
- temporary scripts.

**Kept.**

- The final UI and unit result bundles and logs (158 MB).
- The reused DerivedData folders `dd-r1` (1.3 GB) and `dd-release` (507 MB).
- Scratch from earlier milestones, untouched.

**Not removed.** The net fall of about 1.9 GiB is mostly simulator data, chiefly from booting and testing on the existing iPhone 16e (4.4 GB) and iPhone 17 Pro Max (2.6 GB) simulators for the screen-size checks. Those devices existed before R5 and may hold earlier data, so nothing on them was erased or uninstalled. Erasing them would recover the space if wanted. No original Drive file, PDF, SwiftData store, Xcode project or other project's file was touched.

## Not done or not verified

- **Physical iPhone.** Not tested; none was connected for this milestone.
- **VoiceOver on a device.** Labels were checked through XCUITest only.
- **Clipped-text advisories.** Those on "Start", "Start with question 1", "Targeted practice" and "Consolidation" were recorded but not each inspected visually.
- **Planning time zone.** Not stored; see the determinism doc.
- **Missed state.** A missed task has no stored state after a refresh.
- **Worksheet frequency.** Worksheets are rare in Debug plans that marked questions can fill; this is a product decision, not taken here.
- **Human review.** No human has reviewed any original, answer key or provisional topic. No content is approved for public distribution.
