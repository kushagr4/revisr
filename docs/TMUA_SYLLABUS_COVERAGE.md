# TMUA syllabus coverage

## Source

The taxonomy (`revisr/Resources/TMUASyllabus.v1.json`, version `tmua-syllabus-v1`) was mapped on 26 October 2026 from the UAT-UK *TMUA Content Specification* for assessment in October 2026 and January 2027 ([PDF](https://uat-wp.s3.eu-west-2.amazonaws.com/wp-content/uploads/2024/05/03165619/TMUA_Content_Specification.pdf)). The specification gives two 75-minute papers of 20 multiple-choice questions, no calculator, equal weighting and no penalty for wrong answers. Paper 1 requires Section 1; Paper 2 requires Sections 1 and 2. Section 2 logic is examined in words: candidates are not expected to use symbolic logic notation or truth tables, so Revisr's Paper 2 items avoid symbols such as ⇒ and ∀.

Revisr's grouping of specification references into topics and strands is an internal organisation choice, not an official blueprint.

## Hierarchy

Broad topic → specific strand (with specification references) → optional reasoning skill → paper applicability. Topics in Section 1 apply to both papers; Logic of arguments, Mathematical proof and Errors in proofs apply to Paper 2 only.

| Topic | Papers | Strands (spec refs) |
|---|---|---|
| Algebra | 1, 2 | Indices and surds (MM1.1–1.2, M2.11, M4.2); Polynomials and Factor Theorem (MM1.6); Manipulation and identities (M4.1–M4.7) |
| Equations and inequalities | 1, 2 | Quadratics (MM1.3, M4.11, M4.15); Simultaneous equations (MM1.4, M4.13–14); Inequalities (MM1.5, M4.16) |
| Functions and graphs | 1, 2 | Function properties (MM1.7); Transformations (MM8.2–8.4); Graphs and roots (MM8.1, MM8.6–8.7, M4.12) |
| Coordinate geometry | 1, 2 | Straight lines (MM3.1–3.2, M4.9–4.10); Circles (MM3.3) |
| Sequences and series | 1, 2 | Sequences (MM2.1, M4.17); Arithmetic series (MM2.2); Geometric series (MM2.3); Binomial expansion (MM2.4) |
| Trigonometry | 1, 2 | Triangle trigonometry (MM4.1, M5.17); Radians (MM4.2, M5.16); Graphs and identities (MM4.3–4.5); Equations (MM4.6) |
| Exponentials and logarithms | 1, 2 | Exponential graphs (MM5.1); Log laws (MM5.2); Exponential equations (MM5.3) |
| Differentiation | 1, 2 | Derivatives (MM6.1–6.2); Applications (MM6.3, MM8.5) |
| Integration | 1, 2 | Definite integrals and area (MM7.1–7.4); Trapezium rule (MM7.5); Differential equations (MM7.6) |
| Number | 1, 2 | Number properties (M2.5); Exact calculation (M2.1–M2.14 subset) |
| Ratio, proportion and units | 1, 2 | Ratio and proportion (M3); Units (M1) |
| Geometry and measures | 1, 2 | Plane geometry and circle theorems (M5.2–5.9, MM3.3); Mensuration (M5.14–5.16); Vectors (M5.19) |
| Statistics | 1, 2 | Statistics (M6.1–6.4) |
| Counting and probability | 1, 2 | Counting (M2.6, MM2.4); Probability (M7) |
| Logic of arguments | 2 | Implication (Arg1); Necessary and sufficient (Arg2); Quantifiers (Arg3); Negation (Arg4) |
| Mathematical proof | 2 | Proof methods (Prf1); Deduction (Prf2, Prf5); Conjecture (Prf3); Proof ordering (Prf4) |
| Errors in proofs | 2 | Error identification (Err1–Err2) |

Reasoning skills: conditional reasoning, necessary/sufficient, quantifiers, negation, counterexample, proof structure, error identification, deduction, case analysis, multi-step problem solving.

## Backward compatibility

`legacyTopicKeyMap` maps Revisr Web's broad `revisr-core-v1` keys (algebra, sequences, geometry, functions, combinatorics, probability, number-theory, inequalities) onto these topics. Imported web items keep their original keys in provenance. The legacy iOS catalogue's free-text `primaryTopic` values and earlier diagnostic records are not relabelled. New diagnostic items store `topicKey`, `strandKey`, `skillKey` and the taxonomy version.

## Development bank coverage (26 October 2026, after R1)

The R1 drafts add 16 Paper 1 items for the 8 previously empty strands and 6 Paper 2 items whose main load is Section 1 knowledge. They also add 5 corrected versions, which do not change the counts. Counts are latest versions per stable ID: 82 questions, 50 Paper 1 and 32 Paper 2. Paper 2 items carry their Section 1 topic, so a Section 1 topic can have Paper 2 items.

| Topic | Papers | P1 items | P2 items | Strands with only one item |
|---|---|---:|---:|---|
| Algebra | 1, 2 | 4 | 0 | polynomials, algebraic-manipulation |
| Equations and inequalities | 1, 2 | 3 | 1 | quadratics, simultaneous-equations |
| Functions and graphs | 1, 2 | 4 | 0 | graph-transformations, graphs-and-roots |
| Coordinate geometry | 1, 2 | 2 | 1 | straight-lines |
| Sequences and series | 1, 2 | 4 | 1 | arithmetic-series, geometric-series, binomial-expansion |
| Trigonometry | 1, 2 | 4 | 1 | triangle-trigonometry, radians-arcs, trig-functions-identities |
| Exponentials and logarithms | 1, 2 | 4 | 0 | logarithm-laws, exponential-equations |
| Differentiation | 1, 2 | 4 | 0 | — |
| Integration | 1, 2 | 4 | 1 | trapezium-rule |
| Number | 1, 2 | 3 | 0 | number-properties |
| Ratio, proportion and units | 1, 2 | 3 | 0 | ratio-proportion |
| Geometry and measures | 1, 2 | 6 | 0 | — |
| Statistics | 1, 2 | 1 | 0 | statistics |
| Counting and probability | 1, 2 | 4 | 1 | — |
| Logic of arguments | 2 | 0 | 15 | — |
| Mathematical proof | 2 | 0 | 8 | conjecture, proof-ordering |
| Errors in proofs | 2 | 0 | 3 | — |

All 17 topics and **46 of 46** strands now have at least one draft question. Before R1, 38 of 46 had one; the 8 previously empty strands are all assessed content in the official specification (see `R1_CONTENT_REVIEW_MATRIX.md`). 21 strands still have only one question. None of these items is publicly eligible, and none has human review.

## Coverage by diagnostic length

The selector maximises new topics first, then new strands and skills (see `DIAGNOSTIC_SELECTION_AND_EXPANSION.md`). Measured on the 82-question development bank by `testBundledBankCoverageByLength` (26 October 2026, after R1; the earlier 60-item figures are in brackets):

| Length | Topics sampled | Strands sampled | Paper 2 reasoning topics | Difficulty mix (level: count) | Author-estimated minutes |
|---|---:|---:|---:|---|---:|
| Starter (10) | 10 / 17 (8) | 10 / 46 (10) | 3 / 3 | 2: 5, 3: 5 | 34 |
| Quick (15) | 13 / 17 (11) | 15 / 46 (15) | 3 / 3 | 2: 5, 3: 8, 4: 2 | 56 |
| Balanced (20) | 13 / 17 (13) | 20 / 46 (19) | 3 / 3 | 2: 8, 3: 7, 4: 4, 5: 1 | 76 |
| Comprehensive (40) | 17 / 17 (17) | 31 / 46 (29) | 3 / 3 | 2: 14, 3: 16, 4: 9, 5: 1 | 153 |

Even the comprehensive diagnostic has only one to a few questions per topic. Topics with few assessed questions are reported as "insufficient evidence", and unsampled topics as "not assessed".
