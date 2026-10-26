# Question difficulty and authenticity audit

26 October 2026. Aggregates only; per-item findings stay in `revisr-content-private/review/`. **No difficulty in Revisr is calibrated:** there are no student response data and no expert ratings. Every level shown in the app is labelled "(estimated)".

## The 87 draft versions (82 distinct original questions)

R1's AI pre-review re-solved each of the original 60 questions and suggested a difficulty level and time without seeing the stored values. That is agreement or disagreement between estimates, not calibration.

| Set | Questions | Stored level | AI-suggested level | Rated easier than stored | Stored minutes → suggested |
|---|---:|---|---|---:|---|
| Paper 1 from Revisr Web | 20 | 9 × L2, 10 × L3, 1 × L4 | 8 × L1, 11 × L2, 1 × L3 | **17** | 74 → 36 |
| Paper 1 supplement | 14 | 4 × L2, 7 × L3, 3 × L4 | 1 × L1, 5 × L2, 8 × L3 | 6 | 55 → 44 |
| Paper 2 reasoning | 26 | 6 × L2, 12 × L3, 7 × L4, 1 × L5 | 8 × L2, 11 × L3, 6 × L4, 1 × L5 | 3 | 103 → 87 |
| R1 drafts (strand gaps, Paper 2 Section 1 load, corrections) | 27 | mostly L3–L4 (author estimates) | blind check only, no difficulty review | — | — |

Findings:

- **The 20 web-derived questions are routine.** They are one- or two-step exercises, below real TMUA Paper 1, and their stored levels and times overstate them. Use them as foundation practice, not as diagnostic evidence of TMUA readiness.
- **Paper 2 originals are closer to their stated level**, but the set is narrow:
  - 51 distinct methods across 60 questions;
  - 3 near-duplicate Paper 2 pairs (same logical template);
  - 6 Paper 2 questions that rest on the same fact about when a conditional fails.
- **Length is not difficulty.** No draft was made "harder" by adding words, and none should be.
- **Answer-key position bias** (R1): keys are never the last option, and in numeric Paper 1 lists never the smallest or largest. New versions must vary key positions.
- **Not changed automatically:** no stored difficulty was raised or lowered without human review. Historical versions stay as submitted; improvements go into new versions after review, as R1 did for the 5 corrected versions.

## The official TMUA questions now in development builds

The 259 official study copies (2017–2022 Papers 1 and 2, Specimen Paper 1) are authentic by definition. They are the questions UCLES set, with UCLES's keys and worked solutions. Their stored levels come from the original Revisr library index and are also estimates:

| Estimated level (original index) | Questions |
|---|---:|
| 2 (Core) | 64 |
| 3 (Challenging) | 93 |
| 4 (Very hard) | 66 |
| 5 (Olympiad / extreme) | 36 |

Those labels were inferred when the library was indexed. They are useful for ordering, but they are not official item statistics: UAT-UK does not publish per-question facility values. No Revisr screen claims that a question matches official TMUA difficulty.

## How selection uses difficulty now

- **Fixed targets:** the diagnostic selector aims for roughly 35% easier (L1–2), 45% standard (L3) and 20% harder (L4–5) questions in each section. A pre-existing bug inflated these targets as the section filled (fixed in selector v2; see `RESOURCE_LIBRARY_INTEGRATION.md`).
- **Real questions preferred, softly:** the selector prefers real past or mock questions up to half of each section. Syllabus coverage still comes first, so the easy web-derived originals can no longer fill a diagnostic on their own.
- **Measured on the bundled bank:** a 20-question section per paper mixes official and original questions from at least three different official papers, across levels 2–5 (`TMUAQuestionBankIntegrationTests`).
- **Practice:** the planner schedules official questions as ordinary auto-marked practice. In the 14–180 day audit they made up 34–75% of practice tasks.

## Distinguishing estimates from evidence

| Kind | Source | Shown as |
|---|---|---|
| Stored level of an original draft | Author's estimate; AI pre-review notes in the private register | "level n (estimated)" |
| Level of an official question | Original library index, inferred | "level n (estimated)"; provenance recorded on the item |
| Level of a library question without a key | Original library index label | "Challenging (estimated)" |
| Observed performance | Diagnostic and practice results | Topic evidence with a confidence label; never converted into a difficulty level |

## Recommendations

1. **Human review first:**
   - review the official keys' transcription (two independent readings already agree) and the AI strand classification;
   - review the drafts, starting with the 3 Paper 2 near-duplicate pairs;
   - decide whether the 20 web-derived questions stay in the diagnostic pool or move to foundation practice only.
2. **Calibration:** once students use the app, record per-question facility (proportion correct) and time. Recalibrate after about 30 or more responses per question, keeping the estimate and the observed value separate.
3. **New originals:** write them only for genuine gaps (most strands have one or two original questions). Vary key positions, and target multi-step reasoning, not length.
