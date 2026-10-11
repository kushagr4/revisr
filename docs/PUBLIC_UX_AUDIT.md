# Revisr public UX audit

Updated 9 October 2026 during the Phase 4A/4B review. This audit covers the current public-user programme state on the isolated `Revisr Phase 3 QA` iOS 26.5 simulator and a source review of onboarding, diagnostics and persistence services. The simulator already contained a completed two-paper diagnostic and one completed programme question, so the clean onboarding and in-progress diagnostic screens were reviewed from source and existing automated coverage rather than reset destructively.

## Evidence captured in this run

1. **Today** — the current screen showed a clear programme title, exam date, weekly minutes, 1/5 completion, four visible task rows and the five-tab navigation. The next action was implicit in the task rows rather than surfaced as a single primary action.
2. **Plan** — the screen showed 22 calendar days, 97 tasks, a refresh action and dated task groups. The calendar rows were readable, but the first visible dates mixed completed and future work without a stronger “today/up next” anchor.
3. **Progress** — the screen showed completed tasks, active tasks, recorded attempts, four outcome counts and topic completion. It was honest about scheduled work not counting as progress, but it did not yet show a compact completion trend or diagnostic baseline.
4. **Topics** — the screen showed planned topic counts and evidence reasons. It was informative but repeated long rationale text across many rows and offered no visual distinction between low evidence and recorded weakness.
5. **Settings** — the public settings screen showed examination, date, weekly target, available days, edit preparation and local-only privacy. The grouping is understandable; programme refresh and source acknowledgement can be more explicit.

## Findings

### P1 — Today needs one obvious next action

The current screen makes the student scan the task list to decide where to begin. A primary “Start next task” action should sit in the daily summary and use the first incomplete task. This reduces decision cost without changing scheduling semantics.

### P1 — Empty and boundary states need deliberate copy

Today currently uses the same “rest or unfilled day” wording for an available rest day, an exam day and a past exam date. Those states need separate neutral messages so the app never looks broken or implies fabricated work.

### P1 — Long Plan windows need cheaper grouping

The Plan view filters the full active task collection once per date row. This is acceptable for the current 22-day sample but scales poorly for several months. Grouping tasks by calendar day once keeps the existing UI and reduces repeated work during rendering.

### P2 — Progress needs a clearer evidence hierarchy

The current counts are accurate, but completion, recorded outcomes and topic exposure are presented with equal visual weight. Add a compact completion indicator and preserve explicit language that task completion is not mastery.

### P2 — Rationale text is over-repeated

Today and Topics repeat long planner reasons in every row. Keep the reason available, but reduce visual density with a compact secondary line and a dedicated task detail view for the full explanation.

### P2 — Shared semantic tokens are underused

The design system has colours, typography, spacing and metrics, but public views still rely heavily on raw `.secondary`, `.headline`, `.title3.bold()` and system list defaults. Add a small set of semantic card, status and progress tokens and use them in the public experience.

### P2 — Accessibility state should be explicit

Combined task rows expose their text, but completion state is carried mainly by an icon. Add an accessibility value such as “Completed” or “Not started” and retain text labels for all colour-coded states.

## Proposed priorities

1. Make Today action-led and add intentional rest, exam-day, passed-date and all-complete states.
2. Consolidate semantic tokens and shared public card/status treatments.
3. Group Plan tasks by day and keep the date list lazy and bounded.
4. Add honest Progress completion context and accessible status labels.
5. Revisit the diagnostic report and onboarding introduction after the public shell is visually consistent.
6. Measure launch, plan rendering, SwiftData refresh and PDF opening with a stable simulator baseline before adding caches or concurrency.

## Accessibility and performance limits

Screenshots and the accessibility tree were inspected at the simulator's default text size in light appearance. VoiceOver rotor order, Dynamic Type extremes, dark mode, Reduce Motion, small-device layout and memory profiling require dedicated follow-up runs. The Phase 4A `xcodebuild` retry still loses CoreSimulatorService during startup; the previously completed Phase 3 targeted tests remain the reliable automated baseline until that service is stable.
