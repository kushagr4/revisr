# iOS public release readiness — flexible TMUA

> **Superseded for current status by `R1_RELEASE_READINESS.md` (26 October 2026).** R1 adds:
> - real XCUITest journeys;
> - fixes for timing, save-failure, navigation and expansion defects;
> - planner limits on repetition;
> - an archive-proof content gate;
> - a Git history exposure assessment and the licensing plan.
>
> This file records the state at the end of the first milestone.

**Status: not ready for public release.** The software journey is implemented and tested in development builds. A public build currently contains no eligible questions, so its diagnostic correctly shows as unavailable.

## Implemented and verified (development build)

- Onboarding with user-chosen exam date, weekly time, weekdays, optional session cap and 10/15/20/40-question diagnostic.
- Native diagnostic with pause/resume, termination-safe timing, flags, overview and locked submission.
- Raw-score results with length-dependent confidence on the existing evidence engine.
- Append-only diagnostic expansion.
- Adaptive dated plan for 3–180-day windows; practice with automatic marking and worked solutions; refresh that keeps all history.
- Today / Plan / Progress / Topics / Questions plus Settings, backed by real records.
- Build-time and runtime content gates; Release build verified to bundle 0 unapproved items and 0 restricted PDFs/videos.

Evidence: `UNIVERSAL_ONBOARDING_QA.md` (192-test suite, Release bundle inspection, screenshot walkthrough).

## Blockers

### Content and rights (must be resolved by people, not code)

| # | Blocker | Needed |
|---|---|---|
| 1 | 0 of 60 questions are publicly eligible | Independent human mathematical review of each item version (re-solve, distractors, wording); see the private workspace `review/` notes and blind re-solve record |
| 2 | Originality unverified | Human similarity/originality review of all 60 drafts (40 authored 26 October 2026 with AI assistance; 20 from the Revisr Web W3.0 candidate) |
| 3 | No licensed past/mock content | Written permission or licence from each rights holder (e.g. UAT-UK for TMUA papers) covering in-app reproduction, App Store redistribution, commercial use, answer keys, worked solutions and attribution wording. UAT-UK's site terms allow personal use only. |
| 4 | Mixed-source requirement | Until item 3 exists, the public diagnostic stays blocked (`publicAllowsOriginalOnlyDiagnostic = false`). Shipping original-only needs an explicit product decision. |
| 5 | Bank size | 60 items (34 P1, 26 P2); 8 of 46 strands missing; most topics have 1–4 items. A comprehensive diagnostic leaves only 20 unseen questions for practice, and Paper 2 has no Section 1-knowledge reasoning items yet. Recommend at least 150 reviewed items before launch. |
| 6 | Difficulty and timing | Author estimates only; no student calibration |
| 7 | Legacy third-party resources | The public GitHub repository already contains about 430 MB of past papers, solutions and videos whose redistribution rights are unestablished. They are now stripped from Release builds, but remain in public Git history. Removing them from history requires an explicit decision (it rewrites history and was not done). |

### Software and QA

| # | Item |
|---|---|
| 8 | VoiceOver audit on device, including spoken mathematics in `MathText` |
| 9 | Physical-device and older-iPhone performance measurements (cold launch, plan rendering, memory) |
| 10 | Real interruption testing (calls, lock, background termination) on device |
| 11 | Historical store migration tests still need the original `.qa` fixtures (6 skipped tests) |
| 12 | The TypeScript planner in Revisr Web has not been updated with `PublicPlanningOptions`; parity holds only for legacy options |
| 13 | Release builds strip legacy PDFs, so the personal legacy app and the SMC/BMO PDF diagnostics show "unavailable" in public builds. An internal distribution must set `REVISR_DISTRIBUTION=internal`. |
| 14 | App Store metadata, privacy nutrition label (no data collected), signing and TestFlight — not started; nothing was uploaded |

## Release configuration

- Debug: `REVISR_DISTRIBUTION=internal` — private drafts bundled from `REVISR_PRIVATE_CONTENT_DIR` (default `../revisr-content-private`), labelled "Development content · not yet reviewed".
- Release: `REVISR_DISTRIBUTION=public` — public gate, restricted resources stripped, `check-app` gate fails the build on any violation. Runtime re-applies the gate because Release builds ignore an "internal" bank label.
- No pushes, merges, TestFlight uploads or repository-visibility changes were made.
