# Revisr iOS to Web domain handover

Updated 11 October 2026 on `codex/ios-completion`. This describes the current Swift contract for a future TypeScript implementation. The parity JSON contains synthetic cases run against named production functions. SwiftData lifecycle, paper selection against the bundled catalogue, and full application behavior were not run in this environment.

## Source package

The external package at `/Users/kushagra/Documents/revisr-domain-handover/revisr-domain-handover.zip` contains verbatim copies of selected Swift files and tests, the parity fixture, a README, and SHA-256 manifest. It has no PDFs, videos, resources, personal stores, credentials, simulator data, or recovery archives. Its tests are references; executing them needs the complete iOS project, XCTest target, and seeded catalogue resources. See the package README for its manifest and dependency inventory.

Production sources included:

- `revisr/Models/ModelEnums.swift`, `revisr/Models/AppSettings.swift`
- `revisr/Models/Admissions/AdmissionsEnums.swift`, `AdmissionsModels.swift`, `DiagnosticModels.swift`, `PublicPreparation.swift`, `PublicProgrammeModels.swift`
- `revisr/Services/DateUtilities.swift`
- `revisr/Services/Admissions/AdmissionsServices.swift`, `SolutionLibraryService.swift`, `DiagnosticAnalysis.swift`, `DiagnosticAssessmentService.swift`, `DiagnosticPaperSelector.swift`, `PublicPreparationService.swift`, `PublicPlanningEngine.swift`, `PublicProgrammeService.swift`

Reference tests: `DiagnosticWorkflowTests.swift`, `PublicPlanningEngineTests.swift`, `PublicProgrammeServiceTests.swift`. The six unavailable historical migration fixtures are not included.

## Runtime boundary

The platform-neutral core is `PublicProgrammeAvailability`, `DiagnosticAnalysis`, and `PublicPlanningEngine`, with their value types and policies. `DiagnosticAnalysis.report` and `PublicPlanningEngine.generate` ran in a native macOS harness on synthetic records. The planner consumes an input snapshot; it does not fetch data, access PDFs, persist records, or render UI.

Preparation, paper selection, assessment, and programme services use SwiftData `ModelContext`/`@Model`. `DiagnosticPaperSelector` also uses `Bundle` resource resolution and catalogue relationships. PDF presentation uses PDFKit in SwiftUI views; navigation and interactions are SwiftUI. A Web implementation needs its own persistence, resource and UI adapters around a parity-tested TypeScript core.

Planner inputs are exam kind, start/exam dates and `Calendar`, weekly minutes, weekday availability, diagnostic topic signals, filtered questions and optional complete-paper candidates. Outputs are dated tasks, topic priorities/reasons, available-day count and unfilled-day count. Programme/task identities are added in `PublicProgrammeService`, not by the allocator.

## Diagnostics

### Paper selection (source inspected; XCTest not run here)

`DiagnosticPaperPolicy.forExam` requires two fixed source IDs per exam:

- TMUA: `SRC-E29687FAAA262C5F`, `SRC-D475EB66A3CA6BF0`; 20 questions, 75 minutes; verified local PDF solution mapped to every question.
- SMC: `SRC-802E1A98D14C82D9`, `SRC-EB34C15CFA44A832`; 25 questions, 90 minutes; verified local PDF solution mapped to every question.
- BMO1: `SRC-8C463E1A9E242017`, `SRC-385D3DE51F5BA6A6`; six questions, 210 minutes; ten self-estimated marks per question, no solution requirement.

Selection rejects unavailable/inactive local papers, incomplete one-based question numbering or invalid PDF pages, protected/ineligible/unusable or duplicate-risk questions, wrong exam stream, TMUA Actual benchmark questions, duplicate IDs across the two papers, and missing/unverified/incompletely mapped PDF solutions when required. These IDs are local catalogue identity; the package does not include papers or grant reuse rights.

### Lifecycle (source inspected; not executed in this milestone)

Assessment ID is `public-diagnostic-v1-{profile UUID}-{exam raw value}`; paper IDs append `-P1`/`-P2`; response IDs combine paper and question IDs. Re-entry validates the saved paper IDs and response question sets. Paper two is locked until paper one completes. Submission locks answers and changes status to marking. Timer storage is `Double` seconds; elapsed intervals are clamped nonnegative. The report converts accumulated seconds to `Int`, truncating fractional seconds. On re-entry, an orphaned running timestamp is cleared so time outside the app is not counted. TMUA/SMC accept A–E and self-marking. BMO stores proof attempted, notes and integer self-estimated marks 0–10. Completing both papers advances only the matching profile/exam. Diagnostic records do not create historical `QuestionAttempt` rows.

The Web port must model states and stable IDs explicitly. A changed saved selection must not silently create a different assessment. Web transaction/persistence semantics require independent tests; the pure fixture does not establish SwiftData parity.

### Scoring and evidence (production analysis executed)

- TMUA displays correct answers among assessed answers and the number of questions; it does not report a scaled score.
- SMC reports `25 + 4 × correct − incorrect` out of 125 when every answered response is assessed. Unanswered earns no additional points beyond 25. If some answers are unassessed, it shows correct/incorrect and the unassessed count instead of a partial score.
- BMO marks are user estimates. A complete score is `marks / (response count × 10)` only when all attempted proofs are marked; otherwise recorded marks and unassessed proofs are stated. No attempted proof displays “No proofs attempted”. Provenance says no bundled examiner mark scheme. BMO never produces `strongDifficulty`.
- Evidence maps correct to 1 and incorrect to 0 for TMUA/SMC, and BMO marks to `marks / 10`. “Answered” is selected option for TMUA/SMC and `wasAttempted` for BMO. Answered but unassessed increments unassessed coverage.
- Non-BMO strong difficulty requires ≥4 assessed responses across both papers, ≥3 low values (`≤0.4`), and a low response at difficulty 1–3. Possible improvement requires ≥2 assessed, ≥2 low and at least half low. Relative strength requires ≥4 assessed across both papers, ≥4 high (`≥0.8`) and at least 75% high. Otherwise evidence is insufficient. BMO shares possible/relative thresholds, but strong difficulty is disabled.
- Evidence joins responses to active paper IDs and known questions. Topic/skill output orders by level (strong, possible, relative, insufficient), then name.

Executed diagnostic fixture cases: TMUA strong difficulty on four misses split across two papers; one-miss low-evidence boundary; SMC 32/125 from 2 correct, 1 incorrect, 1 unanswered; BMO 3/10 and 4/10 self-estimates with possible-improvement wording. Other threshold combinations, empty/unassessed-only cases, zero-attempt BMO, skill aggregation, selector and persistence are source/XCTest-only here.

## Adaptive planning

### Ordering and allocation (production planner executed)

Exam day is exclusive. Dates normalize to start of day in the supplied calendar. Start on/after exam day errors. At least one available weekday is required. Weekly minutes divided by available weekdays must meet the per-question allocation: TMUA 15 minutes, SMC 12, BMO 45. Empty suitable-question input errors. Tasks use calendar dates, with no time of day.

Topic base ranks are strong difficulty 40, possible improvement 30, insufficient or no signal 20, relative strength 10. The engine adds recent attempt influence for attempts 0–21 calendar days before plan start, inclusive: incorrect/partial +3 each capped at 8; correct −2 each capped at 4. Rank sorts descending, then topic name ascending. Slot selection reweights each topic by `(rank × (other-topic-assigned-count + 1))` and applies the same name tie-break. Preserve this exact formula.

Integer weekly-minute remainder goes first to available weekdays in Monday-to-Sunday `Weekday.displayOrder`. Each available date receives at most six slots. During the final three calendar days before the exclusive exam boundary, activity is final review and usable capacity is `max(questionMinutes, capacity / 2)`, bounded by daily capacity. Other first slots are targeted; later slots can be mixed, timed (slot two every third available day) or consolidation. Every tenth available day, outside final review, a complete paper may be allocated in source-ID order if its exact question count and full duration fit; its questions are reserved.

Question IDs are unique within a generation. Failed/partial or review-flagged questions can enter error review when the last attempt is at least three calendar days before that task, or when no attempt date exists. Slot one prefers review. Fresh questions have no diagnostic flag and no latest result. Assessed failed diagnostic questions can return for review; unassessed diagnostic questions are excluded. Skipped outcomes are neither fresh nor a review candidate unless the question has a review flag. If the preferred topic has no candidate, review/fresh fallbacks can select from other topics by priority. Every task includes the production reason string. The planner's `hasSolution` field is not consulted by the allocator; the service filters non-BMO questions for verified solution availability before creating planner inputs.

The engine does not enforce catalogue protection, PDF presence, exam-stream eligibility, verified solutions, legacy reservations or import status. `PublicProgrammeService.makeInput` filters candidates first: active source/PDF, valid page, active/schedulable/usable/unprotected question, no duplicate risk, correct stream, not in frozen IDs or legacy assignments, and not TMUA Actual. Non-BMO questions need an active verified PDF solution link; BMO does not. Planner fixtures do not verify this catalogue gate.

### Programme refresh (source inspected; XCTest not run here)

Programme ID is `public-programme-v1-{profile UUID}-{exam}`. Stable task ID combines programme, local-calendar `yyyyMMdd`, activity raw value, and question ID or source ID. Retrieval sorts by scheduled instant then stable ID. With unchanged settings, refresh freezes active incomplete tasks from today through the next three calendar days and regenerates from the following day. Changed settings regenerate from today. For diagnostic review, non-BMO incorrect responses become review evidence; BMO responses become review evidence at self-estimated marks ≤4. Completed tasks remain in history; other incomplete old tasks are retired; matching unfinished task IDs may reactivate. Question completion records a `.programme` attempt with nonnegative seconds and links its UUID to the task; duplicate completion errors. Full-paper completion stores no fabricated score/attempt. Progress includes active tasks and completed tasks, but not retired incomplete tasks.

Tests for refresh, completed-work preservation, relaunch and progress are included but were not executed here. Completed-work preservation is not in the executed fixture because the service requires SwiftData.

## Cross-platform contract and verification limits

- Fixture dates are Gregorian civil dates in explicit UTC. App defaults use Gregorian calendar, autoupdating local timezone/locale, Monday first weekday and four minimum days in the first week. Do not parse date-only strings as UTC then shift a study date.
- Foundation weekday numbering is Sunday=1 through Saturday=7; wire/storage values are weekday names. Missing schedule entry returns `nil`; a configured rest day returns `false`.
- Weekly target/task duration are integer minutes; elapsed diagnostic timer is double seconds. Counts and BMO marks are integers. Any display rounding must be explicit and tested. Never scale scores or relabel self-assessment as examiner verified.
- Preserve question/source/assessment/programme/task IDs and enum raw strings. Swift string sorting can differ from JavaScript; define an explicit comparator and test equal ranks and non-ASCII labels.
- Availability snapshots use Codable enum values. Swift accessors fall back to public defaults if bytes are absent/invalid; Web migration needs a deliberate compatibility rule.
- Preserve user-facing provenance/reason meaning and evidence grounding. Do not add mastery or predicted-grade metrics.

The native harness at `docs/fixtures/production-logic-smoke.swift` compiles the actual five production files named in `docs/IOS_BUILD_AND_TEST_RECOVERY.md` with synthetic in-memory substitutes for SwiftData record types. Run it with `docs/fixtures/run-production-logic-smoke.sh`; validate fixture schema/required cases with `python3 docs/fixtures/validate-public-domain-fixture.py`. It asserts availability true/missing/false, deterministic priorities/tasks/reasons, one-day final review, zero-available-day error, diagnostic-review eligibility, unassessed diagnostic exclusion, low evidence, TMUA, SMC and BMO analysis. It does not run paper selection over bundled records, SwiftData, full-paper scheduling, all exam-specific planning, UI, or a complete iOS build. The six unavailable historical migration fixtures remain unresolved.
