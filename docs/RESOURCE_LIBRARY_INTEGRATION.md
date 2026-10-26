# Resource library integration

How the original Revisr library, the official TMUA study copies and the Revisr bank come together in the student-facing app, and what each build shows. Sources and rights: `QUESTION_SOURCE_AND_LICENSING_MATRIX.md`. Why it was disconnected: `ORIGINAL_QUESTION_BANK_REINTEGRATION.md`.

## Components

| Piece | File | Role |
|---|---|---|
| Content items | `revisr/Models/TMUA/TMUAContent.swift` | Adds the `past_paper_study_copy` category and optional fields: `presentation` (paper regions), `solutionReference`, `keyProvenance`, `taxonomyProvenance`, `difficultyProvenance`, `libraryQuestionID`, plus `creditLine`. Existing banks decode unchanged. |
| Provider register | `revisr/Resources/TMUAResourceProviders.json` | Credit, verified link, kind and public access decision per provider; per-source overrides and label corrections |
| Catalogue | `revisr/Services/TMUA/TMUAResourceCatalogue.swift` | Joins the original index, the solutions manifest, the register and the files present in this build into `TMUAResourceSource` values with an access level |
| Presentation | `revisr/Features/TMUA/TMUAQuestionPresentation.swift` | Revisr text through `MathText`, or the official question as printed (cropped PDF, zoomable), a lettered answer grid and the official worked-solution link |
| Library screens | `revisr/Features/TMUA/TMUALibraryViews.swift` | Papers & sources list, source detail, self-recorded results, paper-session task |
| Self-recorded results | `revisr/Models/TMUA/TMUAResourceLog.swift` | A new SwiftData model, kept apart from `TMUAPracticeAttempt` |
| Paper sessions | `revisr/Services/TMUA/TMUAResourcePlanning.swift` | Self-marked papers for study days the bank cannot fill |
| Build gate | `Scripts/assemble_tmua_content.py` | Validates paper-presented items; study copies never pass the public gate |

## What the student sees

**Questions → Practice questions** lists every eligible question with filters supported by real metadata:
- paper;
- topic, then syllabus strand;
- difficulty, labelled as estimated;
- source type, shown only when more than one is present;
- status: not attempted, attempted, incorrect last time, flagged.

Each row shows the strand, the estimated level and either its history or its credit.

**Questions → Papers & sources** lists every source available in this build, grouped by type (official TMUA papers, other admissions tests, independent mocks, competitions, reference), with type and source filters. A source screen shows:
- the provider credit, type and any label correction;
- the paper (development builds), its worked solutions or mark scheme, and the provider's own page;
- a whole-paper result to record;
- every indexed question with its original topic, estimated difficulty and page. Official questions with a verified key open as auto-marked practice. Others offer "Open at page n" and "Record result" (correct, incorrect, partly right, attempted).

Self-recorded results update progress and the plan, never topic evidence.

## What each build shows

| | Development (Debug) build on the owner's iPhone | Public (Release) build |
|---|---|---|
| Revisr originals | 87 versions, labelled "draft, not yet reviewed" | 0 (none approved) |
| Official TMUA questions | 259 study copies, auto-marked | 0 |
| Diagnostic | Mixed: for example 12 official and 8 original in a Balanced diagnostic on the iPhone | Blocked ("no rights-cleared past or mock questions") |
| Papers & sources | 136 sources as personal study copies | 83 sources from UAT-UK, Oxford, OCR and UKMT, linked to their pages, not reproduced |
| Bundled PDFs and videos | Present | All 242 stripped; the gate refuses an archive containing them |

**Public builds today:** the Papers & sources screen sits in the main tabs, which open after the diagnostic. So until a public diagnostic exists (original-only, or licensed content), public users would not reach the library. Exposing it from the diagnostic hub is a product decision and was not made here.

## Diagnostic selection

- **Source mix:** `TMUADiagnosticSelector` (now `tmua-selector-v2`) prefers real past or mock questions, licensed or study copies, up to half of each section (`TMUAContentPolicy.preferredLicensedShare = 0.5`). Topic and strand coverage still outrank source mix.
- **Two pre-existing defects fixed:**
  1. The section total was recomputed after every pick. That inflated the difficulty-band targets and the preferred share as the section filled; at a 50% share a section became entirely past-paper.
  2. Equal scores were broken alphabetically, so every student met the oldest paper's first questions. Ties now use a stable hash of the question identity, which is still deterministic.
- **Unchanged:** the 10, 15, 20 and 40 lengths, pause and resume, expansion, the evidence-confidence model and scoring.
- **Disclosure:** each diagnostic records its composition, for example "8 original Revisr, 12 official past-paper questions", with the development-build notice that study copies are not licensed content.

## Planner

- **More questions:** in development builds the planner's pool grows from 82 to 341 distinct questions. Official questions are planned like any other auto-marked practice: diagnostic evidence, topic priority, spaced review and mistake review.
- **Paper sessions (opt-in, used by the app):** on a study day the bank cannot fill, the plan adds a self-marked paper:
  - **Order:** official TMUA papers without keys first, then TMUA-format mocks, MAT, SMC and STEP.
  - **Never repeated:** a paper already recorded is never offered again.
  - **Never displacing:** they never take a day that has question practice, and they are rebuilt with the plan on every refresh.
  - **No evidence:** completing one records a `TMUAResourceLog` and no question-level attempt.
- **Content notice:** the plan's notice now counts paper-session days alongside days with no task.

Audit on the bundled development bank (`revisrTests/TMUA/TMUACatalogueAuditTests`, Balanced diagnostic, exam 14–180 days ahead):

| Window | 3 h a week, 3 days | 5 h a week, 6 days | 12 h a week, every day |
|---|---|---|---|
| 14 days | 22 questions, all distinct, 36% official | 32, 34% official | 70, 51% official |
| 30 days | 50, 48% | 74, 53% | 166, 63% |
| 60 days | 102, 58% | 150, 59% | 346 tasks, 324 distinct, 74% |
| 90 days | 154, 61% | 228, 70% | 526 tasks, 333 distinct, 71% |
| 120 days | 204, 68% | 305, 74% | 706 tasks, 340 distinct, 71% |
| 180 days | 306, 75% | 459 tasks, 328 distinct, 71% | 1,049 tasks, 341 distinct, 72% |

- **No empty days:** in every scenario no study day is empty, with or without paper sessions, and new questions keep arriving until 1–3 days before the exam.
- **Repeats:** only the heaviest loads repeat questions, and then within the spaced-review limit (at most 4 uses).
- **R1 comparison:** with the 60-question bank in R1, plans beyond 4–8 weeks left gaps.
- **Paper sessions:** they never trigger with this bank. They matter for smaller banks: `TMUAQuestionBankIntegrationTests` shows them filling the empty days of a 24-question bank without displacing practice.

## Tests

| Area | Tests |
|---|---|
| Library indexing and access | `TMUAQuestionBankIntegrationTests`: every family has a provider; the development catalogue keeps all 136 sources and 2,600 questions; the public catalogue lists only UAT-UK, Oxford, OCR and UKMT, with HTTPS links and no bundled solutions; label corrections; auto-marked questions link to their items |
| Rights classification and attribution | Study copies never pass the public gate, even with cleared fields; credit wording; source-mix status; build-script tests for study copies (`Scripts/tests/test_assemble_tmua_content.py`) |
| Question eligibility and answer versions | The bundled bank's study copies: letters-only options, key among the printed options, provenance recorded, paper and solution bundled, unique library identity, duplicate excluded |
| Mixed selection | Official and original questions mixed, including harder levels; on the bundled bank, official picks span at least three papers |
| Plan assignment | Official questions scheduled as auto-marked practice; paper sessions fill only empty days, never repeat a finished paper and never create evidence |
| Drive manifests and duplicates | `Scripts/tests/test_drive_inventory.py` |
| Typography | `MathTextLayoutTests`, `TMUAQuestionTypographyUITests` |
