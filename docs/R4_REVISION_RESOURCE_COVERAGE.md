# R4 revision resource coverage

29 October 2026. How the adaptive plan uses the whole catalogue, and whether long plans run out of material.

## Assignment types

| Type | Comes from | Marked | Evidence of mastery |
|---|---|---|---|
| Targeted, consolidation, mixed, timed, error review, spaced review, final review | Marked catalogue questions (originals and official study copies in Debug; approved questions in Release) | By Revisr | Yes |
| Diagnostic refinement | Adds marked diagnostic questions | By Revisr | Yes |
| **Topic worksheet (new in R4)** | 3–8 self-marked questions on one syllabus topic from papers in the library, weakest topics first | By the student, against the publisher's solution | No |
| Paper practice (whole paper) | A paper from the library (bundled in Debug; on the publisher's site in Release) | By the student | No |

**Worksheets.**
- **Order of topics:** the diagnostic's own evidence decides: topics showing strong difficulty first, then possible improvement, then topics without enough evidence, and relative strengths last. Ties keep syllabus order (`testWorksheetTopicsFollowDiagnosticEvidence`).
- **Order of papers:** TMUA-format papers come first, then other admissions tests, then competitions.
- **Never reused:** a question already recorded, already in a worksheet, or adapted from a question already chosen.
- **Never fresh twice:** a worksheet never takes a question from a paper the plan sets whole, and a paper with a question in a worksheet is not then set whole. Papers that are merely eligible for a whole-paper session reserve nothing (see "Found in validation" below).
- **Representation:** a worksheet stores its catalogue question IDs in the task's source ID, so it never points at a resource that does not exist. `TMUACatalogueAuditTests` checks every worksheet and paper task against the catalogue.
- **Completion:** each question opens at its page. The student records how it went, per question or for the whole worksheet. That counts towards progress and the plan, never as evidence. Opening a document is not recorded as an attempt.

## Two R4 planning changes

1. **Worksheets fill room on planned days, not just empty days.** A day the marked bank fills is never displaced. A day it leaves at least 18 minutes short of the student's daily time takes a worksheet sized to the room.
2. **Less drilling of the same question.** When the library can supply fresh self-marked worksheets, a marked question is revisited at most once (`libraryRevisitLimit = 1`) instead of two or three times. The days this frees go to fresh library questions. Without the library, as in public builds, R2's limits apply unchanged.

## Development build (measured)

From `TMUACatalogueAuditTests`: a Balanced diagnostic, plans built with library sessions, 36 scenarios over three study loads. Each cell shows distinct marked questions scheduled, then worksheets (worksheet questions), then whole papers.

| Window | 3 h over 3 days a week | 5 h over 6 days a week | 12 h over 7 days a week |
|---|---|---|---|
| 14 days | 22 · 1 (5) · 0 | 32 · 2 (10) · 0 | 70 · 3 (24) · 0 |
| 30 days | 50 · 1 (5) · 0 | 74 · 2 (10) · 0 | 166 · 3 (24) · 0 |
| 60 days | 102 · 1 (5) · 0 | 150 · 3 (15) · 0 | 342 · 3 (24) · 0 |
| 90 days | 154 · 1 (5) · 0 | 228 · 3 (15) · 0 | 354 · 3 (24) · 0 |
| 120 days | 204 · 2 (10) · 0 | 305 · 2 (10) · 0 | 363 · 4 (28) · 0 |
| 180 days | 306 · 1 (5) · 0 | 350 · 3 (15) · 0 | 363 · 138 (979) · 0 |

**Results across all 36 scenarios:**
- no empty study day;
- no day over the student's time;
- no question used more than twice; before R4 the heaviest plans used questions three times (plans without library sessions still can, under R2's limits);
- no worksheet question in a paper the same plan sets whole;
- official questions make up 18–72% of marked practice.

**Distinct resources available:**
- 363 marked questions;
- 1,895 self-marked questions with solutions, of which 1,098 are multiple choice, syllabus-mapped and assigned to a paper: the pool worksheets draw from. The other 797 are long-form, proof or numeric questions, or have no syllabus topic or paper, so they are offered in Practice and in whole papers but not in worksheets;
- 439 more to record a result;
- 99 whole papers worth setting as a session (64 in a public build, on publishers' sites).

**Content exhaustion is not a problem in development builds, but the heaviest plan comes close.** At 12 hours a week for six months the plan uses all 363 marked questions, twice at most, and 979 of the 1,098 worksheet questions, in 138 worksheets. Every study day is still filled. That leaves 119 worksheet questions, the 797 self-marked questions that suit Practice rather than worksheets, the 439 questions with no solution, and the whole papers.

**Found in validation.** The first version of the worksheet planner reserved the questions of all 99 papers eligible for a whole-paper session, whether or not one was ever scheduled. In development builds whole papers are never scheduled, because the marked bank leaves no empty study day, so 909 of the 1,098 worksheet questions were locked away. The heaviest plan then ran out at 150 worksheet questions in 22 worksheets. Now a paper reserves its questions only once the plan sets it whole. The audit checks that no question appears both in a worksheet and in a paper set whole.

**Why worksheets are few at normal loads.** The marked bank already paces fresh questions to fill most days. Worksheets mainly take the room left late in long or heavy plans.

## Public build

**Today.** No approved questions, so no diagnostic and no plan. The library lists 1,609 questions in 93 papers from UAT-UK, Oxford, OCR and UKMT, each opening on the publisher's site, so a student can still study and record results.

**If originals pass review** (measured by `TMUAPublicContentTests` in the final R4 run; 5 hours over 6 days a week; distinct marked questions, then whole-paper sessions on publishers' sites, then empty study days):

| Approved set | 14 d | 30 d | 60 d | 90 d | 120 d | 180 d |
|---|---|---|---|---|---|---|
| Review wave 1 (29) | 22 / 0 / 0 | 29 / 1 / 0 | 29 / 10 / 0 | 29 / 28 / 0 | 29 / 53 / 0 | 29 / 64 / **40** |
| Waves 1–2 (60) | 32 / 0 / 0 | 49 / 0 / 0 | 60 / 0 / 0 | 60 / 0 / 0 | 60 / 4 / 0 | 60 / 10 / 0 |
| All 104 originals | 32 / 0 / 0 | 72 / 0 / 0 | 95 / 0 / 0 | 99 / 0 / 0 | 104 / 1 / 0 | 104 / 1 / 0 |

**These public figures vary slightly between runs.** An earlier R4 run gave 23 at 14 days for wave 1 and 93 at 60 days for all originals, with paper-session counts moving to match. The worksheet changes cannot cause this, because public builds have no worksheets. It is pre-existing run-to-run nondeterminism in the planner. Development questions-only plans also moved by one question between runs. It is listed as outstanding in `R4_VALIDATION.md`.

**What remains a problem in public builds:**
- **Wave 1 alone** leaves 40 empty days in a six-month plan; R3 measured 49. The ten R4 supplement papers add publisher-linked sessions.
- **No worksheets.** Public builds have no document questions, because nothing third-party is bundled.
- **Fresh material for long plans** therefore depends on more approved originals, or on licensed questions.
