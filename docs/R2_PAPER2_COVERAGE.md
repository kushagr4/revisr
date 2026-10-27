# R2 Paper 2 original-question coverage

27 October 2026. Aggregates only; question text, keys, the per-item audit and the blind re-solve stay in `revisr-content-private` (`review/r2-paper2-audit/`, `review/r2-authoring/`, `bank/p2-coverage-r2.json`).

**Review status throughout:** every check here is AI-assisted. No original question has had human mathematical, originality or rights review, and none is approved for publication.

## Audit of the existing Paper 2 originals

All 32 Paper 2 originals (latest versions) were audited by an AI reviewer. It re-solved each one from the stem and options before reading the stored key, checked distinctiveness and solution quality, and compared stored difficulty with its own estimate.

| Measure | Result |
|---|---|
| Topics | 9 of the 16 that real Paper 2 uses: logic 15, proof 8, errors in proofs 3, and one each in coordinate geometry, counting and probability, equations and inequalities, integration, sequences and series, trigonometry |
| Topics with no original | exponentials and logarithms, algebra, differentiation, functions and graphs, geometry and measures, number, statistics |
| Reasoning skills | All 10 syllabus skills appear, 2 to 5 items each |
| Stored difficulty (author estimates) | level 2: 6, level 3: 14, level 4: 11, level 5: 1 |
| Reviewer's difficulty estimate | level 2: 8, level 3: 16, level 4: 7, level 5: 1 (six items look a level easier than stored) |
| Mathematical validity | 0 problems. All 32 keys agree with the re-solve and with a programmatic check; no item has a second defensible option. |
| Distinctiveness | 3 near-duplicate pairs (as R1 found), 1 more pair sharing a template, and 3 clusters resting on one shared fact (the largest has 6 items, all on when a conditional fails) |
| Worked solutions | 30 good, 2 with minor issues (an aside using an identity beyond need; a limit argument beyond the specification), 0 major |
| Originality review | Pending for all 32 |

**The gap:** 26 of the 32 originals (81%) are logic, proof or errors in proofs, against 47% of the official Paper 2 questions. So whenever the diagnostic needed a Paper 2 question on a content topic, only an official question could supply it.

## New targeted drafts

Ten new Paper 2 originals were drafted, only where the audit showed a gap. They are not number-swapped variants, and no past paper, mock or published solution was consulted.

| Topic (strand) | Reasoning skill | Stored level |
|---|---|---:|
| Exponentials and logarithms (exponential graphs) | Quantifier reasoning | 3 |
| Exponentials and logarithms (logarithm laws) | Error identification | 2 |
| Algebra (polynomials) | Deduction | 3 |
| Differentiation (applications) | Deduction | 3 |
| Functions and graphs (transformations) | Deduction | 3 |
| Geometry and measures (plane geometry) | Necessary and sufficient conditions | 4 |
| Trigonometry (triangle trigonometry) | Case analysis | 3 |
| Sequences and series (arithmetic series) | Conditional reasoning | 2 |
| Integration (trapezium rule) | Counterexample | 3 |
| Equations and inequalities (quadratics) | Multi-step problem solving | 3 |

**Number and statistics were not attempted.** Real Paper 2 uses each only once in 120 questions. The brief allowed them only if a genuinely good reasoning question could be written, and none was drafted.

### Mathematical checks (AI-assisted)

1. **Build and verifier:** a build script is the single source of each item's text. A separate verifier recomputes every key by enumeration or exact arithmetic, shows every distractor is wrong and checks the markup. Result: 10 of 10 verified.
2. **Blind re-solve:** an independent agent saw only the stems and options. It agreed with all 10 keys, each confirmed with exact arithmetic, and found exactly one defensible option in each. Its three remarks were checked; none needed a change (one statement names its vertex explicitly; one question is easier than it looks; one condition concerns the whole graph).
3. **Validator:** the content validator reports 356 items, 0 structural problems and 0 publicly eligible.

### Difficulty is deliberately conservative

The author rated the drafts at levels 3 to 5 (two at level 5). The blind solver rated eight of the ten lower and none at level 5. The bank stores the lower of the two estimates, and `difficultyProvenance` records both, so no generated question is rated hard on its author's word alone. Neither estimate is calibrated against students.

**Effect:** the drafts close the topic gap but not the level-5 gap. Paper 2 originals still have one question at level 5, against 36 official.

## Effect on the bank and the diagnostic

| | Before R2 | After R2 |
|---|---|---|
| Paper 2 originals | 32 questions, 9 topics | 42 questions, 14 topics |
| Paper 2 original levels (2/3/4/5) | 6 / 14 / 11 / 1 | 8 / 21 / 12 / 1 |
| Development bank | 346 versions, 341 questions | 356 versions, 351 questions |

Official questions in Paper 2. v2 is the one selection every student got; v3 is the mean (and range) over 24 students. Both are on the R2 bank and come from the Swift selector (`TMUASelectionPolicyTests.testSelectionAuditOnBundledBank`):

| Length | v2 | v3 mean (range) |
|---|---|---|
| Starter (5) | 4 | 3.0 (2–3) |
| Quick (7) | 6 | 3.8 (3–4) |
| Balanced (10) | 8 | 4.8 (4–5) |
| Comprehensive (20) | 15 | 9.2 (7–11) |

Two changes produce this:
- **Content:** the drafts let originals compete on topics they could not reach before.
- **Selection:** v3 prefers whichever source is under half of the section, where v2 preferred official questions first.

**Coverage is unchanged:** all 17 topics in every Balanced and Comprehensive diagnostic, as with v2. The balance is a soft preference: an official question still wins whenever it is the only one covering a topic. See `R2_DIFFICULTY_AND_SOURCE_DIVERSITY.md`.

## Still to do

- **Human review:** mathematical, originality and rights review of all 42 Paper 2 originals. Start with the 3 near-duplicate pairs and the 6-item shared-fact cluster, then decide whether some should become practice-only.
- **Difficulty:** real student responses are the only way to calibrate. Until then, levels stay labelled as estimates.
- **Level 5:** a demanding Paper 2 original would need human authorship or review. An AI author's "level 5" did not survive an independent estimate.
