# R4 diagnostic content integration

29 October 2026. The diagnostic draws from the unified catalogue, unchanged in its rules.

## Lengths and splits (unchanged)

| Length | Paper 1 | Paper 2 |
|---|---:|---:|
| Starter (10) | 5 | 5 |
| Quick (15) | 8 | 7 |
| Balanced (20) | 10 | 10 |
| Comprehensive (40) | 20 | 20 |

## The candidate pool is the catalogue's automatically marked questions

`tmua-selector-v3` is not rewritten. It still receives `TMUAContentContext.eligibleItems`. R4 makes that pool provably the same set as the catalogue's automatic entries: `TMUACatalogueTests.testDiagnosticCandidatesAreExactlyTheAutomaticallyMarkedEntries` checks this in both builds. So:
- **Only automatically markable questions enter a diagnostic.** These are questions Revisr holds a key for in that exact version. Document and external questions, however well indexed, are never auto-scored, and they never produce topic evidence.
- **A reprint is never two candidates.** The one official question set twice (2019 Paper 2 Q2 and 2020 Paper 1 Q2) was already a single bank item, and the catalogue merges its library identities too.
- **What the selector already weighs carries over:** paper, syllabus coverage, difficulty profile, source mix (originals against past papers, with a soft preference only), and source diversity (penalties for repeating a source paper or year). It also excludes questions the student has already seen, uses the latest version only, and respects build eligibility. The rest of the catalogue supplies no diagnostic candidates, because the rest cannot be marked.

## Availability by build

**Development build.** 363 marked questions: Paper 1 has 197 (58 originals, 139 official); Paper 2 has 166 (46 originals, 120 official). All four lengths are offered, as a mixed diagnostic of unreviewed originals and official study copies, labelled as such. Comprehensive needs 20 per paper, so roughly 9 Paper 1 and 8 Paper 2 Comprehensive diagnostics' worth exist before exposure exhausts the pool.

**Public build today.** 0 approved questions, so no length is offered, and the app says why. The library remains reachable.

**Public build, if questions pass review.** Measured by `TMUAPublicContentTests.testPublicCapacityIfOriginalsPassedReview`, with approvals stamped in memory only:

| Approved set | P1 / P2 | Starter | Quick | Balanced | Comprehensive |
|---|---|---|---|---|---|
| Review wave 1 (29) | 14 / 15 | yes | yes | yes | no (Paper 1: 14 of 20) |
| Waves 1–2 (60) | 30 / 30 | yes | yes | yes | yes |
| All 104 originals | 58 / 46 | yes | yes | yes | yes |

## Original-only and mixed-source modes

- **Original-only public diagnostic: now allowed.** The R4 brief says to support it "when enough original questions have actually passed review and publication requirements" and not to require third-party questions. So `TMUAContentPolicy.publicAllowsOriginalOnlyDiagnostic` is now `true`. A public build with approved originals and no licensed questions offers the diagnostic and tells the student "This diagnostic uses original Revisr questions." Each length still needs its full section from approved questions alone, with no padding. Tests:
  - `testPublicOriginalOnlyDiagnosticIsDisclosedNotSilentlySubstituted`, with 20 + 20 synthetic approved originals: available and disclosed;
  - the R3 capacity test: 12 + 12 gives Comprehensive "insufficient: Paper 1 needs 20, 12 available";
  - with the switch off, the diagnostic is blocked.
- **Mixed-source diagnostic.** A public bank with approved originals and licensed questions offers the mixed diagnostic: `testApprovedMixedOriginalAndLicensedBankOffersTheMixedDiagnostic` builds 20 + 20 synthetic approved originals and 20 + 20 synthetic licensed items. Comprehensive picks 20 per paper drawing on both kinds. Development builds keep their mixed mode with study copies. Synthetic approvals exist only inside tests and never count as real permissions.

## Version pinning (unchanged, re-verified)

Once a diagnostic starts, its question identities, versions, order, source references, answers, timing and selection policy are stored in its sections and items (`contentSnapshot`). A Drive update or catalogue rebuild changes none of them. An R4 refresh changes no bank item; it only adds metadata. The lifecycle tests cover this and pass unchanged in the full suite (`R4_VALIDATION.md`): pause and resume, all expansion paths, marking, historical snapshots and `testNewerContentVersionLeavesAPinnedDiagnosticUnchanged`.
