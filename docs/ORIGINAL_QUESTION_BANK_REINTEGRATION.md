# Original question bank reintegration

Branch `claude/revisr-question-bank-integration`, 26 October 2026. This document explains why the original Revisr library was missing from the TMUA journey, what it actually contains, and what is reconnected now. Rights and access are in `QUESTION_SOURCE_AND_LICENSING_MATRIX.md`; the library screens and planner are in `RESOURCE_LIBRARY_INTEGRATION.md`.

## What the original library contains (verified)

Counted from the bundled manifests and files on this branch:

| Item | Count | Notes |
|---|---:|---|
| Sources (papers, mocks, worksheets, references) | 136 | `revisr/Resources/AdmissionsManifest.json`, 30 families |
| Indexed questions | 2,600 | Every one has a source and a page number |
| Solution documents | 120 | 112 PDFs and 8 videos (`AdmissionsSolutionsManifest.json`) |
| Question-to-solution links | 2,364 | 1,747 at a verified page, 449 paper-level, 168 section-level |
| Questions with at least one solution link | 2,272 | |
| Bundled paper PDFs | 136 | 46 MB, `AdmissionsPapers` |
| Bundled solution PDFs | 98 | 65 MB, `AdmissionsSolutions` (14 more solution documents sit inside paper PDFs) |
| Bundled videos | 8 | 314 MB, saved with a YouTube downloader |

The historical audit figures (about 2,600 questions, 136 sources, 234 PDFs, 8 videos, more than 2,300 links) are all confirmed.

What the index records about each question, and what it lacks:

- **Paper fit:** recorded for 2,233 questions (Paper 1 400, Paper 2 270, "Paper 1 / Both" 473, "Paper 2 / Both" 451, "Both" 639); 367 have none.
- **Topic:** every question has one of 21 coarse topics. 474 are "Mixed / problem solving", and Paper 2's logic, proof and error questions share one "Logic" bucket. They do not map onto the 46-strand TMUA syllabus that the diagnostic uses.
- **Difficulty:** every question has a label (Foundation to Olympiad), and all 2,600 are marked `inferred`. None is calibrated.
- **Format:** 2,064 multiple choice; 536 written, proof or numeric (mostly STEP, BMO, MAT long questions and Kangaroo).
- **No question text and no answer key.** Each record points at a page of a PDF. Answer keys exist only inside PDFs: 7 answer-key documents (mocks), 25 mark schemes and 58 worked-solution documents.
- **Families:** official TMUA papers (12 sources, 240 questions), TMUA specimen and practice papers (3 sources, 60), MAT (15, 240), STEP (13, 163), UKMT competitions (39, 753), CSAT (4, 80), and 50 independent mocks and topic banks (889 questions across about 20 authors).

## Why the new journey did not use it

The flexible TMUA journey and the original app use two separate content systems, and nothing connected them:

1. **Different question model.** The diagnostic, practice and planner work on `TMUAContentItem`: native text with options, a key, a worked solution, a syllabus strand and rights and review fields. Original library entries (`AdmissionsQuestion`) are page references with no text and no answer key, so they could not be rendered, marked or scored.
2. **One content source.** `TMUAContentStore` loads only `RevisrContentBank.json`, which `Scripts/assemble_tmua_content.py` builds from the private workspace. That workspace held only Revisr-authored drafts (87 versions), so the new journey only ever saw AI-assisted originals.
3. **No verified keys.** Without structured, verified answer keys, the original questions could not enter an auto-marked diagnostic. The original app had the student mark their own work.
4. **No rights.** No source has permission for in-app reproduction. The public gate (`TMUAContentPolicy`) correctly excludes everything not cleared, and the build strips all 242 restricted files from Release builds.
5. **Separate navigation.** Stores with the original programme open `RootTabView`; new profiles open `TMUAFlowRootView`. Every new store still imports the full library index at first launch (`SeedDataService.seedNewInstallation`), but no TMUA screen or service ever queried it.
6. **Coarse metadata.** Even with keys, the original topics could not drive topic evidence: a "Mixed" or "Logic" label cannot update a syllabus strand honestly.

## What is reconnected

### 1. The whole library is browsable in the new journey

Questions → **Papers & sources** lists every source from the original index, grouped by type and credited to its provider. In development builds all 136 bundled sources open as personal study copies, with every indexed question, its page and the original topic and difficulty labels (marked as estimates). Public builds list only papers that their publisher's own page offers. Details are in `RESOURCE_LIBRARY_INTEGRATION.md`.

### 2. Official TMUA questions are now real, auto-marked items (development builds)

259 official TMUA questions are in the private bank as `past_paper_study_copy` items: 2017–2022 Papers 1 and 2 and Specimen Paper 1, less one question reused across papers.

- **Identity reused:** each item records the original index identity (`libraryQuestionID`, for example `TMUA-2019-P1-Q11`). Its stable ID is the lowercase form (`tmua-2019-p1-q11`). No new synthetic identities were invented.
- **Shown as printed:** the question is the cropped region of the bundled official paper, not transcribed text. Option buttons carry letters only.
- **Official keys, verified twice:** a pattern extraction and an independent blind reading of UCLES's worked solutions agreed on 264 keys. The one disagreement was resolved from the solution's own conclusion. All 40 keys for 2022 match UAT-UK's official answer key (from the owner's Drive). Every item records how its key was established.
- **Crops checked by eye:** all 260 crops were rendered and checked for the full stem, diagrams and every option, with nothing extra. 11 were re-cropped and re-checked. Option counts come from the visual check.
- **Official solutions linked:** every item links UCLES's worked solution at its page (1,747-link index plus section pages).
- **Classified against the syllabus:** topic, strand and Paper 2 skill come from an AI-assisted classification (176 high, 82 medium, 2 low confidence), recorded as awaiting human review. Six were spot-checked against the paper.
- **Duplicates:** 2019 Paper 2 Q2 and 2020 Paper 1 Q2 are the same question; only the first is kept.
- **Not included:** the 2016 practice papers (40 questions) are scanned images with several questions per page and no text layer. They stay as open-the-paper entries.

The items carry `rights` of `not_permitted` and fail the public gate by category, so they can never enter a public build (`Scripts/assemble_tmua_content.py`, `TMUAContentPolicy`, tests on both sides).

### 3. The diagnostic and planner use them

- **Diagnostic:** the selector prefers real past or mock questions (soft target 50%; coverage still comes first) and now spreads picks across papers and years. On the iPhone, a Balanced diagnostic built from the bundled bank held 12 official and 8 original questions, and its composition note says so.
- **Planner:** the planner's pool grows from 82 to 341 distinct questions. See `RESOURCE_LIBRARY_INTEGRATION.md` for the 14–180 day audit.

## What is not reconnected

- MAT, STEP, UKMT and independent mock questions have no structured, verified keys, so they remain self-marked papers. Seven mocks have answer-key PDFs and could be keyed the same way, but none is licensed and several have unclear authorship.
- No original-library question appears in a public build, and none will without written permission (`QUESTION_SOURCE_AND_LICENSING_MATRIX.md`).
- The 8 downloaded videos are not surfaced in the new library.

## Corrections to the original index (applied in the catalogue, not the manifest)

The manifest is left unchanged, because changing it would change its import revision and the stored programme of existing installations. Corrections live in `TMUAResourceProviders.json` and the private study-copy records:

- TMUA Mock B, C and D were all labelled "Set A".
- Specimen Paper 1 Q5 is on page 5, not page 4.
- The "TMUA Mock" family mixes Tyler Tutoring sets A–D with two Yotta papers; providers are assigned per source.
