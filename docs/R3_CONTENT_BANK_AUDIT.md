# R3 content bank audit

28 October 2026. What is in the private question bank, measured from the bank files, the review register and the R3 pre-review. Aggregates only; per-question status is in `revisr-content-private/review/r3-audit/bank-status.json`, regenerated with `python3 review/r3-audit/bank_status.py`.

## Starting point (verified before any change)

| Repository | Branch | Commit | Working tree |
|---|---|---|---|
| `revisr` | `claude/revisr-r2-diagnostic-quality` | `92f58a0` | clean |
| `revisr-content-private` | `master` (no remote) | `bb6f3b2` | clean |

R3 works on the new branch `claude/revisr-r3-content-readiness`, created from `92f58a0`.

## Versions, identities and published items are different things

| | Count | Note |
|---|---:|---|
| Item versions in the private bank | 385 | Each is an immutable version. Debug builds bundle them all |
| Original Revisr identities (stable IDs) | 104 | 58 Paper 1 and 46 Paper 2: 92 before R3, plus 12 new R3 drafts |
| Original versions | 126 | Includes 22 superseded versions: 5 corrected in R1 and 17 in R3 |
| Latest original versions (what new work uses) | 104 | |
| Official TMUA personal-study copies | 259 | 2017–2022 Papers 1 and 2 (139 Paper 1, 120 Paper 2) and Specimen Paper 1, shown from the official PDFs in Debug builds only |
| Historical library catalogue | 2,600 indexed questions in 136 sources (30 families) | Metadata only: topic, page and estimated difficulty. Not questions Revisr can show |
| Approved for public distribution | **0** | The manifest is empty; no human decision exists |

## Four separate qualities

| | Revisr originals (latest versions) | Official study copies |
|---|---|---|
| **Mathematical correctness** | | |
| Key is one of the printed options | all | all |
| Worked solution present | all | all, as a page in UCLES's worked-solutions PDF |
| Independent AI blind answer agrees with the key | 92 of 92 in the R3 pre-review of the versions before correction; the 12 new drafts and the 9 corrections that changed the question 21 of 21 in a second blind solve; all 17 corrections and 12 drafts also verified programmatically | Keys read from the official solutions: 190 by two agreeing AI readings, 40 from the official 2022 key, 29 from one checked reading |
| A second defensible option found | 0 | — |
| Human-verified key | **0** | **0** |
| **Originality and rights** | | |
| Originality review | written with AI assistance from the public specification without consulting past papers; **no human originality review** | not applicable; UCLES copyright |
| Rights | Revisr's own, pending the owner's declaration per question | no permission held; personal study only |
| **Educational quality** (AI-assisted tiers) | Of the 92 pre-reviewed: Paper 1 had 9 diagnostic core, 23 practice, 17 foundation only and 1 rework; Paper 2 had 24, 15, 3 and 0. Of the 12 new drafts, the blind check suggests 11 as diagnostic candidates and 1 as practice | authentic TMUA questions by definition |
| **Publication approval** | 0 | can never be published as study copies |

## Syllabus coverage (latest original versions)

- **Paper 1:** originals cover all 14 Paper 1 topics. Every topic has at least one question rated suitable for practice or diagnosis, except algebra and equations and inequalities, whose originals are all foundation level.
- **Paper 2:** originals cover 14 of 17 topics. Number, ratio and proportion, and statistics have none. Logic (15) and proof (8) dominate.

The official study copies add depth in Paper 1 equations and inequalities, integration and trigonometry. They are thin in counting and probability, geometry, and statistics.

**With R3's 12 drafts:**
- Paper 1 gains demanding questions in algebra and in equations and inequalities, so every Paper 1 topic has a question suitable for diagnosis.
- Paper 2 gains number, bringing it to 15 of 17 topics. Ratio and proportion, and statistics, still have no Paper 2 original.

## Difficulty

| | Paper 1 | Paper 2 |
|---|---|---|
| Author estimate (stored) | 15 × L2, 26 × L3, 9 × L4 | 8 × L2, 21 × L3, 12 × L4, 1 × L5 |
| Independent AI estimate (R3) | 17 × L1, 24 × L2, 9 × L3 | 3 × L1, 18 × L2, 18 × L3, 3 × L4 |
| Reviewer rating | none | none |
| Student calibration | none | none |

The AI estimate is lower than the stored level for 68 of 92 questions and never higher. Among those 92, no Paper 1 question reaches level 4 on content. The 12 R3 drafts store the lower of their author and blind estimates: 2 × L4 (both Paper 1), 9 × L3 and 1 × L2. **No original reaches level 5 on content.** The study copies' levels (64 × L2, 93 × L3, 66 × L4, 36 × L5) come from the original library index; they are also estimates, not official statistics. Stored levels were not changed in R3 (see `R3_MATHEMATICAL_QUALITY.md`).

## Duplication

- **Exact duplicates:** none. From R3, `validate` rejects two identities with the same question text.
- **Near duplicates** (AI analysis, R1, confirmed in R3): 3 Paper 2 pairs with the same logical template. R3 chose which of each pair to review first; the other is queued "review after".
- **Shared method:** 16 clusters where different questions rest on the same idea. The largest is six Paper 2 questions turning on when a conditional fails.
- **Paper 1, R3 additions:**
  - four questions use a water-in-a-container setting;
  - two share the same √x-minus-x rate shape;
  - one has an unmentioned one-line shortcut.

## Questions needing correction

| Source | Found | Outcome |
|---|---|---|
| R1 AI audit (60 questions) | 3 blocking or major, 31 minor | 5 corrected in R1 (all blocking and major) |
| R3 AI pre-review (92 questions) | 0 major or blocking; 53 minor in 39 questions | 17 corrected as new versions; the rest are cosmetic or concern foundation-level questions, and are listed as known concerns on the reviewers' key sheets |

Answer-key position (latest versions): first option 7, last 6, otherwise in the middle. The web-derived Paper 1 set never puts the key last. Corrections varied the key position where options changed.

## What "eligible for public distribution" requires, and why nothing is

Every original needs, for its exact content: mathematical, answer-key, worked-solution, distractor, wording, syllabus, originality and educational-suitability approvals from a registered human reviewer; the owner's rights declaration; and the owner's publication approval. A third-party question also needs a verified grant. Today:
- no reviewer is registered;
- no decision is recorded;
- no grant exists.

So 0 versions are eligible, and the Release build bundles none (`R3_VALIDATION.md`).
