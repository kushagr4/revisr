# R5 · Adaptive revision: evidence, changes and long-plan realism

## The evidence hierarchy, as implemented

| Rank | Evidence | Where it acts |
|---|---|---|
| 1 | Verified diagnostic answers | Each topic's evidence level (strong difficulty, possible improvement, insufficient, relative strength). This sets the engine's base rank (40/30/20/10), the worksheet topic order, and which topics get extra worksheets. |
| 2 | Practice answers Revisr marks | "Recent" rank: up to +8 for misses and down to −4 for successes, within 21 days of the plan start. Missed and flagged questions return as error or spaced review. |
| 3 | Results the student records on worksheet questions | Which questions come back: a question marked incorrect or partly right returns once in a later worksheet, at least seven days on. Never topic priority, never evidence of mastery. |
| 4 | Self-reported whole-paper results | The paper is not set again. Nothing else. |
| 5 | Opening a page, or completing a task | Nothing. A task completes only from an answer (2), a finished worksheet built from recorded results (3), or a recorded paper result (4). |

`testSelfMarkedResultsNeverBecomeEvidence` records incorrect results on three whole worksheets. It checks that no `TMUAPracticeAttempt` is created and that the engine's topic priorities are identical.

## Changes in R5

1. **Diagnostic answers are not counted twice.** A diagnostic answer already sets the topic's level. Before R5 it was also counted as "recent practice" for about 21 days, then dropped out, so priorities shifted with no new evidence. With `recentRankFromPracticeOnly` (TMUA), recent rank uses practice answers only. Checked by `testDiagnosticAnswersAreNotCountedTwiceAsRecentPractice`.
2. **Questions in the next three days keep their evidence.** Before R5, questions already planned in the unchanged three-day window were removed from the planning input entirely. So a recent miss on a question awaiting its review did not raise its topic. These questions are now passed as `plannedElsewhereQuestionIDs`: never scheduled twice, but counted for priority.
3. **Weak topics get more worksheets.** Topics the diagnostic assessed as clear difficulty or possible improvement get two worksheets in each round instead of one. This uses verified evidence only.
4. **Self-marked mistakes come back once.** A question the student marked incorrect or partly right at least a week earlier comes back once, provided it has been in at most one worksheet and is not planned already. It leads its topic's queue, and the worksheet's reason says "One question you marked incorrect or partly right before comes back once." Checked by `testSelfMarkedMistakesComeBackOnce`.
5. **Worksheet time follows its questions.** Estimates per question, including marking against the solution:
   - 5 minutes at levels 1–2;
   - 6 at level 3 or unknown;
   - 8 at level 4;
   - 10 at level 5.

   The TMUA itself allows 3¾ minutes a question. These are transparent, conservative estimates, not measured timings, and the levels are estimates too. A worksheet takes questions while they fit the room, up to eight, and its allocated time is their sum.
6. **Library sessions respect the session cap.** Before R5 an empty day's session ignored the student's longest-session setting and had a 20-minute floor that could exceed the day. It is now the smallest of the day's share, the cap and 75 minutes. A day with under 15 minutes gets no library session.
7. **Publishers take turns.** Before R5 a topic's queue drew its easiest questions from one topic bank first. In R5's 36-scenario audit the top publisher supplied 71–100% of worksheet questions in plans up to 120 days. Publishers now alternate within each tier: official, mocks, other admissions tests, competitions. The top publisher's share fell to 18–27%, and each worksheet runs from easier to harder.
8. **An original and its adaptation are never both set.** Before R5 the adaptation check ran one way: an adaptation set first did not block its original. The audit found one such pair in the heaviest plan. Both directions are now checked and the audit asserts it.
9. **The refresh summary measures before it changes anything.** Before R5 the "before" set was read after tasks were retired, so the summary could never report a topic losing practice ("less …"). It also left out library sessions. Both are fixed: `testRefreshAfterDroppingDaysCanReportLessPractice` and `testRefreshSummaryReportsTopicsThatLosePractice`.
10. **Accurate words.**
    - The "clear difficulty" reason no longer says "across both papers", which was wrong for the three Paper 2-only topics.
    - "Widening gaps" is said only where questions repeat at widening gaps; with library sessions a question returns once.
    - Empty days are no longer blamed on "Revisr's question bank" alone.
    - Today's priorities footer now says exactly what feeds them.

11. **A started worksheet's minutes are booked first.** A worksheet the student has started keeps its day through a refresh. The engine now learns of its minutes (`bookedMinutesByDay`) before planning that day, so the day cannot go over capacity. Found in review and checked in `testStartedWorksheetSurvivesRefreshAfterSettingsChange`.
12. **Review fixes to revisits and worksheet fitting:**
    - A mistake comes back once counted from its first miss, including one first recorded in Practice; before this fix it could return twice.
    - An adaptation stays blocked while its original returns as a revisit.
    - A worksheet too long even for a full session is dropped, instead of blocking every later worksheet.
    - A kept paper session holding a question from an open diagnostic round leaves the plan.
    - The refresh summary is read before reserved-question tasks are retired.

Changes 1–7 alter future plans. The golden digests in `TMUAPlannerDeterminismTests` were re-recorded once for changes 1–6 and once for change 7, each time from two separate processes that agreed. The review fixes in 11–12 left the digests unchanged.

**Stored plans.**

- Completed tasks are untouched.
- A plan changes only on the student's next refresh, settings save or diagnostic extension. Nothing regenerates at launch.
- Task-ID formats are unchanged.

## Missed days and refresh

- Today lists up to five unfinished tasks from earlier days, each still openable, and offers "Move unfinished work into my plan", with confirmation.
- A refresh keeps the next three days as they are (unless settings changed), every completed task, and every worksheet already started. It returns missed questions to the pool for the days ahead.
- Retired tasks are kept as rows, not deleted.

**Limitation.** A missed task has no stored "missed" state, so after a refresh it no longer appears in Plan's earlier days. Adding that state needs a model field; it is recommended for a later milestone.

## Long-plan realism (Debug build, final R5 code)

**Setup.** `TMUACatalogueAuditTests` builds 36 plans: 14–180 days, 3 hours on 3 days, 5 hours on 6 days or 12 hours on 7 days, with and without library sessions. Each uses a pinned student who answers a balanced diagnostic.

**Asserted in all 36:**

- no day over capacity;
- no question in two worksheets;
- no question both in a worksheet and in a paper set whole;
- no original together with its adaptation;
- every worksheet question has a syllabus topic and is not outside the specification;
- no empty study day when library sessions are on.

| Plan | 3 h on 3 days | 5 h on 6 days | 12 h on 7 days |
|---|---|---|---|
| 14 days | 22 marked · 1 worksheet (5) | 32 · 2 (12) | 70 · 3 (24) |
| 30 days | 50 · 1 (5) | 74 · 2 (12) | 166 · 3 (24) |
| 60 days | 102 · 1 (5) | 150 · 3 (17) | 341 distinct of 346 · 3 (24) |
| 90 days | 154 · 1 (5) | 228 · 3 (17) | 356 distinct of 526 · 3 (24) |
| 120 days | 204 · 2 (10) | 305 · 2 (12) | 363 distinct of 705 · 4 (28) |
| 180 days | 306 · 1 (5) | 353 distinct of 459 · 3 (17) | 363 distinct of 715 · **158 worksheets (1,060 questions)** |

"Marked" means questions Revisr marks. Other totals across the 36 plans:

- **Whole-paper sessions:** 0 in every plan. The worksheets and the bank fill the days.
- **Repetition:** at most two uses of a question Revisr marks when library sessions are on, and three without them.

**What a student's worksheets look like** (`REALISM` lines; in the shorter plans every worksheet is on one of the two weak topics):

- **Time.** 5.8–6.4 minutes a question.
- **Levels.** Mostly level 3, with levels 2 and 4 in the longer plans. In the heaviest plan, levels 1–5 run 124/188/553/189/6.
- **Paper fit.** Mostly Paper 1 for the weak topics in these runs. In the heaviest plan: 429 Paper 1, 298 Paper 2, 164 both, 169 unknown.
- **Topics.** 16 of the 17 in the heaviest plan; 100 of its questions carry provisional topics.
- **Solutions.** A question-level solution page for 60–81% of questions; the rest open the publisher's whole solutions file.
- **Days.** No day over its capacity.

## Findings to act on in a later milestone

- **Worksheets are rare in most Debug plans.** The R4 rule that "days the bank can fill are never displaced" means worksheets appear only where a day has 18 or more minutes left after its 15-minute questions, or once the 363 marked questions run out. A typical plan therefore has one to four worksheets; only the heaviest has 158. Making worksheets a regular part of every week (for example, one session a week reserved for the library) is a product decision about the balance between marked practice, which produces evidence, and self-marked practice. It was not made silently here.
- **Public builds have no worksheets,** because 0 questions are approved and nothing is bundled.
- **Diagnostic tiers dominate.** Practice can move a topic by at most one tier. A topic the student has since mastered stays high until a new diagnostic. This is deliberate (diagnostic answers are the strongest evidence) but worth revisiting once there is more marked practice data.
- **Time estimates are not measured.** They should be replaced with recorded worksheet times once enough exist.
