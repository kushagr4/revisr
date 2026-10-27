# R2 diagnostic selection audit (selector v2)

27 October 2026, branch `claude/revisr-r2-diagnostic-quality`. This audit describes how the diagnostic selector worked before R2 (`tmua-selector-v2`, in `revisr/Services/TMUA/TMUADiagnosticSelector.swift`), reproduces its output on the real development bank, and identifies the defects R2 fixes. The redesign is in `R2_DIFFICULTY_AND_SOURCE_DIVERSITY.md`.

## Method

- **Code read in full:** the selector, `TMUADiagnosticService` (how each round is selected, stored and expanded) and the existing selection tests.
- **Reproduced outside the app:** a Python replica of the v2 scoring was checked against the Swift selector and reproduced its picks exactly for all four lengths.
- **Bank:** the development bank at private commit `f22af8d`: 87 original versions (82 questions) and 259 official study copies.
- **Baseline kept privately:** the ordered question identities are in `revisr-content-private/reports/r2-selection/baseline-v2.json`. They are identities only, with no question text or keys, and every student received this same selection under v2.

## How v2 balances each factor

The selector is greedy. For each pick it scores every unseen candidate in the paper and takes the highest score. Weights are in points.

| Factor | How v2 handles it |
|---|---|
| Topic coverage | +1,000 for a topic not yet in the diagnostic; −120 per earlier question on the topic in this paper; −40 per earlier question on it anywhere |
| Syllabus strand | +200 for a strand not yet in the diagnostic |
| Reasoning skill | +80 for a skill not yet in the diagnostic, in either paper |
| Paper 1 versus Paper 2 | Paper 1 is selected first, then Paper 2 with Paper 1's questions as prior coverage; each paper has its fixed count (5+5, 8+7, 10+10, 20+20) |
| Difficulty | Three bands (levels 1–2, 3, 4–5) with targets of 35%, 45% and 20% of the section; +60 while a band is under target. Sections of 8 or fewer add +15 for levels 2–3. |
| Provenance and source type | +50 for an official or licensed question while those make up less than half the section and its topic has no official question yet in this paper |
| Individual source paper | Not considered |
| Previous exposure | Questions already in the diagnostic or practised are excluded |
| Question version | Only the latest eligible version of each identity is a candidate; a diagnostic stores the exact version and a full content snapshot of every question it selected |
| Stable tie-breaking | Equal scores go to the lowest FNV-1a hash of `stableId@vN`. It is the same for every student. |

A diagnostic records `selectorVersion`, its bank version and its questions, in order, with content snapshots. Relaunching restores exactly the stored questions; nothing is re-selected.

## Baseline: what every student received

Official + original questions per paper; levels are the estimated difficulty of each pick.

| Length | Paper 1 | Paper 1 levels (2/3/4) | Paper 2 | Paper 2 levels (2/3/4/5) | Official questions per paper |
|---|---|---|---|---|---|
| Starter (5+5) | 3 + 2 | 2 / 3 / 0 | 5 + 0 | 1 / 2 / 1 / 1 | P1: Specimen 2, 2018 1. P2: 2020 2, three others 1 each |
| Quick (8+7) | 4 + 4 | 3 / 4 / 1 | 7 + 0 | 3 / 2 / 1 / 1 | P1: Specimen 3, 2018 1. P2: 2020 3, 2021 2, two others 1 |
| Balanced (10+10) | 5 + 5 | 4 / 5 / 1 | 9 + 1 | 1 / 5 / 2 / 2 | P1: Specimen 4, 2018 1. P2: 2020 5, 2017 2, two others 1 |
| Comprehensive (20+20) | 13 + 7 | 7 / 9 / 4 | 15 + 5 | 6 / 8 / 3 / 3 | P1: 2018 5, Specimen 5, 2019 2, 2021 1. P2: 2020 5, 2021 4, 2017 3, three others 1 |

Topic coverage was good: 10, 15, 17 and 17 of the 17 syllabus topics, with 10, 15, 20 and 36 strands.

## Findings

1. **Every student received the same diagnostic.** Selection depended only on the bank, so the tie-break order was fixed for everyone. Students sharing notes, or a student who reset, met the same questions.
2. **No level 5 in Paper 1, because the bank has none.** The Paper 1 pool holds 49 questions at level 2, 89 at level 3 and 51 at level 4 (official and original together), and 0 at level 5; all 37 level-5 questions are Paper 2. The selector never rejected a level-5 Paper 1 question.

   The real Paper 1 problem was how few demanding questions it took:
   - the hard band (levels 4–5) targeted only 20% of a section;
   - short sections earned a bonus for levels 2–3;
   - so Paper 1 drew 0, 1, 1 and 4 level-4 questions at the four lengths, out of 51 available, and up to 35% of each section was level 2.
3. **Paper 2 was mostly official.** Two causes:
   - **Bonus order.** The official bonus applied from the first pick, so the first half of each section went to official questions.
   - **Topic gap.** After that, coverage decided. The Paper 2 originals covered 9 topics, 26 of their 32 questions in logic, proof or errors in proofs. The official Paper 2 questions cover 16 topics. Every new topic therefore came from an official question, and the Starter and Quick Paper 2 sections were entirely official.

   This was partly a content gap; see `R2_PAPER2_COVERAGE.md`.
4. **Picks clustered by paper.** No term rewarded spreading picks across papers. The hash order is well mixed overall (its runs match random shuffles), but it is fixed, so the same papers won every tie for every student. Balanced Paper 1 took four of its five official questions from Specimen Paper 1, and Paper 2 took five of nine from 2020.
5. **The skill bonus favoured Paper 1 originals.** Reasoning skills are classified for Paper 2. In Paper 1, 27 of the 50 originals carry a skill tag and none of the 139 official questions do, so the +80 skill bonus pushed Paper 1 originals ahead for a metadata reason, not a mathematical one.
6. **Coverage depended on the Paper 1 draw.** Some topics, ratio and proportion for example, have Paper 1 questions only. When a tie-break left such a topic out of Paper 1, Paper 2 could not cover it. v2's fixed draw happened to cover all 17 topics; a per-student draw would not always (measured: 16.4 of 17 on average for Balanced before the fix described in the redesign).

## What R2 keeps

- **Structure:** the 10/15/20/40 lengths and the Paper 1/Paper 2 counts.
- **Stored state:** pinned snapshots, autosave, pause and resume, submission locking, scoring and evidence confidence.
- **Expansion:** the expansion rules and exposure exclusion.
- **Existing diagnostics:** v2 itself, unchanged, for diagnostics already created under it. A test pins v2's output on fixtures, and its picks on the real bank still match this baseline exactly.
