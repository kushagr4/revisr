# Diagnostic evidence contract

## Inputs

One `DiagnosticEvidence` per submitted question identity: topic (title from the syllabus), reasoning skill (optional), paper (`P1`/`P2`), difficulty, whether it was answered, and value (1 correct, 0 incorrect, `nil` unanswered). Unanswered questions are never treated as incorrect evidence; they are reported as "skipped". Topic performance is never inferred from paper totals.

## Engine

The existing `DiagnosticAnalysis` engine (ported to TypeScript in Revisr Web, with parity fixtures) classifies evidence. Its grouping step is now exposed as `DiagnosticAnalysis.aggregate(_:exam:key:requiredSources:)`. The only new parameter is `requiredSources`, the number of distinct papers that must contribute before a firm classification. Its default of 2 reproduces the original rule exactly; the legacy PDF diagnostic and the standalone parity harness are unchanged and still pass.

Unchanged thresholds:

| Level | Rule |
|---|---|
| Strong evidence of difficulty | ≥ 4 assessed, from the required number of papers, ≥ 3 missed, including a difficulty ≤ 3 question |
| Possible area for improvement | ≥ 2 assessed, ≥ 2 missed, missed ≥ half |
| Relative strength | ≥ 4 assessed, from the required number of papers, ≥ 4 correct and ≥ 75% correct |
| Insufficient evidence | otherwise |

Flexible-diagnostic adaptation: Logic of arguments, Mathematical proof and Errors in proofs (and their reasoning skills) are examinable only in Paper 2, so they require one contributing paper. Every Section 1 topic still requires both papers. Without this, the original rule could never classify a Paper 2-only topic, however much evidence existed. No count threshold was lowered.

## Length and confidence

Classification depends on actual counts, so length matters materially:
- **Starter (10):** almost every sampled topic has one question, so it is "insufficient"; a 10-wrong run still produces no "strong difficulty" (`testStarterEvidenceStaysConservative`).
- **Quick (15) / Balanced (20):** a few topics may reach "possible area for improvement".
- **Comprehensive (40):** topics with several questions can reach strong or relative-strength levels; sparse topics stay "insufficient".

The report also shows the length's confidence label and explanation, topics sampled versus not assessed, and Paper 2 reasoning-skill results. No result claims mastery, predicts admission or gives a scaled score.

## Use in planning

Topic results are passed unchanged to the planner as `diagnosticSignals`. Per-question outcomes become planner question history: missed → incorrect (error review), correct → spaced review only, skipped → review flag. Later practice outcomes replace diagnostic outcomes question by question, and recent misses raise topic priority (see `ADAPTIVE_REVISION_ENGINE.md`).
