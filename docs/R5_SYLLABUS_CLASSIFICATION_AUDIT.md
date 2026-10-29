# R5 · Syllabus classification audit

R4 reported 462 catalogue questions with no syllabus topic and 373 with no Paper 1/Paper 2 fit. R5 found that the metadata could not tell these situations apart:

- a question outside the TMUA specification;
- a question nobody had classified;
- a paper fit that is a fact versus one that is an estimate.

R5 records the provenance of every topic and paper fit. It fixes one source of wrong paper fits, adds provisional topics only where two independent AI classifications agreed, and leaves the rest honestly unknown.

All figures are for the internal (Debug) catalogue of 2,851 questions unless stated otherwise. They are aggregates; no question text appears here.

## What the metadata now distinguishes

Each catalogue entry carries two provenance fields, `topicBasis` and `paperFitBasis` (`TMUACatalogueEntry` in `TMUAQuestionCatalogue.swift`).

| `topicBasis` | Meaning | Before R5 | After R5 |
|---|---|---:|---:|
| `revisrRecord` | The question's own Revisr record: the author's taxonomy for originals, an AI-assisted one for official questions | 363 | 363 |
| `libraryIndex` | The original library index's topic, mapped to the syllabus | 2,026 | 2,026 |
| `provisionalDraft` | Two independent AI classifications of the page agreed (R5); **not reviewed by a person** | — | 184 |
| `outsideSpecification` | The index places it outside the specification ("Games, invariants & strategy") | 462 shown as "Beyond the TMUA specification" | 20 |
| `unclassified` | No syllabus topic is known | (included above) | 258 |

| `paperFitBasis` | Meaning | After R5 |
|---|---|---:|
| `appearsInPaper` | The question is in that paper: its Revisr record, the paper's own label, or the question's part of a file holding both papers | 1,318 (737 Paper 1, 581 Paper 2) |
| `libraryEstimate` | The library index's judgement of the paper a question suits; shown as "(estimated)" | 1,160 (282 Paper 1, 372 Paper 2, 506 both) |
| `unknown` | No paper fit | 373 |

"Confirmed" is deliberately not used:

- No topic in the catalogue has been reviewed by a person.
- `revisrRecord` and `libraryIndex` topics are the best existing labels.
- `provisionalDraft` topics are labelled provisional wherever they are shown.

## Changes

### 1. "Beyond the specification" split from "not yet classified"

The index topic "Mixed / problem solving" (442 questions) was treated as outside the specification. It is not: 30 official TMUA "Mixed" questions have syllabus topics in their Revisr records, and 238 of the 442 come from TMUA-format mocks.

- The private topic map (schema 2) now lists "Games, invariants & strategy" as **outside** and "Mixed / problem solving" as **unclassified**.
- The builder rejects any index topic that is both mapped and unmapped.
- The Practice topic filter offers both "Beyond the TMUA specification" and "Topic not yet classified".

### 2. Paper fit for combined Paper 1 + Paper 2 files

Tyler Tutoring's mocks A–D are single files holding both papers, and their override labels them "Set A" to "Set D". The source-label rule therefore never fired, and the index estimate was used. That estimate disagreed with the question's own paper for 78 of 159 questions:

- 37 Paper 2 questions were shown as Paper 1;
- 3 Paper 1 questions were shown as Paper 2;
- 38 questions were shown as "both".

For TMUA-format sources the question's own part (`AdmissionsManifest.Question.paper`) now decides first, then the paper's label. The part agrees with the label wherever both name a paper.

Paper fit totals changed as follows:

| Paper fit | Before R5 | After R5 |
|---|---:|---:|
| Paper 1 | 1,031 | 1,019 |
| Paper 2 | 903 | 953 |
| Both | 544 | 506 |
| Unclassified | 373 | 373 |

The same rule also lists each paper's questions in order inside a combined file (R5 determinism fix 8).

### 3. Provisional topics for TMUA-format "Mixed" questions

**Scope.** Only the 238 "Mixed" questions from TMUA-format mocks were classified, all in bundled papers: 167 self-marked and 71 record-a-result. They are TMUA questions, can be practised and, once classified, can be used by the planner.

**Not attempted:**

- the 117 competition and 87 other admissions-test "Mixed" questions (UKMT, MAT, STEP, CSAT, BMO), so that they are not forced into TMUA topics;
- the 20 Games questions, which are outside the specification.

**Method.**

1. Each question's starting page was rendered to an image in a scratch folder; PDF text was too thin for mathematics.
2. Two independent classification passes each read every page against the 17 topics and their strands in `TMUASyllabus.v1.json`. Pass A classified by the mathematics used, pass B by the topic an examiner would list.
3. A topic was accepted only when both passes named the same topic, both found the question's number on the page, and both rated confidence at least medium.
4. Two accepted drafts were spot-checked against their pages by hand, and both were correct.

| Outcome | Questions |
|---|---:|
| Accepted (both passes agreed, confidence ≥ medium) | 184 (75 high, 109 medium) |
| Agreed, but low confidence or "unknown" | 41 |
| Disagreed | 9 |
| Question number not found on the page | 3 |
| One pass missing | 1 |

Accepted drafts by topic:

| Topic | Drafts | Topic | Drafts | Topic | Drafts |
|---|---:|---|---:|---|---:|
| Integration | 29 | Logic | 13 | Exponentials & logarithms | 4 |
| Sequences & series | 24 | Counting & probability | 12 | Geometry & measures | 4 |
| Number | 21 | Differentiation | 9 | Proof | 4 |
| Equations & inequalities | 16 | Coordinate geometry | 8 | Errors in proofs | 3 |
| Algebra | 15 | Trigonometry | 8 | Statistics | 2 |
| Functions & graphs | 7 | Ratio & proportion | 5 | | |

**Where the data lives.**

- The private workspace keeps both passes' votes and short rationales (`catalogue/topic-drafts-2026-10-29.json`).
- `tools/build_reconciliation.py` publishes only the question ID, topic, strand and confidence of accepted drafts into `TMUACatalogueReconciliation.json`, with a basis sentence that ends "Not reviewed by a person."
- The builder rejects a draft that names an unknown topic or overrides a mapped topic. The app also ignores a draft whose topic its syllabus lacks.

**How drafts are shown.** In the app a drafted topic reads "Integration (provisional)". The question screen adds: "Provisional topic: two independent AI classifications of the page agreed. Not reviewed by a person."

### 4. Planner gates

- **Paper fit.** Worksheets no longer require a paper fit, since they are grouped by topic and the planner never matches papers. This admits 179 self-marked multiple-choice questions, chiefly from Tyler's topic bank, Euclid Ascent and James Chen.
- **Syllabus topic.** A syllabus topic is still required. A question outside the specification or not yet classified is never set as topic practice; `TMUACatalogueAuditTests` asserts this for every scheduled worksheet question.
- **Worksheet pool.** It grew from 1,098 to 1,407: 179 from the paper-fit change and 130 from self-marked multiple-choice questions with an accepted draft.

## What remains unknown

258 questions have no syllabus topic:

| Group | Questions | Notes |
|---|---:|---|
| Competitions | 117 | IMC 59, SMC 41, Senior Kangaroo 9, BMO 7, and others |
| Other admissions tests | 87 | STEP 63, MAT 17, CSAT 7 |
| TMUA-format mocks | 54 | Where the classifications did not agree confidently |

By how they can be practised:

- 214 self-marked;
- 44 record-a-result.

20 questions are outside the specification. 373 have no paper fit: STEP 163, Tyler topic bank 156, Euclid Ascent 27, James Chen 20 and the IMC 2022 supplement 7. For STEP a TMUA paper fit is not meaningful.

**Public build** (as assembled by `TMUACatalogueTests` from the same bundle judged as public): see the figures in `R5_VALIDATION.md`. It holds 1,609 linked questions, none bundled.

## Known limits

- **AI drafts.** Provisional topics are AI classifications, not reviews. They feed worksheets and filters but never diagnostic evidence.
- **Index topics.** Mapped topics remain as R4 left them. "Functional equations & recurrences" maps to functions and graphs, and competition "Number theory" and "Geometry" map to their nearest TMUA topics; both are noted in the private topic map.
- **Strands.** Only questions with a Revisr record and drafts carrying a strand have one. The Strand filter says so whenever a strand is chosen.

## Tests

| Test | What it checks |
|---|---|
| `TMUAStudentExperienceTests.testTopicProvenanceSeparatesOutsideUnclassifiedAndDrafts` | A synthetic library: a mapped topic, an outside topic, a valid draft, an invalid draft (ignored) and an unclassified question; question-part paper fit in a combined file; filters keep "outside" and "not yet classified" apart; worksheets use neither. |
| `TMUAStudentExperienceTests.testBundledDraftsAreValidAndOnlyFillUnknownTopics` | Every bundled draft names a syllabus topic, is unique and only fills an unclassified index topic. |
| `TMUACatalogueTests.testTopicsMapOnlyToSyllabusTopicsAndOfficialPapersKeepTheirPaper` | Unchanged R4 invariant, still passing. |
| Private `tools/tests/test_build_reconciliation.py` | Four new tests: only agreed drafts publish, unknown strands drop, a draft must name a syllabus topic and never overrides a mapped topic, and outside and unclassified stay apart with no rationale published. 17 of 17 pass. |
