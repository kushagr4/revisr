# Adaptive revision engine

The flexible TMUA programme reuses the existing deterministic `PublicPlanningEngine` (also ported to TypeScript in Revisr Web) through `TMUAProgrammeService.planningInput`. It does not introduce a separate algorithm. New behaviour is opt-in through `PublicPlanningOptions`; `.legacy` (the default) produces exactly the earlier output, as confirmed by `PublicPlanningEngineTests` and `docs/fixtures/production-logic-smoke.swift`.

## Inputs

Start date; exam date (exam day excluded); available weekdays; weekly minutes; optional daily session cap; topic evidence from the diagnostic report; and every eligible bank item as a planning question, carrying topic, difficulty, whether it was in the diagnostic, latest outcome and date (from the newest practice attempt, else the diagnostic mark), and review flag (student flag or a skipped diagnostic question).

## Behaviour (existing engine)

- **Topic priority:** strong difficulty 40, possible improvement 30, insufficient or unassessed 20, relative strength 10, adjusted by misses and successes in the last 21 days. Unassessed topics therefore receive baseline revision, and strengths still get occasional practice.
- **Daily capacity:** weekly minutes split across available weekdays. Tasks are 15 minutes (a conservative cap including solution review). There are at most 6 per day, and the final three days are halved and become final review.
- **Activities:** targeted, mixed, timed, consolidation, error review, final review. Full papers are not scheduled because no approved full papers exist outside the diagnostic.

## Opt-in options used by the TMUA programme

| Option | Effect |
|---|---|
| `dailyMinutesCap` | Student's "longest session" preference; never exceeded |
| `paceFreshQuestions` | Introduces unseen questions cumulatively in proportion to the elapsed share of the window, so a 12-day and a 180-day plan both spread content to the end. When nothing is due for review, it may borrow up to about a week ahead. |
| `spacedReviewIntervalDays = 7` | Revisits questions with widening gaps (7, 14, 21… days). A missed question's first revisit is labelled error review; later ones spaced review. |
| `maximumSpacedRepeats` | 2 or 3 (R1: capped at `spacedRepeatLimit = 3`; was up to 6, which scheduled one question up to 7 times in long plans) |
| `balanceFallbackTopics` (R1) | When the preferred topic has no suitable question, the fallback rotates across topics instead of always using the top-priority topic |
| `minimumOneTaskPerStudyDay` (R1) | While unseen questions remain, pacing never leaves a study day empty |
| `diagnosticRefinementMinutes` | One optional "Refine your diagnostic" task (on the third study day or later) for Starter, Quick and Balanced, only when enough unseen questions exist. It is completed automatically when the added questions are submitted. |

Every task references a real eligible bank item, or is the refinement task. No fictional IDs or missing documents are created (`testRefinementTaskOfferedForShortDiagnosticsOnly`, `testInsufficientRevisionContentLeavesHonestGaps`). If capacity is below one 15-minute task per study day, generation fails with an explanation, and onboarding/Settings block saving such a profile with a suggestion.

## Adaptation and refresh

Inputs that change future work: practice outcomes (each answer is auto-marked and becomes the question's latest outcome; misses return as error review after three days and raise topic priority), flags, completed and missed tasks, changed exam date, weekly time, weekdays or session cap, diagnostic expansion, and an explicit "Refresh future plan".

Refresh rules (shared `PublicProgrammeService.applyPlan`):
- Completed tasks are never altered. Attempts, diagnostic answers and flags are separate records and are never deleted.
- Incomplete tasks in the next three days stay fixed unless preparation settings changed. Other incomplete tasks are retired (`isActive = false`), not deleted, and the plan is regenerated from the later start.
- Stable task IDs (date + activity + question) prevent duplicate active tasks.
- `revision`, `refreshedAt` and a one-line `refreshSummary` are shown in Plan, for example "More Trigonometry (+3), less Algebra (−2); 5 completed tasks kept; 4 tasks in the next three days unchanged."

Today suggests a refresh after settings change or after five completed tasks since the last refresh. Since R1 it also reports tasks missed on earlier days and offers a one-tap refresh, which retires them (kept, not deleted) and replans their questions. Refreshes happen automatically after Settings changes, when diagnostic questions are added (so those questions leave planned practice at once: `reservedStableIDs`), and after an expansion round is submitted.

## Verified windows

`testPlansFitEveryPreparationWindowAndExcludeExamDay` generates plans for 3, 7, 14, 30, 60, 90, 120 and 180 days. It checks that tasks stay inside the window and off exam day, that weekly minutes stay within capacity, that active task IDs are unique, and that windows of 60 days or more still have work in the final week and include spaced review.

## Limits

With 60 draft items, unseen questions last about 2–6 weeks; after that plans use error and spaced review, at most 4 scheduled uses per question. Long windows therefore have empty study days. The Plan tab reports them (`TMUAPlanContentSummary`) instead of filling them with repetition. The 15-minute task size is a planning cap, not a calibrated time per question. Measurements for 3–180-day windows are in `R1_DIAGNOSTIC_AND_PLANNER_AUDIT.md`.
