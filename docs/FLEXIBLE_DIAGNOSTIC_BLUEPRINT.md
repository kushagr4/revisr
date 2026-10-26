# Flexible diagnostic blueprint

Revisr's diagnostic is a preparation assessment, not an official TMUA administration. It never produces a scaled or 1–9 score.

## Lengths

| Option | Paper 1 | Paper 2 | Total | Advisory time | Confidence label |
|---|---:|---:|---:|---|---|
| Starter | 5 | 5 | 10 | 19 + 19 min | Provisional |
| Quick | 8 | 7 | 15 | 30 + 27 min | Screening |
| Balanced | 10 | 10 | 20 | 38 + 38 min | Developing |
| Comprehensive (recommended) | 20 | 20 | 40 | 75 + 75 min | Broadest available |

The official format is two 75-minute papers of 20 questions. Shorter sections get proportional advisory time (75 × n / 20, rounded up) and are labelled "abbreviated section". Nothing expires and nothing is submitted automatically. Source: `TMUADiagnosticLength`.

The length is chosen in onboarding and stored on the profile. It can change only while no section has started and no answer or flag exists (`TMUADiagnosticService.changeLength`). After that, the only way to answer more questions is an expansion round.

## Structure

`TMUADiagnostic` (one per profile) → rounds → one `TMUADiagnosticSection` per paper per round → `TMUADiagnosticItem` per pinned question version. Each item stores a JSON snapshot of its exact version (stem, options, key, solution, taxonomy), so a draft stays renderable and markable if a later bank drops that version. Answer keys and solutions are shown only after the section is submitted.

Paper 2 of a round unlocks when Paper 1 of that round is submitted, matching the official order. Students may leave between sections for any length of time.

## Timing, pausing and interruption

| Event | Effect on recorded time |
|---|---|
| Start or resume | `runningSince` set |
| Pause button | Elapsed time added, timer stopped, `pauseCount` incremented; answers remain saved |
| App leaves foreground (background, lock, call, app switcher) | `scenePhase` ≠ active pauses the timer; the section is **not** submitted |
| Leaving the assessment screen | Timer paused |
| App terminated while a timer runs | On next launch, time counts only up to the last saved interaction (`lastSavedAt`); later wall-clock time is discarded and `recoveredInterruptionCount` increments |
| Submission | Remaining running time added; status locked |

Every answer, flag and navigation step is saved to SwiftData immediately. The current question index persists, so a student who closes the app on question 7 reopens on question 7. Relaunch never creates a new question set: `create` returns the saved diagnostic when one exists.

## Scoring

Correct = 1, incorrect = 0, unanswered = 0, no negative marking. Marking uses the pinned key from the item snapshot. A second submission is rejected. Raw scores are reported per paper and combined, out of the number of questions actually answered in that diagnostic (a 15-question diagnostic reports out of 15).

## Results

`TMUADiagnosticReportBuilder` produces paper and combined raw scores, answered/skipped counts, active time, topics sampled vs not assessed, topic and Paper 2 reasoning-skill evidence (see `DIAGNOSTIC_EVIDENCE_CONTRACT.md`), the length's confidence explanation, the source-composition note and a timing note. The confidence label follows the evidence actually collected: during an unsubmitted expansion round the earlier length's wording is kept.
