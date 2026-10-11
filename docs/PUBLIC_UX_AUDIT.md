# Revisr public UX audit

Updated 11 October 2026. The evidence below records the 9 October simulator inspection; the latest addendum is source-only because CoreSimulatorService remains unavailable. The earlier simulator already contained a completed two-paper diagnostic and one completed programme question, so the clean onboarding and in-progress diagnostic screens were reviewed from source and existing automated coverage rather than reset destructively.

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

## 11 October 2026 Progress and Topics evidence review

### Findings

- Progress labelled assigned work “Active tasks,” although completed assignments can remain active in the saved plan. It showed a 0-of-1 bar when there were no tracked assignments.
- The attempt total did not say that repeated work on one question is recorded as separate attempts. BMO outcomes needed an explicit self-assessment and non-verification statement at the point of presentation.
- Topics displayed the first task reason in fetch order, so the rationale could change between renders. The page also needed to distinguish scheduled topic workload from diagnostic baseline and mastery.

### Source changes

- Progress now shows completed and remaining tasks, linked question attempts, and an honest empty state when no task history or current assignment exists. Its explanation says completed history is retained, retired incomplete tasks are excluded, repeated questions add attempts, and completion is not mastery.
- Outcome sections say “Self-assessed” for BMO and explicitly state those outcomes are not examiner-verified. TMUA and SMC outcomes are labelled self-marked.
- Topics now explains that scheduled workload is not mastery, points students to the diagnostic baseline and recorded outcomes, and chooses the next incomplete task's reason in stable date/ID order.
- Added focused snapshot tests for an empty plan and two completed assignments for the same question, preserving distinct attempt counts.

No score, classification, scheduling, stable ID, schema or persisted user data semantics changed. These changes have source and test review only. XCTest, simulator screenshots, accessibility interaction, light/dark appearance and Dynamic Type remain unverified until Xcode can compile and run the app.

## 11 October 2026 source review

- Plan's task filter and date grouping now run once per `body` evaluation, outside the lazy date rows. This removes repeated whole-list grouping at each row; runtime scrolling measurements are still required to quantify impact.
- Progress completion now counts active tasks and completed historical tasks. Retired incomplete tasks no longer inflate the planned-work denominator after an adaptation refresh. Completed task history and linked attempt IDs remain included.
- A focused regression XCTest was added for active, completed, retired-incomplete and retired-completed tasks. It has not run because Xcode cannot discover usable simulator runtimes.
- Source syntax parsing passed for 132 Swift files and `git diff --check` passed. Debug and Release generic builds both failed before Revisr source compilation during asset processing with `No available simulator runtimes for platform iphonesimulator`.

No visual validation occurred in this continuation. Onboarding, diagnostic introduction/paper/report, Today, Plan, Progress, Topics, Settings and empty states still need screenshot inspection at small/large iPhone sizes, light/dark appearance, accessibility Dynamic Type, Reduce Motion and VoiceOver. Do not describe these as visually verified based on source review.

## 11 October 2026 journey audit and source changes

### Prioritized findings

1. **P1 — Missing-programme recovery had no in-app action.** The public root only asked the student to reopen Revisr, even when completed diagnostics remained saved.
2. **P1 — Today and Plan conflated rest days with days that had no assigned work.** Both labels hid whether the saved availability snapshot marked the weekday available.
3. **P2 — Missing paper files produced contradictory task controls.** The task detail said it could not be completed without its paper, while the completion button only checked whether SwiftData records existed.

### Changes

- The missing-programme state now offers a native **Return to Diagnostics** button with an accessibility hint. It opens the saved assessment flow, where a completed diagnostic can retry programme generation.
- Today and Plan now describe an unavailable weekday as a **Rest day** and an available weekday without generated work as **No tasks scheduled**, using the programme's saved availability snapshot. Exam-day and past-exam messages remain distinct. A focused XCTest covers saved weekday availability and a missing schedule entry; it has not run. A standalone Swift smoke test for the pure availability helper passed.
- Question and full-paper completion controls are disabled when the bundled source PDF cannot be resolved, matching the visible unavailable-resource explanation.

These changes do not alter planner output, examination scoring, SwiftData fields, task identities, completion history or attempt records. Native controls and text labels communicate the new states; no status depends on colour alone.

All 132 Swift files passed syntax parsing, `git diff --check` passed, and a standalone Swift smoke test of the availability helper passed. The new availability XCTest and all other Swift tests remain unexecuted; simulator verification was unavailable. These source changes need iOS compilation and a runtime walkthrough, including unavailable-resource handling, rest/unassigned days and programme-retry navigation. No screenshot, VoiceOver, Dynamic Type, dark-mode or Reduce Motion result is claimed.
