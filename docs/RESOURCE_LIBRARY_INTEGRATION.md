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
- every indexed question with its original topic, estimated difficulty and page. Official questions with a key read from UCLES's worked solutions (AI-assisted, not yet checked by a person) open as auto-marked practice. Others offer "Open at page n" and "Record result" (correct, incorrect, partly right, attempted).

Self-recorded results update progress and the plan, never topic evidence.

## What each build shows

| | Development (Debug) build on the owner's iPhone | Public (Release) build |
|---|---|---|
| Revisr originals | 87 versions, labelled "draft, not yet reviewed" | 0 (none approved) |
| Official TMUA questions | 259 study copies, auto-marked | 0 |
| Diagnostic | Mixed: a new Balanced diagnostic holds 14 official and 6 original questions (see below) | Blocked ("no rights-cleared past or mock questions") |
| Papers & sources | 136 sources as personal study copies | 83 sources from UAT-UK, Oxford, OCR and UKMT, linked to their pages, not reproduced |
| Bundled PDFs and videos | Present | All 242 stripped; the gate refuses an archive containing them |

**Where these figures come from:**
- **Development column:** the bundled bank, the iPhone 17 Pro simulator and unit tests.
- **The owner's iPhone:** the same build is installed there, but it was not exercised for this milestone (27 October: the phone was locked and the on-device check was skipped).
- **Public column:** the Release build of 27 October:
  - the gate assembled 0 items and excluded 346;
  - the app contains no PDF or video;
  - no item identifier, title or specimen string appears in it.

  It still bundles the library's metadata manifests (source titles, topics, page numbers, solution document IDs), as it did before this work.

**Updated in R3 (28 October 2026):** the diagnostic hub now links to Papers & sources, and setup can be completed when no diagnostic is available, so public users reach the library. Independent preparation sites are listed as credited links. See `R3_STUDENT_RESOURCE_EXPERIENCE.md`. The original note follows.

**Public builds today:** the Papers & sources screen sits in the main tabs, which open after the diagnostic. So until a public diagnostic exists (original-only, or licensed content), public users would not reach the library. Exposing it from the diagnostic hub is a product decision and was not made here.

## Diagnostic selection

**Superseded for new diagnostics by v3 (R2).** This section describes v2, which still applies to diagnostics created under it. For v3's per-student selection and its composition, see `R2_DIFFICULTY_AND_SOURCE_DIVERSITY.md`.

- **Source mix:** `TMUADiagnosticSelector` (now `tmua-selector-v2`) gives real past or mock questions, licensed or study copies, a bonus until half of each section is official (`TMUAContentPolicy.preferredLicensedShare = 0.5`). This is a preference, not a cap. Topic and strand coverage outrank it, so a section goes above half when only official questions cover its remaining topics.
- **Two pre-existing defects fixed:**
  1. The section total was recomputed after every pick. That inflated the difficulty-band targets and the preferred share as the section filled; at a 50% share a section became entirely past-paper.
  2. Equal scores were broken alphabetically, so every student met the oldest paper's first questions. Ties now use a stable hash of the question identity, which is still deterministic.
- **Unchanged:** the 10, 15, 20 and 40 lengths, pause and resume, expansion, the evidence-confidence model and scoring.
- **Disclosure:** each diagnostic records its composition, for example "6 original Revisr, 14 official past-paper questions", with the development-build notice that study copies are not licensed content.

A new diagnostic on the bundled development bank (`testBundledDiagnosticDrawsOfficialQuestionsFromSeveralPapers`, 27 October). Each line is official + original questions:

| Length | Paper 1 | Paper 2 | Official papers drawn on |
|---|---|---|---|
| Starter (5 + 5) | 3 + 2, levels 2–3 | 5 + 0, levels 2–5 | P1: 2018, Specimen. P2: 2017, 2020, 2021, 2022 |
| Quick (8 + 7) | 4 + 4, levels 2–4 | 7 + 0, levels 2–5 | Same papers as Starter |
| Balanced (10 + 10) | 5 + 5, levels 2–4 | 9 + 1, levels 2–5 | P1: Specimen (4), 2018 (1). P2: 2020 (5), 2017 (2), 2019, 2021 |
| Comprehensive (20 + 20) | 13 + 7, levels 2–4 | 15 + 5, levels 2–5 | P1: 2018 (5), Specimen (5), 2019 (2), 2021 (1). P2: all six years, 2017–2022 |

The test asserts, for every length:
- **Size:** the exact length per paper, with no question twice.
- **Coverage:** a distinct topic for every Paper 1 question, up to the 14 topics.
- **Keys and credit:** every key is one of the printed options, and every official question carries its credit and a worked-solution page.
- **Stability:** the same selection when the candidates are reversed.
- **Mix:** both sources somewhere in the diagnostic.

For sections of 10 or more it also requires at least one official question and three difficulty levels; for sections of 20, official questions from at least three papers.

Two findings, both left unchanged:
- **Paper 2 leans official.** After the bonus stops, each pick goes to whichever question covers a topic not yet covered. The Paper 2 originals cover 9 topics, mostly logic and proof; the official Paper 2 questions cover 16. So the Starter and Quick Paper 2 sections are entirely official. This follows the documented rule. The remedy is more Paper 2 originals in the missing topics, not a selector change.
- **Picks cluster by paper.** No rule spreads picks across papers. Among equally scored candidates the selector takes the lowest hash. That hash order is well mixed overall (checked against random shuffles), but it is fixed, so every student gets the same draw. With this bank, Balanced Paper 1 takes four of its five official questions from Specimen Paper 1, and Paper 2 takes five of nine from 2020. A small penalty for reusing a paper within a section would spread them. It is proposed, not implemented.

## Planner

- **More questions:** in development builds the planner's pool grows from 82 to 341 distinct questions. Official questions are planned like any other auto-marked practice: diagnostic evidence, topic priority, spaced review and mistake review.
- **Paper sessions (opt-in, used by the app):** on a study day the bank cannot fill, the plan adds a self-marked paper:
  - **Order:** official TMUA papers without keys first, then TMUA-format mocks, MAT, SMC and STEP.
  - **Never repeated:** a paper already recorded is never offered again.
  - **Never displacing:** they never take a day that has question practice, and they are rebuilt with the plan on every refresh.
  - **No evidence:** completing one records a `TMUAResourceLog` and no question-level attempt.
- **Content notice:** the plan's notice now counts paper-session days alongside days with no task.

Audit on the bundled development bank (`revisrTests/TMUA/TMUACatalogueAuditTests`, Balanced diagnostic, exam 14–180 days ahead; final code, run on 27 October):

| Window | 3 h a week, 3 days | 5 h a week, 6 days | 12 h a week, every day |
|---|---|---|---|
| 14 days | 22 questions, all distinct, 45% official | 32, 38% official | 70, 51% official |
| 30 days | 50, 42% | 74, 50% | 166, 63% |
| 60 days | 102, 57% | 150, 61% | 346 tasks, 324 distinct, 75% |
| 90 days | 154, 60% | 228, 69% | 526 tasks, 333 distinct, 72% |
| 120 days | 204, 67% | 305, 74% | 706 tasks, 340 distinct, 74% |
| 180 days | 306, 75% | 459 tasks, 328 distinct, 71% | 1,049 tasks, 341 distinct, 74% |

- **No empty days:** in every scenario no study day is empty, with or without paper sessions, and new questions keep arriving until 1–3 days before the exam.
- **Repeats:** only the heaviest loads repeat questions, and then within the spaced-review limit (at most 4 uses).
- **R1 comparison:** with the 60-question bank in R1, plans beyond 4–8 weeks left gaps.
- **Paper sessions:** they never trigger with this bank. They matter for smaller banks: `TMUAQuestionBankIntegrationTests` shows them filling the empty days of a 24-question bank without displacing practice.

## Tests

| Area | Tests |
|---|---|
| Library indexing and access | `TMUAQuestionBankIntegrationTests`: every family has a provider; the development catalogue keeps all 136 sources and 2,600 questions; the public catalogue lists only UAT-UK, Oxford, OCR and UKMT, with HTTPS links and no bundled solutions; label corrections; auto-marked questions link to their items |
| Rights classification and attribution | Study copies never pass the public gate, even with cleared fields; credit wording; every bundled study copy's credit names its paper exactly as its title does (this caught Specimen Paper 1 credited as "TMUA Paper 1"); source-mix status; build-script tests for study copies (`Scripts/tests/test_assemble_tmua_content.py`) |
| Question eligibility and answer versions | The bundled bank's study copies: letters-only options, key among the printed options, provenance recorded, paper and solution bundled, unique library identity, duplicate excluded |
| Mixed selection | Official and original questions mixed, including harder levels (fixtures); on the bundled bank, every diagnostic length checked as above |
| Plan assignment | Official questions scheduled as auto-marked practice; paper sessions fill only empty days, never repeat a finished paper and never create evidence |
| Drive manifests and duplicates | `Scripts/tests/test_drive_inventory.py` |
| Typography | `MathTextLayoutTests`, `TMUAQuestionTypographyUITests` |
