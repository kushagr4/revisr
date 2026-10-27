# R2 difficulty and source diversity: selector v3

27 October 2026. `tmua-selector-v3` (`revisr/Services/TMUA/TMUADiagnosticSelector.swift`) is the policy for every diagnostic created from now on. It replaces v2 only for new diagnostics. The audit that motivated it is in `R2_DIAGNOSTIC_SELECTION_AUDIT.md`.

Difficulty levels below are **estimates**: the original library index's labels for official questions, and author or AI estimates for originals. None is reviewed by a person or calibrated against students. Nothing here claims official TMUA difficulty, and the app keeps labelling levels as estimated.

## Versioned, student-specific and reproducible

- **Seed.** Each diagnostic has a stable identity (`tmua-flex-diagnostic-v1-<profile UUID>`). Its seed is the FNV-1a hash of that identity joined to the policy name: `seed(assessmentID:policy:)`. Equal scores are broken by a SplitMix64 mix of the question's version key and the seed. A different student gets a different tie order, while the same student and policy always get the same one.
- **Nothing is random at runtime.** The seed is derived, not drawn. Reselecting with the same identity, policy, bank and exposure gives the same questions in the same order, whatever the order of the candidates.
- **Pinning.** As before, a diagnostic stores its ordered questions:
  - the exact version of each, with a full content snapshot (stem, options, key, source and taxonomy);
  - its paper assignment;
  - the answers;
  - `selectorVersion`.

  Relaunching restores the stored questions; nothing is reselected.
- **Policy pinning.** `TMUASelectionPolicy(recorded:)` reads `selectorVersion`. A length change before starting, and every expansion, use the diagnostic's own policy:
  - **v2 diagnostics** keep v2. Its code is unchanged and its picks on the real bank still match the pre-R2 baseline exactly.
  - **v1 diagnostics** (retired before R2) keep the v2 rules they already used.

  No existing assessment is reshuffled, and no schema change was needed.
- **No equivalence claim.** Different students' diagnostics aim at the same coverage and difficulty objectives. They are not psychometrically equivalent forms; that would need response data.

## What v3 scores

Each pick takes the highest-scoring unseen candidate. Weights are in points (`TMUADiagnosticSelector.Weight`). Coverage dominates: a new topic outweighs everything else combined.

| Objective | v3 rule | Change from v2 |
|---|---|---|
| Topic coverage | +1,000 new topic; +100 more if the other paper has no candidates on it; −200 per repeat in this paper; −40 per repeat in the diagnostic | Repeat penalty raised from 120 so difficulty and source bonuses cannot outweigh covering a new topic. The "only here" bonus stops Paper 1 from leaving a topic, such as ratio and proportion, that Paper 2 cannot cover. |
| Strand | +200 new strand | Unchanged |
| Reasoning skill | +80 new skill, **Paper 2 only** | Paper 1 skill tags exist only on originals, so they no longer bias Paper 1 towards originals |
| Difficulty | Targets by section size (below): +60 while a band is under target, −40 once it is met; +40 for level 5 while under its own target | Higher demanding share; the bonus for easy questions in short sections is removed |
| Source balance | +50 to an official question while official questions are under half the section, and +50 to an original while originals are under half; each only for a topic that source has not yet covered in this paper | v2 preferred official questions first, so the first half of every section went to them |
| Source paper | −25 for each question already drawn from the same published paper | New |
| Sitting year | −10 for each question already drawn from the same year (Specimen counts as its own) | New |
| Exposure and versions | Unchanged: seen questions excluded; latest eligible version only | — |

**Difficulty profiles** (`difficultyProfile(sectionSize:)`), as percentages of the section:

| Section size | Levels 1–2 | Level 3 | Levels 4–5 | Level 5 within that |
|---|---:|---:|---:|---:|
| up to 5 | 20 | 60 | 20 | — |
| 6–8 | 20 | 50 | 30 | — |
| 9–15 | 20 | 45 | 35 | 10 |
| 16+ | 20 | 40 | 40 | 10 |

Short sections favour level 3, which tells students apart best, and never force a level 5. Longer ones progress from foundational to demanding questions. Questions are still presented easiest first.

**Soft, not quotas.** The paper and year penalties (25 and 10) are smaller than the difficulty swing (100), so they only decide between questions of comparable coverage and difficulty. A section may use fewer papers than possible when spreading would cost coverage or difficulty. That happened in 3 of 192 sections tested.

## How the weights were chosen

The weights were evaluated before being adopted:
- **A replica first.** A Python replica of the scoring was run on the real development bank for 40–60 students per length, tuning one change at a time.
- **Port and parity.** The Swift implementation was then checked against it and matched exactly for all 96 test diagnostics (4 lengths × 24 students).

Rejected or corrected along the way:
- **Repeat-topic penalty at 120.** Paper 2 covered only 8.2 of 10 topics in Balanced.
- **Paper 1 left choosing topics freely.** Balanced diagnostics averaged 16.4 of 17 topics. The "only here" bonus restored 17 of 17.
- **No penalty once a difficulty band is full.** Balanced Paper 2 averaged 6.3 of 10 questions at levels 4–5, against a target of 4.
- **Same-paper penalty of 40 or 55.** It spread papers slightly more but made Paper 2 harder and cost strands, so it was kept at 25.
- **Official-first source bonus (+50 official, +30 original).** Balanced Paper 2 stayed at 7 of 10 official. The symmetric rule brought it to about 5 with no loss of coverage.

## Results on the development bank

Development bank after R2: 92 original questions and 259 official study copies. The tables give the v2 selection, which every student got, against v3's mean (and range) over 24 students. They come from the Swift selector (`TMUASelectionPolicyTests.testSelectionAuditOnBundledBank`).

### Source composition (official + original)

| Length | Paper 1, v2 | Paper 1, v3 | Paper 2, v2 | Paper 2, v3 |
|---|---|---|---|---|
| Starter (5+5) | 3 + 2 | 3 + 2 | 4 + 1 | 3.0 + 2.0 |
| Quick (8+7) | 4 + 4 | 4 + 4 | 6 + 1 | 3.8 + 3.2 |
| Balanced (10+10) | 5 + 5 | 5 + 5 | 8 + 2 | 4.8 + 5.2 |
| Comprehensive (20+20) | 13 + 7 | 9.8 + 10.2 (8–12 official) | 15 + 5 | 9.2 + 10.8 (7–11 official) |

The original Paper 2 drafts added in R2 (`R2_PAPER2_COVERAGE.md`) let originals compete on topics they could not reach before. The official share now stays near half without being forced.

### Source papers and years

| Length | Paper 1 papers, v2 → v3 | Most from one paper (P1), v2 → v3 | Paper 2 papers, v2 → v3 | Most from one paper (P2), v2 → v3 | Sitting years, v2 → v3 |
|---|---|---|---|---|---|
| Starter | 2 → 3 | 2 → 1 | 3 → 2.8 | 2 → 1.2 | 5 → 5.5 |
| Quick | 2 → 4 | 3 → 1 | 3 → 3.7 | 3 → 1.1 | 5 → 6.2 |
| Balanced | 2 → 5.0 | 4 → 1.0 | 4 → 4.1 | 4 → 1.6 | 6 → 6.8 |
| Comprehensive | 4 → 6.9 | 5 → 2 | 6 → 5.7 | 5 → 2.6 | 7 → 7.0 |

Balanced Paper 1 no longer takes four of its five official questions from Specimen Paper 1; no paper supplies more than two.

### Difficulty (mean questions per section at levels 1–2 / 3 / 4–5)

| Length | Paper 1, v2 | Paper 1, v3 | Paper 2, v2 | Paper 2, v3 |
|---|---|---|---|---|
| Starter | 2 / 3 / 0 | 1 / 3 / 1 | 1 / 3 / 1 | 1 / 3 / 1 |
| Quick | 3 / 4 / 1 | 1.9 / 3.7 / 2.4 | 2 / 4 / 1 | 1.6 / 2.8 / 2.6 |
| Balanced | 4 / 5 / 1 | 2.0 / 4.8 / 3.3 | 1 / 5 / 4 | 1.8 / 4.0 / 4.2 |
| Comprehensive | 7 / 9 / 4 | 4 / 8 / 8 | 5 / 8 / 7 | 3.7 / 7.2 / 9.0 |

- **Paper 1 is more demanding.** It takes 1 to 8 level-4 questions instead of 0 to 4. A Comprehensive Paper 1 is now 4 easier, 8 standard and 8 harder questions, against 7, 9 and 4.
- **Paper 1 still has no level 5,** because the bank has none (`R2_DIAGNOSTIC_SELECTION_AUDIT.md`). v3 does not invent one.
- **Paper 2** averages 2.3 level-5 questions in Balanced and 4.6 in Comprehensive. Short sections get level 5 only by coverage (0.5 in Starter), never by quota.

### Coverage and variety

| Length | Topics (of 17), v2 → v3 | Strands, v2 → v3 | Paper 2 skills (of 10), v2 → v3 | Distinct sets for 24 students | Mean overlap between two students | Questions used across 24 students |
|---|---|---|---|---|---|---|
| Starter | 10 → 10 | 10 → 10 | 5 → 4.8 | 24 | 4% | 145 |
| Quick | 15 → 15 | 15 → 15 | 5 → 5.8 | 24 | 4% | 191 |
| Balanced | 17 → 17 | 20 → 20 | 7 → 7.3 | 24 | 10% | 194 |
| Comprehensive | 17 → 17 | 35 → 35.4 | 10 → 9.6 | 24 | 20% | 240 |

Mean overlap is the share of questions two students' sets have in common (intersection over union). Topic coverage is never below v2 for any student, and is tested. Variety is real, not cosmetic: two Balanced students share about one question in ten, and across 24 students a Balanced diagnostic draws on 194 different questions.

### Expansion

All six upgrade paths, from Starter, Quick and Balanced to each longer length, were tested on the real bank for six students each under v3:
- the exact counts are added;
- no question repeats;
- every expansion reaches new strands;
- earlier answers, marks, timings and snapshots are untouched (service tests).

An expanded v2 diagnostic stays on v2: its added questions are exactly what the v2 rules select.

## Tests

`revisrTests/TMUA/TMUASelectionPolicyTests.swift`, 13 tests:

**Determinism and policy**
- The policy versions, and how recorded versions are read.
- The same identity and policy always select the same questions, whatever the order of the candidates; a different identity or policy gives a different seed.
- v2 is frozen and ignores the seed (golden fixture).
- v3 golden fixture (a deliberate change to v3 needs a new policy version, not a new golden list).

**Pinning through the service**
- A new diagnostic records v3 and its questions are reproducible from its identity.
- A v2 diagnostic keeps v2 and its questions when expanded.
- A relaunch restores the same questions, order, snapshots and policy.
- A newer content version leaves a pinned diagnostic unchanged and is not added again.

**On the bundled bank**
- Every student gets a different set, with mean overlap under 35%, coverage never below v2, both sources present and only eligible questions.
- No paper exceeds its fair share plus one in a section, at most 5% of sections are under-spread, and diagnostics with official questions span several years.
- Difficulty follows each length's profile within one question on average, with a demanding question in every section.
- All six expansion paths.
- A per-student composition audit.

The existing selection, lifecycle and integration tests (40) pass unchanged under v3.
