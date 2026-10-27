# Diagnostic selection and expansion

## Selector (`TMUADiagnosticSelector`, `tmua-selector-v2`)

v2 (question-bank integration): the section's target size is fixed before selection (prior questions plus this round); v1 recomputed it after every pick, inflating band targets and the past/mock share. Ties are broken by a stable hash of `stableId@vN` instead of alphabetically, so the oldest paper no longer wins every tie. No rule spreads picks across papers, and with the bundled bank they cluster: Balanced Paper 1's official picks come mostly from Specimen Paper 1 (see `RESOURCE_LIBRARY_INTEGRATION.md`). The table below is otherwise unchanged.

Inputs: paper, count, eligible items (latest version per stable ID), prior items already in this diagnostic, and excluded stable IDs (anything seen in the diagnostic or in practice). Paper 1 is selected first; Paper 2 is selected with Paper 1's picks as prior coverage.

Greedy scoring for each candidate (highest wins; ties broken by a stable hash of `stableId@vN`, so the result is deterministic and independent of input order):

| Term | Weight |
|---|---|
| Topic not yet in the diagnostic | +1000 |
| Each item of the same topic already in this paper's section | −120 |
| Each item of the same topic anywhere in the diagnostic | −40 |
| Strand not yet sampled | +200 |
| Reasoning skill not yet sampled | +80 |
| Difficulty band (≤2 / 3 / ≥4) below its target share (35 / 45 / 20%) | +60 |
| Short section (≤ 8 questions per paper) and difficulty 2–3 ("broadly informative") | +15 |
| Past or mock item (licensed, or a study copy in development builds) while the section is under 50% past or mock, in a topic with no such item yet | +50 |

The chosen questions are presented in ascending difficulty, keeping selection order within a difficulty level.

Hard rules: correct paper; eligible under the build's content policy; structurally valid (taxonomy, options 4–8, key present, solution present); latest version only; no stable ID twice; no excluded/seen ID. If a paper has fewer eligible unseen items than required, selection throws `insufficientContent` and the UI shows the shortfall. It never pads with duplicates or unapproved content.

What each length achieves on the development bank is measured, not assumed; see `UNIVERSAL_ONBOARDING_QA.md`.

## Expansion

From the results screen, the hub, the Settings sheet, or the optional "Refine your diagnostic" plan task, a student can choose any longer length: 10→15, 10→20, 10→40, 15→20, 15→40 or 20→40.

`TMUADiagnosticService.expand`:
1. Requires the initial diagnostic to be submitted and no expansion round open.
2. Computes the cumulative difference per paper (for example 10→15 adds 3 Paper 1 and 2 Paper 2 questions).
3. Selects with all earlier diagnostic items as prior coverage, so additions fill gaps, and excludes every stable ID already met in the diagnostic **or in practice**.
4. Creates a new round with its own sections, timing and advisory minutes. Earlier rounds, answers, marks and timings are never modified.
5. Updates the target length. The report keeps the earlier length's confidence label until the new round is fully submitted.

Questions in an unsubmitted round are **reserved** (R1 fix). Expansion goes through `TMUAProgrammeService.expandDiagnostic`, which refreshes an existing plan immediately. Reserved questions are excluded from planning, open tasks that reference them are retired, and the task screen refuses to show them. Before this fix, an added question could also sit in Today's tasks, and opening that task revealed its worked solution before the student answered it in the diagnostic (`testExpansionReservesQuestionsAndPreservesEarlierWork`).

When the added round is submitted, any open refinement task is marked complete and the programme is refreshed again. Completed tasks are kept and the next three days stay stable.

Each question identity contributes at most one observation to the evidence (`TMUADiagnosticReportBuilder` deduplicates by stable ID), so repeats cannot inflate evidence. The timing note states that extended diagnostics were answered in separate sessions, not under one timed sitting.

If a student practises many questions before expanding, too few unseen questions may remain. The longer options are then disabled with an explanation (`canExpand`). This is tested in `testPractisedQuestionsAreNotReusedAsDiagnosticEvidence`.

## Tests

`TMUAContentAndSelectionTests` (exact counts for every length, determinism, difficulty variety, insufficient content, exclusion, versioning, mixed source) and `TMUADiagnosticLifecycleTests.testEveryExpansionPathKeepsEarlierWorkAndAddsOnlyTheDifference` (all six expansion paths). R1 adds the UI journey `TMUALifecycleAndExpansionUITests.testExpansionFromStarterKeepsEarlierAnswersAndScores` and `TMUAAdaptationScenarioTests.testExpansionReservesQuestionsAndPreservesEarlierWork`.
