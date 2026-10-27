# Google Drive TMUA resource audit

Audited 26 October 2026 through the authorised Google Drive connection, read-only: nothing on Drive was created, moved, shared, modified or downloaded in bulk. The folder is "TMUA" (owner [redacted], folder ID [redacted]), the folder previously shared. Its title, owner and contents confirm it.

The file-by-file inventory (titles, Drive IDs, provider evidence, duplicate matches) is private: `revisr-content-private/drive/tmua-drive-inventory.json` and `tmua-drive-summary.md`. This public summary gives counts only.

## Method

- **Metadata first:** every folder was listed recursively, and each file was classified from its title and folder.
- **Cover checks where needed:** where a title was ambiguous, the first page's text snippet was read (28 files) to confirm the provider and paper. No OCR was run and no question text was copied.
- **Personal notes:** the "GPT notes" folder holds personal notes, recorded by type only, never read.
- **Duplicates, checked two ways:**
  - **Agent's comparison:** byte size, filename and cover or PDF date against the files bundled in `revisr/Resources`, and against other Drive copies.
  - **Deterministic check:** `Scripts/drive_inventory.py` (title and byte size), so the result can be re-run.

## What the folder holds

| Measure | Count |
|---|---:|
| Files | 343 (551 MB; 330 MB of it is 8 videos) |
| Subfolders | 19 |
| Distinct documents after removing copies inside Drive | 262 |
| Copies inside Drive (mostly older July 2025 copies of the same papers) | 81 |

| By kind | Count |
|---|---:|
| Question papers | 164 |
| Worked solutions | 102 |
| Mark schemes | 37 |
| Combined paper and solutions | 13 |
| Videos | 8 |
| Worksheets | 7 |
| Notes, guides and other | 11 |
| Answer key | 1 |

| By provider (files, including copies) | Count |
|---|---:|
| UKMT | 87 |
| UAT-UK / Cambridge Assessment (official TMUA) | 67 |
| University of Oxford (MAT) | 65 |
| STEP (Cambridge Assessment / OCR) | 25 |
| JZMaths | 20 |
| Tyler Tutoring (Jacqueline Tyler) | 20 |
| Beyond Horizon | 7 |
| PMT Education | 7 |
| TMUA.co.uk | 6 |
| Yotta, TMUA.fyi, CSAT samples | 4 each |
| TMUA Euclid (all series) | 7 |
| Other independent authors (MioMath, Asher Falcon, James Chen, DπD Maths, Rosie, Zack, Zetta, sed) | 2 each |
| Percentile Labs (9.0 TMUA Handbook) | 1 |
| Personal notes and one unidentified spreadsheet | 3 |

Provider identity: 275 files by title, 15 by folder and 28 by a cover check; 25 are unverified. Almost all of those are inferred from a cover-checked file in the same set.

## Duplicates against the app's library

- **Already local (323 of 343):**
  - 287 are byte-identical to bundled files with the same name.
  - 27 are byte-identical under a different name.
  - 9 are the same document in a re-saved or re-encoded file, confirmed by matching cover, version and PDF date. The deterministic check counts these 9 as "not local" because their bytes differ.
- **Every local source and solution has a Drive counterpart.** The `for revisr` subfolder (244 files) is the library's origin.
- **Genuinely new to the library: 20 files.**
  - **Official TMUA (2):** Specimen Paper 2, and the 2022 answer key, which was used to confirm the 2022 keys.
  - **Oxford MAT (3):** the 2009, 2012 and 2013 question papers. They are the missing question papers for solutions the library already holds.
  - **UKMT (1):** the IMC 2022 question paper, the same situation.
  - **PMT Education (7):** handwritten MAT solutions with a CC BY-NC-ND 4.0 notice on the cover.
  - **TMUA.co.uk (4):** guides. Three are downloads personalised to your account, so they are never used.
  - **Personal or unidentified (3):** a links document, a note and a spreadsheet, none used.

**Not found anywhere:** question papers for TMUA 2023 (only its worked answers are local) or MAT 2023–2025. UAT-UK's official page offers TMUA 2016–2023, and Oxford's page offers MAT 2007–2025, so these are reachable by link.

## Corrections found while auditing

- **Swapped TMUA.co.uk filenames:** "Paper.pdf" is the worked solutions and "Solutions.pdf" is the question paper. The local manifest already has them the right way round.
- **Misnamed practice solutions:** the files named "TMUA-2016-paper-N-worked-answers" are the Practice Paper solutions.
- **Wrong set labels:** the local index labels TMUA Mock B, C and D as "Set A" (now corrected in the catalogue).
- **STEP 2015 solutions** cover STEP I–III but are linked only to STEP I.
- **The 9.0 TMUA Handbook** names its publisher (Percentile Labs, all rights reserved).

## What was imported

**No Drive file was imported or copied into either repository.** The Drive audit added these to the private workspace:
- metadata;
- confirmation of the 2022 official keys;
- the list of 20 new files.

Importing any of the new files would only ever be into the private workspace, for personal study, and none is needed for this milestone. Possession in Drive is not permission to redistribute; see `QUESTION_SOURCE_AND_LICENSING_MATRIX.md`.

## Tooling

`Scripts/drive_inventory.py`:
- `validate` checks an inventory's structure;
- `duplicates` finds Drive↔Drive and Drive↔local duplicates by normalised title and byte size;
- `summary` prints counts without titles.

Tests: `Scripts/tests/test_drive_inventory.py` (synthetic inventories only). On the real inventory it reports 343 records, 0 problems, 287 distinct documents and 29 byte-distinct from local. The difference from 262 and 20 is the 9 re-encoded files and the agent's content-based matching of Drive copies.

**Re-checked 27 October 2026** against the private inventory, without contacting Drive again. Every count in this document matches the inventory's records:
- 343 files, 551 MB, in 19 folders;
- 262 distinct and 81 Drive copies;
- 323 local (287 exact, 27 renamed, 9 re-encoded) and 20 new;
- provider evidence: 275 by title, 28 by cover, 15 by folder, 25 unverified.

The deterministic tool still gives 287 distinct and 29 not local. These are metadata counts. Drive was not re-listed, so files added or removed since 26 October are not reflected.
