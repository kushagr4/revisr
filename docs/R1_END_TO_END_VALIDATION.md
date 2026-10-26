# R1 end-to-end validation

Date: 26 October 2026. Branch `claude/revisr-r1-validation`, created from `claude/flexible-tmua-ios` at `341dfd9`. Both earlier commits (`21e444b`, `341dfd9`) are preserved.

## Environment

- macOS 26.7.1, Xcode 27.1, iOS 26.5 simulator runtime.
- Dedicated disposable test simulators only; no other simulator's data was used:
  - "Revisr Flexible TMUA QA" (iPhone 17 Pro, created in the previous milestone; the standard device);
  - "Revisr R1 Pro Max QA" (iPhone 17 Pro Max, created in R1; large-screen and dark-mode runs);
  - "Revisr R1 SE QA" (iPhone SE 3rd generation, created in R1; deleted in the authorised cleanup once the iPhone 13+ policy applied).
- XCUITest needed no extra macOS permissions: simulator UI automation ran from the command line without an accessibility or automation prompt. The Claude simulator panel was not used.

## How the UI tests are isolated

A new UI-test target `revisrUITests` has its own shared scheme, so the unit scheme is unchanged. The app accepts three Debug-only launch switches (`Preview Content/DebugUITestSupport.swift`, compiled out of Release):

| Switch | Effect |
|---|---|
| `--uitest-store <name>` | Opens `Application Support/RevisrUITests/uitest-<name>.store` instead of the student's store. The student's own store is never opened, overwritten or deleted. |
| `--uitest-reset` | Deletes that isolated store before opening it, giving a true first launch |
| `--uitest-fixture-bank` | Uses 80 synthetic development fixtures (40 per paper, every strand, varied answer letters, every fourth with long text and mathematical notation) instead of the private draft bank |

Each fixture stem states its own key ("Fixture answer: C"), so tests answer deliberately right, wrong or skip, and can check scoring exactly. Termination uses `XCUIApplication.terminate()` (a kill, with no background transition), then a relaunch on the same isolated store.

## UI automation results (XCUITest, real taps)

Final run on the final code, on the approved standard device (iPhone 17 Pro simulator, "Revisr Flexible TMUA QA", iOS 26.5): **8 of 8 UI tests passed** (`xcodebuild test -scheme revisrUITests`, about 37 minutes).

| UI test | What it drives | Final (iPhone 17 Pro) | Also run |
|---|---|---|---|
| `testStarterFirstRunJourney` | The 26-step first run below | Passed (279 s) | Passed on iPhone 17 Pro Max in dark mode, and on iPhone SE before the policy |
| `testQuickJourney` | 8 + 7, termination mid-paper, plan, task, relaunch | Passed (270 s) | — |
| `testBalancedJourney` | 10 + 10, same flow | Passed (320 s) | — |
| `testComprehensiveJourney` | 20 + 20, same flow | Passed (494 s) | — |
| `testBackgroundingPausesClockAndTerminationKeepsAnswers` | Home and return shows Paused; a 20-second pause adds no time; termination while running keeps answers and position; double-tap submit gives one submission and no error | Passed (174 s) | — |
| `testExpansionFromStarterKeepsEarlierAnswersAndScores` | Settings gear → Diagnostic → Improve accuracy → 10→15 → added 3 + 2 questions; earlier "2 / 5" and "5 / 5" unchanged; report "11 correct out of 15", Quick label | Passed (282 s) | — |
| `testLargestAccessibilityTextKeepsJourneyOperable` | Onboarding, question, overview and submit at the largest accessibility text size | Passed (142 s) | Passed on iPhone SE before the policy. Failed once mid-milestone on a tap absorbed by scrolling; the helper now retries. |
| `testAccessibilityAuditAcrossJourney` | Xcode's accessibility audit on 15 screens; fails on description, hit-region and trait issues | Passed (244 s) | Passed on iPhone 17 Pro Max in dark mode |

The five-tab navigation and the Settings gear are exercised on every run: tabs by name, Settings through the gear in the expansion and audit tests.

### The first-run journey, step by step (`testStarterFirstRunJourney`)

| # | Required step | How it is exercised and checked |
|---|---|---|
| 1 | Clean persistent store | `--uitest-reset` on an isolated store; the welcome screen must appear |
| 2 | Welcome screen | Welcome text asserted; screenshot |
| 3 | Continue to profile creation | Tap "Build my revision plan" |
| 4 | Future TMUA date | Graphical date picker: Previous Month, then day 15. The countdown must change and be more than 0 days. |
| 5 | Weekly study time | Tap the "5 hours" chip; it must be selected |
| 6 | Weekdays | Tap a weekday 3 days ahead. Its value must change from "Study day" to "Rest day", and the summary must read "About 50 minutes on each study day". |
| 7 | Starter diagnostic | Tap the Starter card; it must be selected; tap "Start with 10 questions" |
| 8 | Start Paper 1 | Tap Start; "Question 1 of 5" |
| 9 | Answer two questions | Q1 correct, Q2 wrong, each read from the fixture stem; each option must show as selected |
| 10 | Flag a question | Flag Q2; the "Flagged" label appears |
| 11 | Navigate backwards | Previous; "Question 1 of 5" |
| 12 | Selections persist | Q1's selection unchanged; Next: Q2's selection and flag unchanged |
| 13 | Pause | Pause; the paused overlay appears; Save and exit; hub shows "Resume at question 2" and "2 of 5 answered" |
| 14 | Terminate | `XCUIApplication.terminate()` |
| 15 | Relaunch | Same isolated store |
| 16 | Resume at saved position | "Resume at question 2"; resumes at Q2 with its answer and flag, and Q1's answer intact |
| 17 | Complete Paper 1 | Q3 correct, Q4 skipped, Q5 correct. The submit sheet must show 4 answered and 1 flagged. Hub: "Submitted · 3 / 5 correct". |
| 18 | Open Paper 2 | Start Paper 2 (unlocked only after Paper 1) |
| 19 | Complete Paper 2 | 5 correct; "Submitted · 5 / 5 correct" |
| 20 | Diagnostic report | Raw score "8 correct out of 10"; Paper 1 "3 / 5", Paper 2 "5 / 5"; confidence label "Starter" |
| 21 | Generate plan | Tap "Generate my personalised plan" from the report |
| 22 | Today | "0 of n tasks" |
| 23 | Plan | Plan tab: today's row present; "1 complete" after step 24 |
| 24 | Complete a task | Today's Next task: answer correctly, Check, "Correct". The same question and selection stay on screen (regression for the navigation defect below). Today: "1 of n tasks". |
| 25 | Progress updates | Completed tasks "1 of …", question attempts 1, Starter diagnostic "8 / 10" |
| 26 | Relaunch, history persists | Terminate and relaunch: Today still "1 of n"; Progress unchanged |

The Quick, Balanced and Comprehensive journeys repeat the flow for 8+7, 10+10 and 20+20 questions:
- Paper 1 alternates right and wrong answers and skips the last question; Paper 2 has one wrong answer.
- Each terminates the app halfway through Paper 1 and must resume at the next question.
- Each checks the exact submitted counts, the raw score and the length label, then generates a plan, completes a task and relaunches.

### Defects found by UI automation and fixed

1. **Completing Today's "Next" task swapped the open screen to a different question.** After a task was completed, Today's "next" task changed and SwiftUI rebuilt the pushed screen for the new task while keeping the old result. The student saw an unanswered question marked wrong, with its solution revealed. Found in a Quick-journey screenshot (the key was A, but D showed as the student's wrong answer). Fixed with value-based navigation (`TMUATaskRoute`) and practice state keyed to its task. The journeys now assert the question and the selection stay on screen.
2. **Accessibility audit failures** (enforced types: element descriptions, hit regions, traits):
   - the "Preparing for SMC or BMO instead?" link had a tap area under 44 pt;
   - progress bars were exposed as tiny elements: they are now read as text ("Setup step 1 of 3", "2 of 5 answered") or hidden where adjacent text says the same.

   The audit now passes on every screen for these types.
3. **Contrast and Dynamic Type** (from the audit's advisory types):
   - In light mode, secondary text and the green, orange and red status colours measured about 2–3.6:1. They are now 4.75–5.86:1 on white and grouped backgrounds; dark mode keeps the system colours.
   - The Today countdown and the results score used fixed font sizes; they now scale with Dynamic Type (`@ScaledMetric`).
   - In dark mode, white text on the teal fill (selected chips and weekdays, answered badges, option letters, prominent buttons) measured about 3.3:1. A new `accentFill` token keeps light mode unchanged and gives 5.35:1 in dark mode, with 3.18:1 against unselected chips so the selected state remains distinguishable.
4. Speech: VoiceOver had no spoken form for some symbols the questions use: ∛, ′, ∠, ⟂, ↔, →, ∫, …, ·, and the superscripts 4–9. They now have one, and `TMUAMathSpeechTests` fails if a bundled question uses a symbol without one.

Earlier R1 fixes verified through the UI:
- the clock now pauses when the app is backgrounded, and the overlay asks the student to resume;
- a double tap on "Submit and lock answers" submits once, with no error;
- expansion keeps earlier marks.

Test-side issues, not app defects:
- the reset switch percent-encoded a path containing a space;
- taps landed on bottom bars covering their targets;
- taps were absorbed by scroll momentum;
- a label was parsed with a trailing space;
- XCUITest's own wait-for-idle time was counted as active time.

### Accessibility audit findings left open (advisory types)

- **Contrast "failed" on the paused overlay and under sheets.** The audit samples text behind translucent material, so this is expected.
- **Contrast on the date picker's system day numbers.** These are system controls.
- **"Dynamic Type partially unsupported" on the graphical date picker and List section headers.** System components.
- **"Text clipped"** on some chip and button labels at the default size on the iPhone SE. In the screenshots the labels render in full, so these look like false positives, but they are not proven to be.

None of these is claimed as compliant. No VoiceOver session was run on a device.

## Unit and other automated tests

| Suite | Executed | Passed | Skipped | Failed |
|---|---:|---:|---:|---:|
| Baseline at `341dfd9` (previous milestone) | 192 | 186 | 6 | 0 |
| R1 unit suite, final code (approved iPhone 17 Pro simulator, after the cleanup) | **209** | **203** | **6** | **0** |

The 6 skips are the same historical store-migration tests, whose `.qa` fixtures are still missing. They were not manufactured and are not counted as passes. New unit tests (17):

| Class | Tests | Purpose |
|---|---:|---|
| `TMUATimingIntegrityTests` | 5 | Checkpoints, a week away, pauses, save failures (file-backed store), switching papers |
| `TMUAAdaptationScenarioTests` | 7 | Adaptation scenarios (`R1_DIAGNOSTIC_AND_PLANNER_AUDIT.md`) |
| `TMUAPlannerAuditTests` | 3 | 128-scenario planner audit and the content-limit notice |
| `TMUAMathSpeechTests` | 2 | Spoken forms for every symbol in the bundled bank |

Other checks:
- **Legacy parity harness:** the standalone `production-logic-smoke` harness still passes, so legacy planner and evidence parity hold.
- **Python content-gate tests:** `Scripts/tests/test_assemble_tmua_content.py`, 9 of 9 pass.
- **Pre-existing Python failure:** `Scripts/tests/test_chunk4_programme.py` still errors in setup because its `.qa/chunk4` fixtures are missing, the same cause as the 6 XCTest skips.
- **Parity fixture:** `validate-public-domain-fixture.py` passes.
- **Release build:** succeeds with 0 bundled questions, 242 restricted files stripped, and no debug or UI-test code (`R1_RELEASE_READINESS.md`).
- **Internal-content archive:** refused, as intended.
- **Leak scan:** none of the 87 private item versions' stable IDs, stems or solutions appear in the branch diff or in new files.

## Device and simulator coverage

| Device | Appearance | Text size | What ran |
|---|---|---|---|
| iPhone 17 Pro simulator (6.3"), "Revisr Flexible TMUA QA" | Light | Default and largest accessibility size | All UI tests (final run on the final code), full unit suite, smoke test after cleanup |
| iPhone 17 Pro Max simulator (6.9"), "Revisr R1 Pro Max QA" | **Dark** | Default | Accessibility audit, Starter journey |
| iPhone SE 3rd generation simulator (4.7"), before the testing policy | Light | Default and largest accessibility size | Accessibility audit, Starter journey, largest-text journey, unit suite. Under the iPhone 13+ policy this device was deleted; its results are kept as history and are not part of the supported matrix. |

From 26 October 2026 testing follows `IOS_TESTING_POLICY.md`: iPhone 13 and newer only, no iPads, and explicit destinations from `Scripts/approved_simulator.py`.

## Not verified

- No physical device; no older hardware; no performance traces (launch time, memory, scrolling).
- VoiceOver on a device, including how the spoken mathematics actually sounds.
- Full Keyboard Access, Switch Control, Voice Control.
- Reduce Motion, by code review only: the only animation is a 0.2-second onboarding step change and the system sheets.
- Real phone calls and the lock button. Backgrounding uses the Home button; termination uses `terminate()`.
- A real full disk; save failures are injected.
- Landscape: the app is portrait-only by configuration.
- Notification delivery.

Screens reviewed only through screenshots, without assertions on their content:
- Topics, Questions filters and Settings (beyond opening them and the audit);
- the Plan day detail;
- the worked-solution review screen.
