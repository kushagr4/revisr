# Universal onboarding and journey QA — 26 October 2026

> First-milestone record. R1 replaced the screenshot-only walkthrough with XCUITest journeys that use real taps; see `R1_END_TO_END_VALIDATION.md`.

## Environment

macOS 26.7.1, Xcode 27.1 (27A9275), iOS Simulator SDK 27.1, iOS 26.5 simulator runtime. The CoreSimulator failure recorded in `POST_RECOVERY_VALIDATION.md` (11 October) is no longer present on this host: `simctl list` works, builds succeed and XCTest runs. No runtime or device was repaired, erased or deleted. Tests ran on the existing "iPhone 17 Pro (iOS 26.5)" simulator; screenshots used a new disposable device, "Revisr Flexible TMUA QA".

## Builds

| Build | Result |
|---|---|
| Baseline Debug simulator build of `3e1404a` (unmodified) | **Succeeded** — first complete app compile of this branch |
| Debug simulator build, this branch | Succeeded; content phase: `Assembled internal bank: 60 items` |
| Release `iphoneos` build (generic device, unsigned) | Succeeded; `Assembled public bank: 0 items, 60 excluded`; `Removed 242 restricted legacy resources`; `Release gate passed`. App 14 MB with 0 PDFs and 0 MP4s (Debug app: 447 MB). |

## XCTest

| Run | Executed | Passed | Skipped | Failed |
|---|---:|---:|---:|---:|
| Baseline (`3e1404a`) | 154 | 148 | 6 | 0 |
| This branch, final full suite (includes the real-bank coverage report) | 192 | 186 | 6 | 0 |

The six skips are the historical migration tests whose original `.qa` store fixtures are still missing (unchanged from baseline). New suites: `TMUAContentAndSelectionTests`, `TMUADiagnosticLifecycleTests`, `TMUAPlanningAndJourneyTests`. During development these tests caught three real planner defects that are now fixed: missed diagnostic questions labelled as spaced review; content running out before the final week in 120- and 180-day windows; and front-loaded pacing. The standalone production-logic harness (`docs/fixtures/production-logic-smoke.swift`, compiled with `xcrun --sdk macosx swiftc`) still passes, confirming legacy planner and evidence parity.

### What the tests cover

- All four lengths: exact 5+5 / 8+7 / 10+10 / 20+20, both papers, no duplicates, version pinning, determinism, difficulty variety, coverage growth.
- Rights gates: public gate, Release forces public, fixtures need explicit opt-in, original-only public diagnostic blocked, mixed-source selection with attribution and topic spread (synthetic licensed fixtures — not real permissions), insufficient content rejected.
- Persistence: answers, flags, navigation index, pause, a day away while paused, termination with a running timer and relaunch (file-backed store), resume, no question-set replacement, P2 lock, submission marking, duplicate-submission rejection, locked answers after submission, drafts marked from snapshots when the bank drops a version.
- Expansion: all six paths with cumulative counts, unchanged earlier answers/marks/timings, separate rounds, practised items excluded, deduplicated evidence.
- Scoring/evidence: raw scores out of the chosen length, skipped ≠ incorrect, no scaled-score claims, Starter stays provisional, Paper 2-only topics classifiable, comprehensive relative strength.
- Planning: 3/7/14/30/60/90/120/180-day windows, weekly capacity, exam day excluded, weekday availability, session cap, insufficient capacity, DST-safe day counts, unsampled topics get baseline revision, refinement task only for short diagnostics, every task references real content, refresh keeps completed work and retires (not deletes) the rest, settings changes rebuild future work.
- Full journey for every length on a file-backed store: setup → choose length → start → answer → pause → terminate → relaunch → resume → submit P1 → submit P2 → report → plan → complete task → refresh.
- Legacy safety: a clean install has no personal defaults; an earlier-flow public profile is not moved automatically.

## Simulator walkthrough (screenshots)

The panel-driven tap-through needs the user's simulator-access approval, which was not granted in this session. Screens were instead reached through DEBUG-only launch scenarios (`revisr/Preview Content/DebugTMUAScenarioService.swift`, compiled out of Release) and captured with `simctl io screenshot` on a fresh install each time. Real touch input, VoiceOver navigation and keyboard interaction were **not** exercised.

Inspected: welcome, exam date, availability, length choice, question session, question overview, diagnostic hub, results, Today, Plan, Progress, Topics, Settings sheet, Questions practice; dark mode (results); largest accessibility text size (session, results, length).

Defects found and fixed during the walkthrough:
1. Session-length menu had no visible label → labelled row.
2. White text on the existing accent teal measured about 1.95:1 contrast → added the adaptive `accentStrong` (about 5.7:1 light, 3.3:1 dark for bold button text) for TMUA controls.
3. Six tabs pushed Questions and Settings into iOS's More menu, which produced nested navigation bars → five tabs plus a gear-opened Settings sheet.
4. Some plan days used only 15 of about 50 available minutes → pacing may borrow ahead when nothing is due.
5. At AX5 text size the session controls wrapped letter by letter, the results grid hyphenated, and the onboarding footer crowded the content → icon-only controls (VoiceOver titles kept), stacked facts, and hint moved into the scroll view.

Known remaining UI issues: large navigation titles truncate at AX5 (system behaviour); the "Saved" indicator is an icon with a VoiceOver label and no visible text.

## Not verified

- VoiceOver traversal on device (labels and spoken mathematics are implemented, not audited).
- Physical-device behaviour, older iPhones, cold-launch timing, memory and scrolling performance (no Instruments traces were captured).
- Real background, lock and call interruptions (logic is unit-tested via service calls; the `scenePhase` hook was source-reviewed).
- Migration of genuine historical stores (fixtures still missing).
- Notification delivery (scheduling code only).
