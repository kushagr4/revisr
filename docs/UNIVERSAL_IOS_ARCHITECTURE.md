# Universal iOS architecture — flexible TMUA journey

Branch `claude/flexible-tmua-ios`, started from `codex/ios-completion` at `3e1404a`. Native SwiftUI and SwiftData only; there is no WebView or cross-platform runtime.

## Journeys and routing

`RevisrApp` → `StartupView` → `SeedDataService.bootstrapForLaunch` decides which product a store belongs to. Nothing in this routing rewrites earlier records.

| Store state | `publicOnboardingStage` | `publicFlowVersion` | Root view |
|---|---|---|---|
| Original personal store (pre-public) | `nil` | — | `RootTabView` (legacy personal app, unchanged) |
| Clean install (new) | `.profile` … | `2` | `TMUAFlowRootView` (flexible TMUA) |
| Public profile never saved (stage `.profile`) | `.profile` | set to `2` on launch | `TMUAFlowRootView` |
| Earlier public PDF-diagnostic profile (TMUA/SMC/BMO) | `.diagnostics`… | `nil` | `PublicPreparationSetupView` (earlier flow, unchanged) |

`TMUAFlowRootView` routes by stage: `.profile` → `TMUAOnboardingView`; `.diagnostics`/`.diagnosticsComplete` → `TMUADiagnosticHubView`; `.programme` → `TMUARootTabView`. The welcome screen's "Preparing for SMC or BMO instead?" link clears the flow version and opens the earlier setup form, so SMC and BMO stay available without their PDF/self-marking assumptions entering the TMUA flow.

## Layers

| Layer | Files | Notes |
|---|---|---|
| Content model | `Models/TMUA/TMUAContent.swift`, `Resources/TMUASyllabus.v1.json` | Versioned items (stable ID + version), rights and review records, hierarchical syllabus. |
| Content policy | `Services/TMUA/TMUAContentPolicy.swift` | Public gate, internal/public distribution, source-mix status, availability per length. `TMUAContentStore` decodes the bank once per launch. |
| Selection | `Services/TMUA/TMUADiagnosticSelector.swift` | Deterministic, coverage-aware greedy selection (`tmua-selector-v2`; see `RESOURCE_LIBRARY_INTEGRATION.md`). |
| Diagnostic lifecycle | `Models/TMUA/TMUADiagnosticModels.swift`, `Services/TMUA/TMUADiagnosticService.swift` | Rounds → sections → pinned items; timing; submission; expansion. |
| Evidence | `Services/Admissions/DiagnosticAnalysis.swift` (existing engine), `Services/TMUA/TMUADiagnosticReport.swift` | Raw score and topic/skill evidence from question-level outcomes. |
| Planning | `Services/Admissions/PublicPlanningEngine.swift` (existing engine + opt-in options), `Services/TMUA/TMUAProgrammeService.swift`, `PublicProgrammeService.applyPlan` | One shared refresh rule set for both public programmes. |
| UI | `Features/TMUA/*`, `DesignSystem/MathText.swift` | Onboarding, hub, assessment, results, expansion, Today/Plan/Progress/Topics/Questions + Settings sheet. |
| Build | `Scripts/assemble_tmua_content.py`, "Assemble TMUA Content" build phase | Bundles and gates content; strips restricted resources from public builds. Since R1, `resolve_distribution` allows internal content only in Debug and never in an archive. |
| UI tests (R1) | `revisrUITests/*`, scheme `revisrUITests`, `Preview Content/DebugUITestSupport.swift` | XCUITest journeys. Debug-only launch switches: `--uitest-store <name>` opens an isolated store (never the student's own), `--uitest-reset` deletes it first, and `--uitest-fixture-bank` installs synthetic development fixtures instead of the private drafts. All are compiled out of Release. |

## SwiftData additions (all additive)

New entities: `TMUADiagnostic`, `TMUADiagnosticSection`, `TMUADiagnosticItem`, `TMUAPracticeAttempt`, `TMUAReviewFlag`, and (question-bank integration) `TMUAResourceLog` for self-recorded results. New optional attributes: `AppSettings.publicFlowVersion`, `publicDiagnosticLengthRawValue`, `publicSessionMinutes`; `PublicProgramme.sessionMinutesSnapshot`, `refreshSummary`. These are lightweight-migration changes; no existing attribute was renamed or removed, and no record is relabelled. The flexible programme uses the existing `PublicProgramme`/`PublicProgrammeTask` entities under a distinct ID (`tmua-flex-programme-v1-<profile>`), so an earlier `public-programme-v1-…` programme is never overwritten.

Native practice uses `TMUAPracticeAttempt` instead of `QuestionAttempt`, because bank items are not `AdmissionsQuestion` rows. The legacy catalogue, its attempts and the personal programme are untouched.

Integrity rules added in R1:
- A section's clock stops whenever the app leaves the foreground, and the student resumes explicitly.
- A 60-second checkpoint bounds time lost to a crash.
- A failed save restores the in-memory records, because SwiftData's rollback does not.
- Questions in an open diagnostic round are reserved and kept out of planned practice.
- Opened tasks are bound to their task by value-based navigation (`TMUATaskRoute`), so completing the "Next" task cannot swap the open screen to another question.

Details: `R1_DIAGNOSTIC_AND_PLANNER_AUDIT.md`.

## Main navigation

Five tabs — **Today, Plan, Progress, Topics, Questions** — plus **Settings**, opened by the gear button on every tab. This deliberately deviates from the six-tab request: on iPhone, iOS folds a sixth tab into a "More" list whose navigation controller nests each tab's `NavigationStack`, which produced duplicated back buttons in the simulator walkthrough. A gear-opened Settings sheet is the standard iPhone pattern and keeps every screen's navigation correct.

## Offline and privacy

After installation the whole journey runs offline: content is bundled, all state is local SwiftData. No account, backend key or network call is involved. The optional daily reminder is a local notification that asks for permission only when it is switched on.

## Performance notes

- The bank is decoded once (`TMUAContentStore`) — about 60 items in development.
- Plan rows receive pre-grouped tasks; per-row work is constant time. The planner runs only on explicit generate/refresh actions, never during rendering.
- `MathText` parses short strings per render. Measurement on older devices has **not** been performed (see `IOS_PUBLIC_RELEASE_READINESS.md`).
