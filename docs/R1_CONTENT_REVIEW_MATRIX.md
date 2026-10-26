# R1 content review matrix

Status on 26 October 2026: **no question has a human review decision.** Everything below is AI pre-review, recorded as such. Question text, answer keys, worked solutions, stable IDs and per-item findings stay in the private workspace (`revisr-content-private/review/`). This public summary gives aggregates only.

## Review workflow

Each item *version* moves through human gates. The private tool `tools/review_workflow.py` keeps a register (`review/register.json`), records decisions only with a named human reviewer (it rejects AI tool names), and checks that bank files never claim more than the register records (`check`). It also writes blind worksheets (questions without keys) and separate key sheets for reviewers (`worksheet`). The app's build gate reads only the bank's review and rights fields, and those may be set only from recorded human decisions.

| Status | Meaning |
|---|---|
| `awaiting_mathematical_review` | No human mathematical decision yet |
| `mathematical_correction_required` | A human (or, until one decides, the AI pre-review) found a defect. Correction means a new item version. |
| `mathematical_review_approved` | A named human re-solved it and checked the key, distractors, solution, assumptions and wording |
| `awaiting_originality_review` | Revisr originals: human similarity and originality check outstanding |
| `rights_clearance_required` | In-app use, redistribution, commercial use, answer key and solution not all cleared |
| `awaiting_pedagogical_review` | Fit to TMUA style, syllabus mapping, distractor quality and teaching value unchecked |
| `difficulty_not_calibrated` | Difficulty and time are estimates; there is no student response data or expert rating |
| `awaiting_publication_decision` | All gates passed; awaiting the publication decision |
| `approved_for_publication` | All gates passed and publication approved; the only state the public build admits |

## R1 AI pre-review of the 60-item bank

Three independent AI auditors re-solved every item from the stem and options before opening the key. Each one checked:
- every distractor, the worked solution, assumptions and domains, and wording;
- the syllabus mapping and alignment with the TMUA specification;
- difficulty and time.

A fourth analysed redundancy across the bank. Verification scripts are in the private workspace.

| Batch | Items | Keys agree | Second defensible option | Blocking | Major | Minor | No finding | AI-recommended status |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Paper 1, from Revisr Web W3.0 | 20 | 20 | 0 | 0 | 0 | 15 | 5 | 20 awaiting mathematical review |
| Paper 1 supplement | 14 | 14 | 0 | 0 | 0 | 6 | 8 | 14 awaiting mathematical review |
| Paper 2 reasoning | 26 | 26 | **2** | **2** | 1 | 10 | 13 | 23 awaiting review; **3 correction required** |
| **Total** | **60** | **60** | **2** | **2** | **1** | **31** | **26** | 57 awaiting review; 3 correction required |

The earlier blind re-solve (60 of 60 keys agreed) missed both blocking defects. It checked logical form, not whether two inequalities coincide on the stated domain. Agreement on keys is not mathematical approval.

### Defect classes found (details in the private register)

| Class | Count | Example (described, not quoted) | Action |
|---|---:|---|---|
| A distractor logically equivalent to the key on the stated domain | 2 (Paper 2 negation items) | "≤" and "<" are interchangeable because equality never occurs in the domain | R1 corrected v2 drafts written (pending human review) |
| Solution relies on content outside the specification | 1 | A double-angle identity, which is not in the specification's trigonometry section | v2 draft solves the equations directly |
| A common slip produces the key | 1 (Paper 1) | Substituting the wrong root in the Factor Theorem gives the same answer | v2 draft changes the polynomial |
| Distractor pair eliminable together | 1 | Two options are logically equivalent wrong answers | v2 draft replaces one |
| Weak or throwaway distractors | about 12 | An option no plausible error produces | Proposed fixes recorded, for human decision |
| Unstated assumptions or misleading titles | about 6 | Vertex labelling order; a title that reveals the method | Proposed wording recorded |
| Solution gaps | about 6 | A step asserted without justification | Proposed wording recorded |
| Mapping suggestions | 2 | One item better fits "mensuration"; one skill tag should be empty | For human decision |

Specification checks resolved during R1: the modulus function is in the specification (MM8.1, graphs of common functions), so the two items that use it are in scope. Double-angle identities are not (MM4 lists only tan θ = sin θ / cos θ and sin²θ + cos²θ = 1).

### Bank-level patterns

| Pattern | Finding | Consequence |
|---|---|---|
| **Answer-key position** | The key is never the last option in any of the 60 items, and is the first option only 4 times. In all 28 numeric Paper 1 option lists the key is never the smallest or largest value. In the 13 Paper 2 "I/II/III" items, "none" and "all three" are never correct, and 9 have exactly two true statements. | A test-wise student can beat chance: avoiding first and last options gives about 26% against 18%, and always answering the "two statements" option gives 31% against 12.5% on those items. Shuffling cannot fix the numeric and I/II/III patterns, so new versions must vary key positions. New R1 candidates were authored with balanced keys. |
| **Difficulty** | The 20 web items are routine one- or two-step exercises (AI estimate mostly level 1–2 against stored 2–3), below real TMUA Paper 1. Stored times total 74 minutes against an estimated 36. | Treat that set as foundation practice, not a mock paper. Recalibrate after human review and, ideally, student data. |
| **Variety** | 51 distinct methods across 60 items. 26 of the 38 represented strands show only one method. 3 Paper 2 pairs are near-duplicates (same logical template). 6 Paper 2 items rest on the same fact about when a conditional fails. | Expansion and long plans cycle through few methods. The near-duplicate pairs should not both appear in one diagnostic. |
| **Paper 2 scope** | Logic 15, proof 8, errors 3. No item's main load is Section 1 knowledge. About 9 of 26 use number-theory or parity contexts. | Real Paper 2 papers include Section 1-heavy reasoning items. R1 drafted 6 candidates. |
| **Format** | Paper 1 items have 4–7 options; Paper 2 items have 5, 6 or 8. No symbolic logic notation; every domain is stated. | Fine for TMUA style |

## Syllabus coverage and new candidates

### Missing strands: specification check

The previous report listed 8 strands with no question. Checked against the UAT-UK TMUA Content Specification for October 2026 and January 2027, every one is assessed content; none is optional or mis-mapped:

| Strand | Specification | Verdict |
|---|---|---|
| Function properties | MM1.7 (many-to-one mappings; properties of common functions including √x) | Assessed (Section 1) |
| Exponential graphs | MM5.1 (y = aˣ and its graph) | Assessed |
| Derivatives | MM6.1–6.2 (gradient, rate of change, second derivatives, notation) | Assessed |
| Differential equations | MM7.6 (solving dy/dx = f(x)) | Assessed |
| Number calculation | M2 (four operations, place value, priority of operations, bounds) | Assessed |
| Units | M1 (standard and compound units, conversions in algebraic contexts) | Assessed |
| Mensuration | M5.14–5.16 (areas, volumes, arc and sector, similarity of lengths, areas and volumes) | Assessed |
| Vectors | M5 (vector addition, scalar multiples, column vectors, geometric arguments) | Assessed |

### R1 draft additions (private, pending human review)

The additions were authored only after the audit had identified what was needed. All were composed from the specification alone, with no past or mock paper consulted. Each is checked by a verification script that confirms the keyed option is the only correct one and recomputes the error behind each distractor. Each records AI-assisted provenance dated 26 October 2026, with review states `ai_derivation_only`, originality `pending`, rights `pending_review` and publication `not_approved`.

| Set | Items | Purpose |
|---|---:|---|
| Corrected versions | 5 | New versions (v2) of the 2 blocking Paper 2 items, the out-of-spec solution, the Factor Theorem slip and the duplicate distractor. Originals are unchanged in history, and saved diagnostics keep their pinned versions. |
| Paper 1 strand gaps | 16 | Two per empty strand, each pair using different methods. Difficulty: 1 at level 2, 10 at level 3, 5 at level 4. |
| Paper 2, Section 1 load | 6 | Reasoning items whose main load is Section 1 knowledge (trigonometric equations, inequality conditions, sequences, integrals, circle–line tangency, counting) |

Keys across the 22 new items: A 3, B 3, C 4, D 3, E 4, F 2, G 2, H 1. The key is the first option in 3 items and the last option in 4. "None of them" and "I, II and III" are each correct once. Independent blind verification of the 27 new and corrected items: a separate agent, solving with keys hidden, agreed with the key on **27 of 27** and found no second defensible option and no solution error. It left two notes for the human reviewer: a solution sentence that says "both quantifiers" where only one changes, and one stem that puts a Unicode superscript inside TeX markup. This is AI verification, not human review.

### Coverage now

| Measure | Before R1 | After R1 drafts |
|---|---:|---:|
| Distinct questions (latest versions) | 60 (34 P1, 26 P2) | 82 (50 P1, 32 P2) |
| Strands with at least one question | 38 / 46 | **46 / 46** |
| Strands with only one question | 26 of 38 | 21 of 46 |
| Paper 2 items with a Section 1 main load | 0 | 6 |

Diagnostic coverage measured on the 82-question development bank (`testBundledBankCoverageByLength`):

| Length | Topics sampled (before → after) | Strands sampled (before → after) |
|---|---|---|
| Starter (10) | 8 → 10 of 17 | 10 → 10 of 46 |
| Quick (15) | 11 → 13 of 17 | 15 → 15 of 46 |
| Balanced (20) | 13 → 13 of 17 | 19 → 20 of 46 |
| Comprehensive (40) | 17 → 17 of 17 | 29 → 31 of 46 |

**What this does not change.** Every one of the 82 questions still needs human mathematical, originality and pedagogical review, and none is publicly eligible. Most strands have one or two questions. A bank that supports long plans and repeated expansion needs about 150–200 reviewed questions, with several per strand and varied key positions.
