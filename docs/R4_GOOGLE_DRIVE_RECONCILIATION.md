# R4 Google Drive reconciliation

29 October 2026. This reconciles the owner's Google Drive TMUA collection with the app's library index and the original Revisr bank. Everything was done through the authorised Drive connector, read-only. Nothing on Drive was created, moved, shared, modified or downloaded.

Per-file and per-question detail lives in `revisr-content-private`, under `drive/` and `catalogue/`. This page gives counts only.

## The owner's decision, and what it does and does not change

The owner selected every genuine question in the Drive TMUA folder, along with the original Revisr questions, as the two sources of Revisr's question library. R4 records three separate statuses for every question:

| Status | Meaning | Today |
|---|---|---|
| **Selected for Revisr** | The owner's editorial decision | Every Drive question and every original |
| **Mathematically validated** | Key and solution correctly associated; human review | No Drive question and no original has been checked by a person. The keys Revisr marks with are AI-read or author keys (see `R4_UNIFIED_QUESTION_CATALOGUE.md`) |
| **Legally distributable** | Rights to reproduce the question in an app given to others | None. Selection is not a licence (see `R4_CONTENT_RIGHTS_AND_AVAILABILITY.md`) |

## Drive: files and documents

The folder was re-listed recursively on 29 October. It is the snapshot `drive/snapshots/drive-2026-10-29.json`, with 19 folders.

| Measure | Count |
|---|---:|
| Files | 343 (550.5 MB; 8 of them are videos) |
| Distinct documents, after removing copies inside Drive | 262 |
| Copies inside Drive | 81 |
| Files already represented in the app's library | 323 (287 byte-identical, 27 renamed, 9 re-encoded) |
| Files not in the library | 20 |

**Compared with the 26 October audit, nothing has changed.** The same 343 file IDs are present, with the same titles, sizes, folders and created and modified times.

`Scripts/drive_inventory.py sync` confirms this: 343 unchanged, 0 changed, 0 moved, 0 new, 0 missing. Its incremental behaviour is described below.

Of the 20 files not in the library:
- **5 are question papers:** TMUA Specimen Paper 2, MAT 2009, MAT 2012, MAT 2013, and IMC 2022. They have now been indexed.
- **15 hold no questions:**
  - the official 2022 answer key, which R1 already used to confirm keys;
  - 7 PMT handwritten MAT solution sets;
  - 4 TMUA.co.uk guides;
  - a links document, a note and a spreadsheet.

## Questions, not files

| | Questions |
|---|---:|
| Library index: indexed questions in the 133 question-bearing papers, all of which come from Drive | 2,600 |
| Drive question papers newly indexed in R4 | 93 (Specimen Paper 2: 20; MAT 2009, 2012 and 2013: 16 each; IMC 2022: 25) |
| Questions identified only from solutions the collection holds (TMUA 2023 Papers 1 and 2, MAT 2023–2025). Their question papers are held nowhere in the collection | 61 |
| **Questions identified in the Drive collection** | **2,754** |
| Reprints merged into an earlier appearance | −7 |
| **Unique Drive-collection questions** | **2,747** |
| Original Revisr questions (distinct identities; 126 versions) | 104 |
| **Unique canonical questions in the unified catalogue** | **2,851** |

**Overlap between the collections.** Each of the 259 official TMUA study copies in the private bank is the same question as one library-index entry. Each one is a single catalogue identity: its bank item is an alias that marks it. No original duplicates a Drive question; the originals were written from the specification without consulting past papers.

The R4 indexing of the 154 new questions is AI-assisted: question numbers, pages, topic, paper fit and a difficulty estimate. It is recorded as such and has not been reviewed by a person.
- For the five held papers, pages were read from the papers' text through the connector.
- Solution pages were read from the bundled solution PDFs.
- All 125 multiple-choice answers in these documents are stated in their solutions. They are kept privately, are not imported as keys, and are not used for marking, because the questions are not presentable in the app.

## Duplicates

Detection is deterministic, followed by a judgement:
1. **File level.** Drive copies are matched by normalised title and byte size, and against the bundled library by manifest filename and byte size (`drive_inventory.py`).
2. **Content level.** The page text of all 136 bundled papers was extracted on this Mac with PDFKit (no OCR). Every 10-word passage was fingerprinted, and passages shared by exactly two papers were collected; passages shared by three or more papers are instructions and stock wording. Pairs of pages sharing at least 8 passages became candidates: 45 non-cover page pairs. One of them holds two related questions, so 46 question pairs were judged.
3. **Judgement.** An AI reader compared each candidate pair, rendering the pages where the extracted maths was garbled. It classified each as same, adapted, shared context or boilerplate. This is AI-assisted, not human-reviewed.

| Result | Question pairs | Treatment |
|---|---:|---|
| Same question reprinted | 7 | Merged into one identity. The later appearance becomes an alias, listed as "also printed in" |
| Adapted (changed numbers, options or question asked) | 22 | Kept as two questions, linked as a variant. The planner never puts a variant in a worksheet with its original |
| Shared context (3) or stock wording only (14) | 17 | Distinct questions |

The merged reprints:
- **Official questions reused:**
  - one official TMUA question set twice (2019 Paper 2 Q2 and 2020 Paper 1 Q2);
  - one Tyler Tutoring topic-bank question that reprints an official 2020 Paper 2 question.
- **Repeats within an independent provider:**
  - three Beyond Horizon questions repeated across its sets;
  - one Beyond Horizon question that reprints MAT 2014 Q1I;
  - one Tyler Tutoring question repeated between a mock and a topic bank.

The canonical identity is the official appearance before other admissions tests, those before competitions, and competitions before independent mocks; then the earlier year. Concepts are never merged: two questions on the same idea stay two questions.

**Limits.**
- The scan cannot see a reprint whose text could not be extracted (scanned pages), or one printed in three or more papers.
- It does not compare papers with themselves.
- The adapted pairs show that several independent mocks borrow from official papers. The 22 links are what the scan found, not a complete list.

## Reconciliation with the original iOS library

| Question in the library index | Count |
|---|---:|
| In Drive | 2,600 (all) |
| In the bundled resources (development builds) | 2,600; every source PDF is bundled |
| With a native question record that Revisr marks | 259 official TMUA questions (one more official question, 2020 Paper 1 Q2, is a merged reprint and is marked through its 2019 identity) |
| Linked to a solution at question level (verified page) | 1,747 |
| Linked to a solution at paper or section level only | 525 |
| With no solution in the collection | 328 (CSAT 80, BMO 93, Beyond Horizon 140, STEP 13, MAT 2) |
| Duplicate of another question | 7 merged; 22 adapted |
| Source metadata corrected | 4 TMUA mock set labels (from R2); provider attribution per paper in `TMUAResourceProviders.json` |
| Available to a student in development builds | All 2,600, as 2,593 catalogue questions (the 7 reprints open as the question they repeat): 259 marked by Revisr; 2,334 opened at their page in the paper, 1,895 to self-mark against a solution and 439 to record a result. The planner sets them as worksheets (1,098 are eligible) or as whole papers (99 are eligible) |
| Automatically markable | 259 |
| Needs self-marking or a recorded result | 2,334 catalogue questions in development builds. In public builds all 1,609 listed questions open on publishers' sites |

**Missing metadata.**
- 462 catalogue questions carry the library topic "Mixed / problem solving" or "Games, invariants & strategy", which do not map to a syllabus topic. They are filterable as "Beyond the TMUA specification".
- 373 have no Paper 1 or Paper 2 fit.
- All 2,851 carry an estimated difficulty; none is calibrated.

## Incremental Drive synchronisation

`python3 Scripts/drive_inventory.py sync INVENTORY SNAPSHOT [--repo .] [--write OUT]` compares a new metadata snapshot with the inventory. Files are matched by Drive file ID, which survives renames and moves.
- **Unchanged:** the classification carries over, so the collection is never re-audited.
- **Changed** (modified time or size): the file keeps its classification and is flagged `needsReindex`. The library sources it backs are listed for re-indexing.
- **Moved or renamed:** metadata is updated and nothing is re-indexed.
- **New:** a placeholder record is added, matched against the bundled library, and queued for classification.
- **Missing:** the record is kept, with `missingSince`. Nothing is deleted, so historical attempts and provenance stay valid.

Its output has counts only. Tests: `Scripts/tests/test_drive_inventory.py`, 9 tests on synthetic inventories. Re-indexing a changed paper keeps question identities: a new version is created only when a question's content changes, and saved diagnostics stay pinned to the versions they used.

The R4 pipeline, step by step:
1. `drive_inventory.py sync` takes the new snapshot.
2. New question papers are indexed into `catalogue/supplement-index-*.json`.
3. Candidates from a fresh duplicate scan are judged into `catalogue/duplicate-review-*.json`.
4. `tools/build_reconciliation.py --repo ../revisr` regenerates the public `TMUACatalogueReconciliation.json`. `--check` fails if the public file is out of date.

There is no hosted sync service.
