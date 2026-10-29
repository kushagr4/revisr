# R5 · Worksheets and the daily study flow

R4 introduced topic worksheets of three to eight self-marked questions. A read-only audit of the R4 implementation found these problems:

- **Unlinked results.** Per-question results were not linked to the worksheet.
- **One manual total.** A worksheet was finished with a single total typed into a form, and that total could be "Correct 8/8" with nothing opened.
- **Wrong stepping.** Previous and Next walked the source paper rather than the worksheet.
- **No progress.** There was no progress or resume.
- **Rewritten on refresh.** A refresh could replace a worksheet the student had started.

R5 rebuilt the worksheet around question-level results, without a new data model.

## Data: no new entity, no migration

- **Per-question results.** These are `TMUAResourceLog` rows carrying the worksheet's task ID (`programmeTaskID`) and the question's catalogue ID. The model already had both fields.
- **New outcome.** The outcome is stored as a string. R5 adds `skipped`, and `attempted` is shown as "Not yet checked". An older build reading `skipped` would show it as "Not yet checked"; it would not show it as a result.
- **Progress.** `TMUAWorksheetProgress` (`Services/TMUA/TMUAWorksheetProgress.swift`) derives everything from those rows: the latest result per question in this worksheet, counts, the next question without a result, and the state.

| State | When |
|---|---|
| Not started | No result recorded in this worksheet |
| In progress | Some questions recorded |
| All recorded | Every question has a result; not yet finished |
| Completed | Finished, every question worked |
| Completed with gaps | Finished with questions skipped or never recorded |

A worksheet finished before R5 had one manual total and no question results. It is shown as "Completed · <its original note>", never as "completed with gaps".

## Recording and finishing (integrity rules)

- **Recording.** `recordWorksheetResult` accepts only a question of that worksheet, and only while the worksheet is unfinished. A later result replaces an earlier one in the tally; both stay in the question's history.
- **Recording never completes the task.** Opening a page records nothing.
- **Finishing.** `finishWorksheet` needs at least one question actually worked; skipped questions do not count, and "Skipped" for everything finishes nothing. It writes one summary row: correct count, question count, the minutes recorded and an overall outcome. It then completes the task with a note such as "Self-marked: 5 correct · 2 incorrect · 1 not recorded".
- **Unrecorded questions.** These are never counted as correct. If any remain, the app asks first: "They stay unrecorded and are not counted as correct."
- **Whole-paper results.** The result sheet starts with no outcome selected, so Save is disabled until the student chooses one. "Skipped" is not offered for a whole paper.
- **Not evidence.** Self-reported results never create a `TMUAPracticeAttempt`; `testSelfMarkedResultsNeverBecomeEvidence` checks the planner's priorities are unchanged. See `R5_ADAPTIVE_REVISION_VALIDATION.md` for what they do influence.

## The worksheet screen

- **Header.** "Topic worksheet · self-marked", the number of questions and estimated minutes, the publishers ("From UAT-UK and JZ Maths"), a progress bar and the state line.
- **Primary action.** "Start with question 1", "Continue with question k" or "Review your answers". It resumes at the first question without a result, so position survives leaving the app without extra storage.
- **Question rows.** Each row shows the question's number, paper and question label, publisher, estimated level, page, and its result in this worksheet.
- **Finish.** "Finish the worksheet" is enabled only once a question has been worked. Afterwards the screen shows "Finished <date> · <tally>" and "Back to Today".

## The worksheet question screen

`TMUACatalogueQuestionView` with a worksheet context:

| Element | Behaviour |
|---|---|
| Header | "Question 3 of 8 · <topic> worksheet", the source and question label, and the credit line "Source: <publisher> · <paper> · Q<label>", with topic provenance (for example "(provisional)") |
| Open the question | Opens the bundled paper at its page (unchanged PDF navigation) |
| Open the solution | Opens the solution page, after a note to try the question first and that a solutions page can show neighbouring answers |
| Your result | One tap: Correct, Partly right, Incorrect, Not yet checked, Skip. The chosen result is marked and VoiceOver reads "Recorded". Two columns, or one at accessibility text sizes. |
| After recording | "Next question without a result". When every question is recorded, "Finish the worksheet". When a question is missing from this build, "Back to the worksheet", which finishes only after confirmation. |
| Toolbar | Overview (every question with its result; tap to jump), Previous, Next. Previous and Next walk the worksheet's own questions. |
| Flag | Matches every identity of the question, so a flag saved under a merged reprint's earlier ID shows and clears correctly |
| History | Every result recorded for the question, noting "in a planned worksheet" |

**Code review fixes:**

- A worksheet question whose stored ID later becomes a merged reprint's earlier ID is still recorded under the stored ID; it is never rejected.
- Once a worksheet is finished, its question screen shows the question's latest result, so a later tap is visible.
- A finished R4 worksheet shows its original note.
- Opened from Saved, a worksheet stays open when finishing removes it from "Worksheets in progress".

Questions with no solution in this build say: "This build has no solution for it, so Revisr cannot tell you the answer. Record how it went." Revisr never shows a solution it does not have, and never claims to mark these questions.

Opened from a paper rather than a worksheet, Previous and Next walk that paper's self-marked questions only. A question Revisr marks opens in its own practice screen, so stepping can no longer land on a question from an open diagnostic. Paper detail rows also lock a question that sits in an open diagnostic round.

## Today

- **Header.** Days to the exam, "n of m tasks · minutes planned", a progress bar and "k to do · about N minutes left".
- **Up next.** The next task with what it involves, for example "8 self-marked questions · about 45 minutes · 3 recorded" or "1 question marked by Revisr · 15 minutes". The button reads "Start", "Continue" for a worksheet under way, or "Look ahead" when today is done. A worksheet already under way is offered first.
- **Rows.** Each row gives the reason's first sentence and its state: "Not started · 45 minutes", "In progress · 3 of 8 recorded · 45 minutes", or "Completed · <note>".
- **Unfinished from earlier days.** Up to five missed tasks, each still openable. "Move unfinished work into my plan" asks for confirmation first. Refreshing rebuilds from today, keeps the next three days, completed work and any worksheet already started, and returns the missed questions to the plan.
- **Rest day.** Shows "Rest day", with the next study day's first task under "Next study day".
- **Current priorities.** The footer now says exactly what feeds priorities: the diagnostic, and recent answers that Revisr marked.

## Practice questions (marked by Revisr)

- **Earlier answers.** These are hidden until the current attempt is checked, because they name the option chosen. Before R5 a spaced-review question showed "Correct (C)" before it was answered.
- **Completed task verdict.** A completed task shows its own attempt's verdict, not a later attempt from elsewhere.
- **Leaving.** After checking, "Done · back to your plan" returns to Today.

## Interrupted study

| What | Kept by |
|---|---|
| Current worksheet question | Resumes at the first question without a result |
| Worksheet results | `TMUAResourceLog` rows, saved on each tap |
| Review flags | `TMUAReviewFlag`, saved on each toggle |
| Completion state | `PublicProgrammeTask.completedAt`, set only on finishing |
| A started worksheet through a refresh | `scheduleResourceSessions` reactivates any worksheet with recorded results, keeps its questions and day, and excludes its questions from new worksheets |
| A practice answer not yet checked | Not kept: one tap to reselect. Diagnostic sections already save every change. |
| A worksheet started under R4 | Not applicable: R4's worksheets were never released, so no student has per-question results saved without a task ID |

**Verified by:**

- `TMUAPlannerDeterminismTests.testStartedWorksheetSurvivesRefreshAfterSettingsChange`: a settings change that empties the three-day window still keeps the started worksheet, with the same questions and day.
- Journey C in `TMUAStudentJourneyUITests` (see `R5_VALIDATION.md`): record two questions, leave, terminate the app, relaunch, resume at question 3, use the overview, record all but one, finish with confirmation, and find the incorrect one under Saved.
