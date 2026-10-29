# R4 unified question catalogue

29 October 2026. These are the true size and shape of the library, measured from the catalogue itself (`TMUACatalogueTests.testPrintReconciliationCounts`). The counts are of unique questions, not files or versions.

## Size

| | Development (Debug) build | Public (Release) build today |
|---|---:|---:|
| Unique questions in the catalogue | **2,851** | **1,609** |
| Original Revisr questions | 104 (126 versions) | 0 (none approved) |
| Drive-collection questions | 2,747 | 1,609 |
| Documents in the library | 146: the 136 bundled library documents (133 with questions; the other 3 are reference guides) and 10 supplement papers | 93, all from providers whose own pages offer them |
| Merged reprints / linked variants | 7 / 22 | 1 / 0 |

## How each question can be used

| Answer mode | Debug | Release | What it means |
|---|---:|---:|---|
| Marked by Revisr (automatic) | **363** | **0** | Revisr holds a key for this exact version: 104 originals and 259 official TMUA questions |
| Self-marked with the publisher's solution | 1,895 | 0 | Opened at its page in a bundled paper, with the solution in the app |
| Record your own result | 439 | 0 | Opened at its page, but this build has no solution for it |
| On the publisher's website | 154 | 1,609 | Not reproduced; the publisher's page offers it |

| Presentation | Debug | Release |
|---|---:|---:|
| Native (Revisr text, or a verified crop of the official paper) | 363 | 0 |
| Document (the bundled paper at the question's page) | 2,334 | 0 |
| External (publisher link) | 154 | 1,609 |

**Keys and solutions.**
- **Answer keys Revisr holds:** 363. These are the author keys of the originals, AI-checked by blind re-solving in R1–R3, and the 259 official keys, read from UCLES's worked solutions by two independent AI readings or from the official 2022 key. **None has been checked by a person.**
- **Publishers' answers in the collection:** the publishers' solutions also state the answers to most Drive multiple-choice questions, and the 125 supplement keys are recorded privately. These are not imported as Revisr keys, because they belong to questions Revisr cannot present natively.
- **Questions with solutions this build can open:** 2,412 (Debug). 1,899 catalogue questions have a question-level solution page: 1,747 indexed questions less two reprints, plus all 154 supplement questions.
- **Distinguishing key types.** Each native question carries its key provenance, such as "UAT-UK official answer key" or "official UCLES worked solution, read twice independently". The catalogue shows it as the review status. No question is labelled human-reviewed.

## Providers (Debug)

| Provider | Questions | | Provider | Questions |
|---|---:|---|---|---:|
| UKMT (SMC, IMC, BMO, Kangaroo, Maclaurin) | 778 | | JZMaths | 200 |
| UAT-UK (official TMUA, specimen and practice papers) | 359 | | Original Revisr | 104 |
| Tyler Tutoring (topic banks and TMUA mocks A–D) | 315 | | CSAT samples | 80 |
| University of Oxford (MAT) | 309 | | TMUA.fyi | 80 |
| Unattributed independent mocks (Beyond Horizon and seven others) | 296 | | TMUA Euclid | 67 |
| OCR (STEP) | 163 | | MioMath, Yotta | 40 each |
| | | | TMUA.co.uk | 20 |

## Papers, topics and difficulty (Debug)

- **Paper fit:**
  - Paper 1: 1,031
  - Paper 2: 903
  - Both: 544
  - Unclassified: 373, mostly competitions and long-form questions
- **Syllabus topics:** all 17 TMUA topics have questions:
  - geometry and measures: 490
  - equations and inequalities: 295
  - number: 286
  - functions and graphs: 195
  - counting and probability: 194
  - trigonometry: 149
  - logic: 138
  - sequences and series: 133
  - exponentials and logarithms: 89
  - algebra: 87
  - integration: 83
  - coordinate geometry: 79
  - differentiation: 57
  - ratio and proportion: 46
  - proof: 31
  - statistics: 22
  - errors in proofs: 15
  - Beyond the specification (mixed problem solving, games and strategy): 462. These are filterable, never assigned to a syllabus topic.
- **Topic classification:** the topics of the 363 native questions come from AI-assisted classification against the syllabus. The rest are mapped from the original library index's topics (`catalogue/topic-map.json`).
- **Estimated difficulty:**
  - L1: 194
  - L2: 422
  - L3: 1,164
  - L4: 763
  - L5: 308
- **Difficulty provenance:**
  - most come from the original library index;
  - the supplement's are AI estimates made while indexing;
  - the originals' are the author's estimates, or the lower of the author's and a blind estimate.
- **Calibration:** none is calibrated against student responses, and the app labels every level "estimated". The 308 level-5 questions are mostly MAT, STEP, BMO and competition questions. They are not TMUA-calibrated level 5, and no original is labelled level 5.
- **Format:**
  - multiple choice: 2,286
  - long-form or proof: 405
  - numeric: 80
  - short or long written: 80

## What is held privately versus bundled

- **Debug builds** bundle the owner's papers and solutions as personal study copies, the assembled bank (originals and study copies), and the metadata files.
- **Release builds** strip every restricted PDF and video (`strip-restricted`). They bundle only approved questions (none today) and the metadata files: the library index, providers and the reconciliation.
- **Never bundled, and never in public Git:** Drive file IDs, question text, private keys and reviewer material. These stay in `revisr-content-private`.

## The Questions tab

One segmented control (`questions.library`) switches between four views of the same catalogue. There is no further nesting.

| View | Shows | Opens |
|---|---|---|
| **Practice** | Every question this build can open. Filters: paper, topic (including "Beyond the TMUA specification"), strand (known only for questions Revisr marks, as before R4), marking, source, estimated difficulty, status. Revisr-marked questions come first. Unattempted originals hide their titles, which can name the method | A marked question opens in Revisr's practice screen. Any other question opens its question screen: the paper at the question's page (pinch to zoom, scroll through the paper), its solution page where the build has one, previous and next question within the paper, record a result, flag for review |
| **Papers** | The paper library from R1–R3, grouped by type and provider, with question counts, solutions and access. Each question row now opens its catalogue screen. A reprint says "Same question as …" and opens the original | The paper; its solutions; the publisher's site; a whole-paper result |
| **Sources** | Original Revisr questions, then each provider by type, with its paper and question counts and how this build offers them. Other preparation sites are credited links | The provider's credit, terms, link and papers |
| **Saved** | Flagged questions; questions incorrect or partly right last time; the 50 most recent attempts and recorded results | The question |

**Access modes are explicit on every row:**
- "Marked by Revisr" against "Self-marked";
- "Opens on UAT-UK's website", "Personal study copy" and "solutions in your library";
- a question screen that tells the student how it is marked, and that results they record are never used as evidence of topic mastery.

**Nothing is presented as more than it is.** A paper on a publisher's site is never shown as an offline question. A document question never gets a key it does not have.

**Typography is unchanged from R2.** The question screens use `.headline`, `.subheadline` and `.footnote` text styles, and the papers are shown as printed, in PDFKit. R2's typography and Dynamic Type tests pass unchanged.

**Topics.** The Topics tab now adds, for each topic, how many more questions the library holds to self-mark.
