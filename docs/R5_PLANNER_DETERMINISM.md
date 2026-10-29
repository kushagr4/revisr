# R5 · Planner determinism

R4 reported that otherwise identical plans differed by one to three questions between runs. R5 traced the cause, fixed the latent order dependences found along the way, and added cross-process golden tests.

## The observed variation: different students, not a random planner

**Reproduction.** R4's 36-scenario library audit (`TMUACatalogueAuditTests`) was run unchanged in two separate test processes. The `AUDIT` lines differed, as R4 saw: for example the official share for "14d 3h/3d questions-only" was 14% in one process and 18% in the other.

**Cause.** The test fixture created each profile with a fresh random `AppSettings.id`.

- The diagnostic selector seeds each student's selection from the assessment identity, which contains that ID (`TMUADiagnosticSelector.seed`, policy `tmua-selector-v3`).
- So every run was a different student, with a different diagnostic, different correct and incorrect answers, different topic levels and therefore a different plan.

**Verification.**

- With the profile ID pinned (`TMUAFixtures.pinnedProfileID`), the same 36 scenarios gave byte-identical `AUDIT` output in two processes.
- A stage-by-stage probe hashed each stage for 8 scenarios across two processes: content, catalogue, sources, diagnostic selection, report, planning input, engine output and the persisted programme. Every stage was identical.

For a real student, whose ID is stored, the plan was already reproducible. Per-student variation in diagnostic selection is intended and unchanged.

## Latent order dependences fixed in R5

A read-only audit of the whole pipeline found these. Each was then checked by an independent reviewer told to refute it, and none was refuted.

| # | Mechanism | Effect before R5 | Fix |
|---|---|---|---|
| 1 | Two practice attempts at the same instant: the latest was whichever SwiftData returned first (`max(by:)` keeps the first on ties). | Which attempt counted could depend on fetch order. | `TMUAPracticeAttempt.isEarlier` orders ties by what the attempt records, the incorrect one counting as later. The same is done for self-recorded results (`TMUAResourceLog.isEarlier`) and legacy attempts. Never by record ID, which is random per store. |
| 2 | Day loops stepped with `date(byAdding: .day)` and never returned to the start of the day. Where clocks go forward at midnight (for example Santiago on 6 September 2026), every later day fell at 01:00. | Day lookups missed: library sessions were added to full days, the final-review window started a day early and empty-day counts were inflated. A completed or kept library session could be rewritten. | `PublicPlanningEngine.nextDay(after:)` returns the start of each next day. It is used by the engine, the library scheduler and the content summary. |
| 3 | A refresh could reuse a library session's row by its day key with no check. | A completed, kept or started session could be overwritten (reachable after a time-zone change). | A row is reused only when it is retired and incomplete; otherwise the day is skipped. A reused engine task also takes its planned date. |
| 4 | A refresh with an invitation to extend the diagnostic already in the next three days placed a second one further on. | Duplicate invitations after each refresh. | `generateOrRefresh` keeps the existing invitation and places no new one while it stands. |
| 5 | The timed-practice slot rotated by study days counted from the refresh date. | Refreshing on another day relabelled unchanged tasks, changing their IDs and retiring and re-adding rows. | `PublicPlanningOptions.calendarDayRotation`, set for TMUA, rotates by calendar day. The legacy planner keeps its rotation, so its parity fixtures are unaffected. |
| 6 | Diagnostic items were de-duplicated in fetch order. | Latent: one diagnostic never holds a question twice today. | Items are sorted by section and position first. |
| 7 | Library and catalogue caches were keyed by distribution and item count only. | In tests, a different bank of the same size could reuse another bank's library. | Keys include the first and last item and the bundle. |
| 8 | Questions in a paper were ordered by number and label only. | A combined Paper 1 + Paper 2 file interleaved its two papers (P1 Q1, P2 Q1, P1 Q2 …). | Paper part first and the question ID last. |

## Golden tests (`TMUAPlannerDeterminismTests`)

Each scenario fixes every input:

- the pinned student identity, the date and the Europe/London calendar;
- the availability;
- a synthetic bank of 64 items;
- a synthetic library of seven papers: an official pair, an independent mock, a MAT-style paper with its paper fit taken from the index, an SMC-style paper, a paper with no solutions and a linked-only paper.

The test serialises the whole programme, retired and completed tasks included. Each task contributes its day, stable ID, activity, question ID, source ID (which names a worksheet's questions), topic, minutes, reason and state. The test then compares the SHA-256 of that text with a digest recorded in an earlier process. Every `xcodebuild test` run is a new process with its own hash seed, so a match is a cross-process result.

| Scenario | Covers |
|---|---|
| 14 days, 3 h on 3 days | short window, low capacity, library sessions |
| 14 days, 12 h on 7 days, all diagnostic answers correct | strong evidence, high capacity |
| 30 days, 5 h on 6 days, questions only | no library |
| 120 days, 5 h on 6 days | long window, worksheets |
| 180 days, 12 h on 7 days | worksheets and whole papers |
| 60 days, 5 h on 6 days, with history | auto-marked answers (two at the same instant), a review flag, per-question worksheet results, a finished worksheet, then a refresh a week later with Saturdays dropped |

Other tests in the same file check:

- each scenario really contains worksheets, whole papers, completed and retired tasks;
- different evidence gives a different plan;
- a refresh adds no second invitation;
- every task falls at midnight across Santiago's midnight clock change;
- same-instant attempts read the same way in either order;
- a worksheet the student has started survives a refresh after a settings change (added with the worksheet work).

A golden digest changes only when planning rules change on purpose. The new value is taken from the `DETERMINISM` line, and this document records why.

**R5 history of the digests:**

1. Recorded on the determinism commit, after two processes agreed (`51f6fe8`).
2. Re-recorded once for the adaptive changes in `R5_ADAPTIVE_REVISION_VALIDATION.md`: worksheet time by question, weak-topic weighting, revisits, the evidence hierarchy, the frozen-window rule and the session cap.
3. Re-recorded once more for publishers taking turns within a topic.

Each re-recording came from two separate processes that agreed. The later review fixes did not change any digest.

## Compatibility

- **Identifiers.** Programme IDs (`tmua-flex-programme-v1-…`) and the task-ID format are unchanged. No stored task is renamed.
- **Completed work.** Completed tasks are never changed; refresh code skips them, and fix 3 adds a guard.
- **Existing plans.** No plan is regenerated at launch. A plan changes only when the student refreshes, saves settings or extends the diagnostic, as before.
- **Effect of the fixes.** They change future plans only:
  - same-instant attempts (practically unreachable, because answers are timestamped when they are saved);
  - time zones with midnight clock changes;
  - the timed/mixed label of a future task, so a few future task IDs differ after the student's next refresh;
  - a repeated invitation is no longer added.

## Known limitation

The planning calendar follows the device's time zone, and no planning time zone is stored. If a student changes time zone between refreshes, day boundaries move with it. Moving west can make the last study day fall on exam day, and can leave today's tasks outside the three-day window. Fix 3 means this can no longer overwrite a completed or kept session.

Storing the planning time zone needs a model field, so it was left for a later milestone rather than changing the schema here.
