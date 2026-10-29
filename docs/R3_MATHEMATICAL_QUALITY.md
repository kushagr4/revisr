# R3 mathematical quality

28 October 2026. A content-based review of every original Revisr question, the defects it found, the corrections made, and the new demanding candidates. Per-question findings stay in `revisr-content-private/review/r3-quality/`; this page gives aggregates only.

**Every check here is AI-assisted.** No person has reviewed any question, and the decisions that count are listed in `R3_HUMAN_REVIEW_WORKFLOW.md`.

## Method

The latest version of each of the 92 original questions was given to one of three independent AI reviewers:
- Paper 1 web-derived and supplement questions (34);
- Paper 1 strand-gap questions (16);
- Paper 2 (42).

Each reviewer worked in this order:
1. Solved each question from a sheet without keys, checking with exact arithmetic or `sympy` where useful.
2. Then opened the key, solution and metadata.
3. Rated 14 criteria: syllabus relevance, rigour, wording, assumptions, reasoning depth, solution correctness, unique key, distractors, misconceptions, redundant computation, notation, ambiguity, similarity and time. For Paper 2 it also rated whether the question is authentic Paper 2 reasoning or symbol-manipulation drill.
4. Gave an independent difficulty estimate (1 routine, 3 typical TMUA, 5 among the hardest), deliberately conservative.
5. Assigned a tier:
   - **diagnostic core:** good evidence of TMUA readiness;
   - **practice:** sound, but weak diagnostic evidence;
   - **foundation only:** correct but below TMUA level;
   - **rework:** a defect worth a new version;
   - **retire.**

Defects needed a demonstration (a counterexample or computation) before they could be called major.

## Results

| | Paper 1 (50) | Paper 2 (42) |
|---|---|---|
| Blind answer agrees with the stored key | 50 | 42 |
| A second defensible option found | 0 | 0 |
| Diagnostic core / practice / foundation only / rework | 9 / 23 / 17 / 1 | 24 / 15 / 3 / 0 |
| Reasoning: recall, one-step, two-step, multi-step, non-routine | 6, 10, 21, 13, 0 | 3, 6, 15, 17, 1 |
| Stored (author) levels | 15 × L2, 26 × L3, 9 × L4 | 8 × L2, 21 × L3, 12 × L4, 1 × L5 |
| Independent AI estimate | 17 × L1, 24 × L2, 9 × L3 | 3 × L1, 18 × L2, 18 × L3, 3 × L4 |
| AI estimate below the stored level | 44 | 24 (all 10 R2 drafts agree) |
| Minutes: stored → AI estimate (total) | 183 → 95 | 170 → 118 |
| Defects (all minor) | 42 in 28 questions | 11 in 11 questions |
| Paper 2 style: authentic / acceptable / logic drill | — | 30 / 7 / 5 |


## The most important weaknesses

1. **Paper 1 has no genuinely demanding original.** Judged on content, the hardest Paper 1 original is level 3, and none reaches 4. The nine stored at level 4 are typical TMUA or easier. R2 reported that selector v3 gives Paper 1 diagnostics more level-4 questions; for originals, that rested on these inflated labels. The demanding share in Paper 1 diagnostics therefore really comes from the official study copies, whose levels are also estimates.
2. **The web-derived Paper 1 set is below TMUA level.** 15 of its 19 latest questions are foundation only: one or two steps, about a minute each. Several distractors match no real mistake.
3. **Paper 2 has a low ceiling and some drill.**
   - No question reaches level 5 on content. The one stored at 5 is a 4, and only three are 4 in all.
   - Five logic questions can be answered by manipulating P and Q without any mathematics. One fact (a "for all" conditional fails exactly when P is true and Q false) carries six questions.
   - Three of the four errors-in-proofs questions share one format.
   - No question asks for a missing assumption, a circular argument, or a choice between purported proofs.
4. **Some questions can be keyed without the intended reasoning.** For example, assuming the obvious function satisfies a functional equation, or testing two easy solutions. One Paper 1 question gave the key even to a student who missed a root.
5. **Stored difficulty and time are inflated.** For 68 of the 92 questions the independent estimate is lower, and never higher. Stored minutes total 353 against an estimated 213. The app labels levels as estimates, but it still presents routine questions as hard.
6. **Answer-key position is predictable.**
   - In the web-derived Paper 1 set, the key is never the last option.
   - It is B or C in 24 of 34 questions.
   - Among numeric options it is never the smallest or the largest.

   Across all 92 latest versions, the key is the first option 7 times and the last 6 times.
7. **Titles can give the method away.** In practice mode the app showed a question's title before the student answered, and a few titles name the method or the trap.

## What R3 changed

**Stored difficulties of existing questions were not lowered.** R1's rule is that no existing label changes without a person's review, and R3 keeps it. The independent estimates are recorded in the private register beside the author estimate. A reviewer's own rating replaces the author estimate in a public build once it is recorded. Corrected versions and new drafts follow R2's rule: they store the lower of the author and AI estimates, and their provenance names both.

**Titles:** practice mode now shows the strand, not the title, until the question has been answered. That fixes every case without new versions. The worst titles were also neutralised in corrected versions.

## Corrections: 17 new versions

Every defect worth fixing became a new version in `bank/corrections-r3.json`. The old versions are byte-for-byte unchanged, and each change is recorded with its reason and both content hashes in `review/corrections.json`. R1's five earlier corrections were recorded there too.

| Kind of change | Versions | What was wrong, in general terms |
|---|---:|---|
| The question itself changed, with a different key | 3 | a wrong method still reached the key; all five distractors were equivalent, so the key was the odd one out; two easy cases eliminated every distractor without the intended argument |
| The question changed, with the same key | 6 | an unstated vertex order made a second option correct; a model valid only on part of its stated domain; Unicode exponents inside formulas; an ambiguous quantifier scope; a distractor that matched no misconception; data that let a guessed function reach the key |
| Worked solution (two also got a neutral title) | 6 | methods outside the specification (chain rule, double-angle identity, one-sided limits); distractors not explained; a loose description of a modulus graph |
| Title only | 2 | the title named the trap or revealed the answer |

Eight titles changed in all: two alone, one with its solution, and five alongside other fixes because they named the method, the trap or the answer. None of the 17 changes reduced a question to arithmetic, and none lengthened a question to make it harder.

**Difficulty.** Each corrected version stores the lower of its author estimate and the R3 estimate. Those estimates were made on the old versions, and two of the redesigned Paper 2 questions are probably harder now, so they need a reviewer's rating.

**Queue.** Each corrected version takes its predecessor's place, keeping its tier, and is marked "corrected". Decisions never carry over.


## New candidates: 12 demanding drafts

The weakest areas were Paper 1's upper end and Paper 2 reasoning tied to real mathematics, so R3 added a small set aimed at those rather than many routine questions. All 12 are in `bank/r3-demanding.json`, written from the public TMUA specification without consulting any past paper, mock or published solution.

| Paper | Topics | Options | What makes them demanding |
|---|---|---|---|
| 1 (8) | algebra, equations and inequalities, coordinate geometry, sequences and series, trigonometry, exponentials and logarithms, functions and graphs, integration (the topics whose originals were easiest) | 5–8 | structural insight (a hidden root, a locus on a circle), parameter conditions where boundary cases interact, counting solutions of a transformed equation, signed area with a parameter. Arithmetic is light and the difficulty is in reasoning |
| 2 (4) | number, algebra, proof, equations and inequalities | 7–8 | necessary-and-sufficient conditions on integers, locating the faulty step in a proof whose suspicious step is in fact valid, a proof that misses a parity case, and the order of quantifiers with real working |

**Difficulty, honestly.** The author put ten at level 4 and two at 3. An independent blind solver put two at 4, nine at 3 and one at 2. Each draft stores the lower value, so **two Paper 1 drafts are level 4 on both estimates** and nothing is level 5. Writing a genuine level 5 that is not just longer was not achieved, and no question was labelled 5 to fill the gap.

**Known concerns,** recorded on the reviewers' key sheets:
- One draft rests on a classical fact and needs a careful originality check.
- One uses logarithms with a variable base, which may sit at the edge of the specification.
- Two have one weaker distractor.
- Four can be settled by testing a value or two. That is common in real TMUA questions, but a reviewer should judge whether it undermines what each one is meant to test.


## Verification of R3 content (AI-assisted)

| Check | Scope | Result |
|---|---|---|
| Programmatic verifier written with the corrections | 17 corrected versions | 17 verified, 0 failures. For each one it recomputes the key, confirms exactly one option is correct, checks the fix (for example, the old wrong method no longer reaches the key) and lists the changed fields |
| Programmatic verifier written with the drafts | 12 new drafts | 12 verified, 0 failures. Every distractor is shown wrong and each named slip reproduced |
| Independent blind re-solve (questions only, shuffled) | the 12 drafts and the 9 corrections that changed the question | 21 of 21 agree with the stored key, all with high confidence, each with exactly one defensible option, nothing outside the specification |
| Content validator | whole bank (385 versions) | 0 structural problems. It now also rejects duplicate question text |
| Old versions unchanged | all tracked bank files | no tracked bank file differs from R2 |

The verifiers were written by the agents that wrote the questions. The blind re-solve is the independent AI check. None of this is a human review.


## What only a person can now establish

- Whether each key and worked solution is right (the review queue starts with wave 1).
- Whether each question is original. All originals were written with AI assistance from the public specification, without consulting past papers, but no person has checked them against the papers they know.
- Difficulty as a reviewer judges it, and later as students' results show it.
