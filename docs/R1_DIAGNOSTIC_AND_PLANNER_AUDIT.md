# R1 diagnostic and planner audit

Audit date: 26 October 2026, branch `claude/revisr-r1-validation`. Evidence is from XCTest unit tests, XCUITest runs and the planner audit tests named below; results are in `R1_END_TO_END_VALIDATION.md`.

## 1. Diagnostic lengths

| Length | Paper 1 | Paper 2 | Verified by |
|---|---:|---:|---|
| Starter | 5 | 5 | Unit: `testCreationPinsVersionsForEveryLength`; UI: `testStarterFirstRunJourney` |
| Quick | 8 | 7 | Unit, UI: `testQuickJourney` |
| Balanced | 10 | 10 | Unit, UI: `testBalancedJourney` |
| Comprehensive | 20 | 20 | Unit, UI: `testComprehensiveJourney` |

For every length the unit suite checks exact counts, eligible sources only, deterministic selection, unique question identities, pinned versions, answers surviving relaunch, marking, unanswered handling, evidence wording appropriate to the length, and plan generation. The UI journeys check the same counts on screen ("Question 1 of n", the hub's per-paper counts, the submit sheet's answered and unanswered counts, the raw score and the length's confidence label), and that answers survive termination.

Expansion: all six upgrades (10→15, 10→20, 10→40, 15→20, 15→40, 20→40) are unit-tested for cumulative counts, unchanged earlier answers, marks and timings, exclusion of exposed questions, and deduplicated evidence. Starter→Quick is also driven through the UI (`testExpansionFromStarterKeepsEarlierAnswersAndScores`).

### Defect found and fixed: expansion could reveal a solution early

Expansion excluded questions already answered in the diagnostic or practice, but not questions merely *scheduled* in the plan. An added round could therefore pick a question that also sat in Today's tasks. Opening that task showed the worked solution before the student answered the same question in the added round. Planning also treated questions in an unsubmitted round as fresh practice.

Fix (`TMUAProgrammeService`):
- `reservedStableIDs` lists questions in unsubmitted sections. They are excluded from planning, and open tasks that reference them are retired.
- `expandDiagnostic` refreshes the plan as soon as questions are added.
- `TMUATaskView` refuses to show a reserved question.

Test: `testExpansionReservesQuestionsAndPreservesEarlierWork`, which confirms that the fixture expansion did pick an already-planned question and that no open task shows it afterwards.

## 2. Timing and persistence semantics

**Active time** is the time a section is open on screen in the foreground and not paused. Exactly:

| Event | What happens |
|---|---|
| Start or resume a section | `runningSince = now`; saved. |
| Select, change or clear an answer; flag; move between questions | The answer or position is saved immediately, together with `lastSavedAt`. |
| Every 60 seconds while running and in the foreground | Checkpoint: only `lastSavedAt` is written (`TMUADiagnosticService.checkpoint`). One small write a minute; answers and accumulated time are untouched. |
| Pause button | Time since `runningSince` is added to `accumulatedSeconds`; the clock stops; a pause overlay appears. |
| Home, app switcher, lock, incoming call, Control Centre | **New in R1:** the clock stops at that moment (saved), and on return the pause overlay asks the student to resume. Previously the clock stopped silently and did not restart, so later work went uncounted. |
| Abnormal termination while running (crash, power loss) | On relaunch, time counts up to `lastSavedAt` (the latest action or checkpoint). At most one 60-second interval is lost; wall-clock time after that is discarded. |
| Reopening after a day or a week | A paused section adds nothing. A section interrupted while running recovers as above, so a week away never counts. |
| Switching papers | Paper 2 cannot start until Paper 1 of the same round is submitted. A submitted paper cannot be reopened. Each section keeps its own clock. |
| Submit | Time is closed and every answer locked and marked. A second submit (including a double tap) is rejected and the button ignores it while the sheet closes. |
| Save failure (for example a full disk) | **New in R1:** the action is reported ("Couldn't Save"), and the in-memory record is restored to its stored values, so the screen never shows an unsaved answer or a submission that did not happen. |

**Limitation.** Before R1, recovery counted only up to the last *interaction*. A student who read one question for 8 minutes without tapping and then lost power lost those 8 minutes. Checkpoints reduce the loss to at most 60 seconds. If the device's auto-lock is disabled and the app is left open, time keeps counting. That is the meaning of "open on screen".

### Defects found and fixed

1. **Clock not restarting after the app was backgrounded.** `TMUAAssessmentView` paused the timer on leaving the app but left the question on screen with no paused overlay, so nothing resumed it. The view now shows the pause overlay on return (`testBackgroundingPausesClockAndTerminationKeepsAnswers`, UI).
2. **Save failures left phantom state.** SwiftData's `ModelContext.rollback()` discards pending changes but leaves model properties as they were set. After a failed save the screen could show the new answer, a stopped clock or a "submitted" paper that was not stored. Every diagnostic action now snapshots the records it changes and restores them on failure. Practice attempts and review flags do the same (`testSaveFailuresKeepStoredAnswersAndTimerState`, run against a file-backed store with injected failures).
3. **Duplicate-submit tap.** A second tap on "Submit and lock answers" while the sheet closed raised an error alert. The button now ignores it.

Low storage is simulated by injecting a save error (`TMUADiagnosticService.injectedSaveFailure`, a test seam that is nil in the app). A real full disk was not produced.

## 3. Planner reliability (3–180 days)

`TMUAPlannerAuditTests` generates real programmes through the app's service path (diagnostic, then `generateOrRefresh`). It covers 8 windows (3, 7, 14, 30, 60, 90, 120 and 180 days), 4 weekly capacities and 2 diagnostic lengths, on two banks: 64 synthetic fixtures, and the 60-item development bank bundled in Debug builds. That makes 128 scenarios per run. Each scenario asserts:
- tasks stay inside the window, never on exam day and never on rest days;
- daily and weekly capacity and the session cap are respected;
- no question appears twice on one day, and every task references real eligible content;
- labels are honest: "Spaced review" and "Error review" only for questions the student has already seen; "Targeted", "Mixed", "Consolidation" and "Timed" only for unseen questions.

Each scenario also prints metrics (`AUDIT` lines).

Capacities: 3h/3d = 180 minutes over Mon, Wed, Sat; 5h/6d = 300 minutes, Sunday off; 8h/5d cap60 = 480 minutes on weekdays with a 60-minute session cap; 12h/7d = 720 minutes every day.

### Defects found by the audit and fixed

| Finding (60-item bank, before) | Cause | Fix (TMUA options only; legacy planner unchanged) |
|---|---|---|
| One question scheduled up to **7 times** in 120–180-day plans | `maximumSpacedRepeats` scaled up to 6 to fill long windows | Capped at 3 revisits (`TMUAProgrammeService.spacedRepeatLimit`); unfillable days stay empty and are reported |
| **Empty study day right after the diagnostic** (for example the 2nd study day of a 60-day comprehensive plan) | Fresh-question pacing had no allowance left, and missed diagnostic questions wait 3 days for review | `minimumOneTaskPerStudyDay`: while unseen questions remain, a day never ends empty because of pacing |
| **All tasks in one topic** in short plans after a comprehensive diagnostic (100% in 3-day windows) | When the preferred topic had no unseen question, the fallback always took the top-priority topic | `balanceFallbackTopics`: the fallback uses the same rotation as the preferred topic |
| A 6-month plan implied months of varied revision | No disclosure of bank limits | Plan tab notice (`TMUAPlanContentSummary`), for example "17 of your 180 remaining study days have no task because Revisr's question bank is not yet large enough to fill them", or the date when unseen questions run out (`testContentSummaryIsHonestAboutLongWindows`) |
| Missed study days were never rescheduled (missed tasks stayed active in the past and their questions stayed "used") | Refresh was suggested only after settings changes or 5 completed tasks | Today shows "N tasks from earlier days were not completed" with a Refresh button. Refresh retires the missed tasks (kept, not deleted) and replans their questions (`testMissedStudyDaysAreRescheduledOnRefresh`) |

Legacy parity: `PublicPlanningOptions.legacy` leaves all new flags off. `PublicPlanningEngineTests` and the standalone parity harness still pass.

### Results before and after (60-item development bank; 3 of the 4 capacities shown)

| Window | Capacity | Diagnostic | Study days | Empty study days (first) before → after | Max uses of one question before → after | Distinct questions | Fresh / error review / spaced (after) | Capacity used (after) | Largest topic share before → after |
|---|---|---|---:|---|---|---:|---|---:|---|
| 3 days | 12h/7d | comprehensive | 3 | 0 → 0 | 1 → 1 | 9 | 0 / 0 / 0 | 44% | 67% → 22% |
| 3 days | 12h/7d | starter | 3 | 0 → 0 | 1 → 1 | 9 | 0 / 0 / 0 | 44% | 11% → 11% |
| 3 days | 3h/3d | comprehensive | 2 | 0 → 0 | 1 → 1 | 4 | 0 / 0 / 0 | 50% | 100% → 25% |
| 3 days | 3h/3d | starter | 2 | 0 → 0 | 1 → 1 | 4 | 0 / 0 / 0 | 50% | 25% → 25% |
| 3 days | 5h/6d | comprehensive | 3 | 0 → 0 | 1 → 1 | 3 | 0 / 0 / 0 | 30% | 100% → 33% |
| 3 days | 5h/6d | starter | 3 | 0 → 0 | 1 → 1 | 3 | 0 / 0 / 0 | 30% | 33% → 33% |
| 7 days | 12h/7d | comprehensive | 7 | 1 (#6) → 1 (#6) | 1 → 1 | 25 | 20 / 5 / 0 | 53% | 24% → 24% |
| 7 days | 12h/7d | starter | 7 | 0 → 0 | 1 → 1 | 32 | 23 / 1 / 0 | 70% | 25% → 9% |
| 7 days | 3h/3d | comprehensive | 3 | 0 → 0 | 1 → 1 | 10 | 8 / 2 / 0 | 83% | 60% → 20% |
| 7 days | 3h/3d | starter | 3 | 0 → 0 | 1 → 1 | 10 | 8 / 0 / 0 | 83% | 10% → 10% |
| 7 days | 5h/6d | comprehensive | 6 | 0 → 0 | 1 → 1 | 14 | 12 / 2 / 0 | 70% | 43% → 14% |
| 7 days | 5h/6d | starter | 6 | 0 → 0 | 1 → 1 | 13 | 11 / 0 / 0 | 71% | 8% → 8% |
| 14 days | 12h/7d | comprehensive | 14 | 0 → 0 | 2 → 2 | 47 | 19 / 20 / 17 | 60% | 36% → 35% |
| 14 days | 12h/7d | starter | 14 | 0 → 0 | 2 → 2 | 55 | 40 / 4 / 21 | 79% | 27% → 22% |
| 14 days | 3h/3d | comprehensive | 6 | 0 → 0 | 1 → 1 | 22 | 15 / 5 / 0 | 92% | 27% → 18% |
| 14 days | 3h/3d | starter | 6 | 0 → 0 | 1 → 1 | 20 | 18 / 1 / 0 | 89% | 10% → 10% |
| 14 days | 5h/6d | comprehensive | 12 | 0 → 0 | 1 → 1 | 32 | 17 / 13 / 0 | 80% | 28% → 25% |
| 14 days | 5h/6d | starter | 12 | 0 → 0 | 1 → 1 | 31 | 26 / 3 / 0 | 81% | 19% → 6% |
| 30 days | 12h/7d | comprehensive | 30 | 1 (#2) → 0 | 3 → 3 | 60 | 20 / 20 / 83 | 60% | 31% → 28% |
| 30 days | 12h/7d | starter | 30 | 0 → 0 | 3 → 3 | 60 | 45 / 4 / 82 | 67% | 24% → 20% |
| 30 days | 3h/3d | comprehensive | 13 | 0 → 0 | 2 → 3 | 37 | 19 / 17 / 13 | 96% | 24% → 26% |
| 30 days | 3h/3d | starter | 13 | 0 → 0 | 1 → 1 | 48 | 45 / 1 / 0 | 95% | 27% → 21% |
| 30 days | 5h/6d | comprehensive | 26 | 0 → 0 | 3 → 3 | 46 | 19 / 20 / 30 | 81% | 29% → 29% |
| 30 days | 5h/6d | starter | 26 | 0 → 0 | 3 → 3 | 55 | 47 / 4 / 20 | 86% | 29% → 25% |
| 60 days | 12h/7d | comprehensive | 60 | 14 (#1) → 2 (#38) | 4 → 4 | 60 | 20 / 20 / 167 | 51% | 26% → 24% |
| 60 days | 12h/7d | starter | 60 | 2 (#5) → 0 | 4 → 4 | 60 | 50 / 4 / 138 | 47% | 28% → 20% |
| 60 days | 3h/3d | comprehensive | 26 | 0 → 0 | 3 → 3 | 48 | 20 / 20 / 61 | 97% | 30% → 29% |
| 60 days | 3h/3d | starter | 26 | 0 → 0 | 3 → 3 | 56 | 49 / 4 / 46 | 97% | 41% → 25% |
| 60 days | 5h/6d | comprehensive | 52 | 3 (#2) → 0 | 3 → 3 | 60 | 20 / 20 / 98 | 80% | 28% → 25% |
| 60 days | 5h/6d | starter | 52 | 0 → 0 | 3 → 3 | 60 | 48 / 4 / 90 | 84% | 26% → 17% |
| 90 days | 12h/7d | comprehensive | 90 | 26 (#1) → 14 (#63) | 5 → 4 | 60 | 20 / 20 / 178 | 36% | 26% → 24% |
| 90 days | 12h/7d | starter | 90 | 6 (#5) → 2 (#84) | 5 → 4 | 60 | 50 / 4 / 152 | 34% | 25% → 19% |
| 90 days | 3h/3d | comprehensive | 39 | 0 → 0 | 3 → 3 | 60 | 20 / 20 / 108 | 95% | 27% → 23% |
| 90 days | 3h/3d | starter | 39 | 0 → 0 | 3 → 3 | 60 | 49 / 4 / 98 | 98% | 29% → 20% |
| 90 days | 5h/6d | comprehensive | 78 | 4 (#2) → 1 (#81) | 4 → 4 | 60 | 20 / 20 / 159 | 77% | 27% → 23% |
| 90 days | 5h/6d | starter | 78 | 3 (#5) → 0 | 4 → 4 | 60 | 50 / 4 / 144 | 77% | 29% → 19% |
| 120 days | 12h/7d | comprehensive | 120 | 40 (#1) → 42 (#63) | 6 → 4 | 60 | 20 / 20 / 180 | 27% | 26% → 25% |
| 120 days | 12h/7d | starter | 120 | 15 (#4) → 2 (#114) | 6 → 4 | 60 | 50 / 4 / 160 | 26% | 25% → 20% |
| 120 days | 3h/3d | comprehensive | 52 | 0 → 0 | 4 → 4 | 60 | 20 / 20 / 157 | 95% | 28% → 23% |
| 120 days | 3h/3d | starter | 52 | 0 → 0 | 4 → 4 | 60 | 49 / 4 / 147 | 97% | 29% → 19% |
| 120 days | 5h/6d | comprehensive | 103 | 6 (#1) → 10 (#93) | 6 → 4 | 60 | 20 / 20 / 177 | 63% | 26% → 24% |
| 120 days | 5h/6d | starter | 103 | 8 (#3) → 3 (#110) | 6 → 4 | 60 | 50 / 4 / 160 | 63% | 26% → 20% |
| 180 days | 12h/7d | comprehensive | 180 | 80 (#1) → 98 (#65) | 7 → 4 | 60 | 20 / 20 / 180 | 18% | 26% → 25% |
| 180 days | 12h/7d | starter | 180 | 35 (#3) → 20 (#144) | 7 → 4 | 60 | 50 / 4 / 177 | 19% | 27% → 24% |
| 180 days | 3h/3d | comprehensive | 77 | 0 → 4 (#156) | 6 → 4 | 60 | 20 / 20 / 178 | 71% | 28% → 24% |
| 180 days | 3h/3d | starter | 77 | 0 → 0 | 6 → 4 | 60 | 50 / 4 / 172 | 74% | 30% → 23% |
| 180 days | 5h/6d | comprehensive | 155 | 18 (#2) → 47 (#106) | 7 → 4 | 60 | 20 / 20 / 180 | 43% | 27% → 25% |
| 180 days | 5h/6d | starter | 155 | 21 (#1) → 3 (#175) | 7 → 4 | 60 | 50 / 4 / 172 | 44% | 26% → 23% |

"First empty" is the index of the first empty day counted from the plan start.

### Content exhaustion: what the bank can actually support

- The bank has 60 items (34 Paper 1, 26 Paper 2). A Comprehensive diagnostic uses 40, leaving **20 unseen questions** for the whole programme. A Starter leaves 50.
- At 5 hours a week (about 3 tasks per study day), unseen questions last about 2–3 weeks after a Comprehensive diagnostic, and about 5–6 weeks after a Starter.
- Beyond that, plans consist of error review and spaced review of seen questions, at most 4 scheduled uses per question with gaps of 7, 14 and 21 days.
- 60-day plans fill nearly every study day. 120–180-day plans leave 3–98 study days empty, concentrated in the later months, and use 18–74% of the student's capacity. The Plan tab says so.
- **Conclusion:** the current bank supports varied revision for windows of about 4–8 weeks at typical capacity. It cannot support 3–6 months of varied revision. At roughly 3 tasks per study day and at most 4 uses per question, a 6-month programme at 5 hours a week needs about 150–200 distinct reviewed questions. The plan no longer pretends otherwise.

### Adaptation scenarios (`TMUAAdaptationScenarioTests`, all passing)

| Scenario | Verified behaviour |
|---|---|
| Repeated algebra mistakes | Algebra's priority rises after 3 missed practice attempts. Missed questions return as error review after the 3-day gap. The refresh summary explains the change and keeps completed work. |
| Improving logical reasoning | Logic's priority falls after correct practice |
| Unassessed geometry (any unsampled topic) | At least 80% of topics the Starter diagnostic did not sample get baseline practice in the first 3 weeks |
| Diagnostic expansion | Added questions are reserved and leave the plan at once. Earlier marks are unchanged. Completed tasks are kept. After submission the plan refreshes with the new evidence. |
| Missed study days | Missed tasks are retired (kept), at least 80% of their questions are replanned, and no stale task stays active |
| Reduced or increased weekly time | Future weeks respect the new capacity, and workload falls or rises accordingly. Completed tasks are kept. |
| Exam moved earlier or later | Nothing remains on or after the new exam day. A later exam extends the plan into the new weeks. Completed tasks are kept. |

### Remaining planner limitations

- The 15-minute task size is a planning cap, not a calibrated time.
- With a 12-hour week and a small bank, most capacity is unused. This is reported as a content limit rather than filled with repetition.
- Empty days fall late in long plans, so the final weeks before the exam are lighter. Filling them needs more content, not more repetition.
- The TypeScript port in Revisr Web has not received the new TMUA-only options.
