# R3 validation

28 October 2026. Everything ran on the Mac or on the approved iPhone 17 Pro simulator (iOS 26.5, `977DC755…`). **Nothing was tested on a physical iPhone**, which this milestone did not require. No new simulator or derived-data folder was created.

## Git

| Repository | Start | End | Pushed |
|---|---|---|---|
| `revisr`, branch `claude/revisr-r3-content-readiness` (from `claude/revisr-r2-diagnostic-quality`) | `92f58a0` | see the handover | No |
| `revisr-content-private`, `master`, no remote | `bb6f3b2` | `86c0661` | No remote |

No history was rewritten. Revisr Web, Vercel and Supabase were not touched. Neither repository has a public remote for private content, and the public repository's changes contain no question text, keys or reviewer material (checked by scanning the changed files for every original stem).

## Kinds of result

| Kind | What it covers |
|---|---|
| Tests executed in R3 | Listed below, with counts |
| Previously verified, not re-run | Physical-iPhone behaviour (never run); the six migration tests that need local staging stores |
| AI-assisted checking | The quality pre-review of 92 questions, the programmatic verifiers of 17 corrections and 12 drafts, and a blind re-solve of 21 versions. Results are in `R3_MATHEMATICAL_QUALITY.md` |
| Human review | **None.** No reviewer is registered and no decision is recorded |
| Calibration | **None.** No student response data exists |
| Blocked | Nothing was blocked; publication itself is blocked by design until reviews and rights exist |

## Automated tests executed in R3

| Suite | Result |
|---|---|
| Full unit suite (`revisrTests`), final bank | **259 run, 253 passed, 6 skipped, 0 failed** (R2: 250 run, 244 passed, 6 skipped). The 6 skips are the same migration tests, which need local staging stores |
| New: `TMUAPublicContentTests` | 9 of 9: the manifest record is required even when an item's fields claim approval; the approval record names its policy, content and grant; banks from before R3 still decode; an empty public bank is unavailable at every length with an honest reason; the original-only decision, with the exact gap per length; the bundled bank as a Release build has 0 public questions but keeps its linked library; linked sites are credited links without papers; a public plan assigns only approved questions and linked papers; the capacity audit |
| Existing selection, lifecycle, integration, planner and typography tests | Pass unchanged. The fixture factory now attaches an approval record to cleared fixtures, because "cleared" now includes being in the manifest; no assertion was changed |
| Full UI suite (`revisrUITests`), light mode | **13 of 13 passed** in 42 minutes with no crash reports: the 12 existing tests and the new `TMUAPublicContentUITests` |
| Journey accessibility audit | Enforced types (element description, hit region, trait): none. 187 advisories recorded across the journey (R2's run: 307; not investigated, since no enforced type fired). The question screen still has 4 Dynamic Type advisories |
| Focused question-screen audit | 23 non-allowed advisories (R2: 22), 18 of them unnamed nodes, no prose, nothing clipped; within its budgets |
| Public-mode screens (hub, library, source) | No enforced issue. Advisories: contrast "nearly passed" on system section headers and footers; Dynamic Type notes on section footers; two "text clipped" notes on the source screen's existing link and record buttons, whose text is complete in the screenshot |
| Assembler and gate tests (`Scripts/tests/test_assemble_tmua_content.py`) | 28 of 28 (13 before R3, 15 new) |
| Other script tests | 4 suites pass. `test_chunk4_programme` errors because its staging file `.qa/chunk4/staging-v1/AdmissionsProgrammeMigration.json` is not in this checkout; this predates R3 and that test is unchanged |
| Private workspace tests (`tools/tests/test_review_workflow.py`) | 9 of 9, on a temporary copy of the workspace |

One infrastructure hiccup, recorded for accuracy: a combined run that built the UI-test scheme after the app scheme replaced the app copy containing the unit-test bundle, so that unit run could not start (no test executed). The app scheme was rebuilt and the full unit suite rerun; that is the result above.


## Content checks

| Check | Result |
|---|---|
| Content validator (whole bank) | 385 versions, 0 structural problems, 0 publicly eligible (manifest revision 1, empty) |
| Review register check | 0 problems; 0 human decisions; 0 registered reviewers |
| Old versions unchanged | no tracked bank file differs from R2 |
| Corrections verifier | 17 of 17 |
| Drafts verifier | 12 of 12 |
| Blind re-solve | 21 of 21 agree |

## Public Release content gate

Release build (`-configuration Release`, generic iOS Simulator), final bank:
- the assembler read approved-content manifest revision 1 (empty) and **assembled 0 items, excluding all 385 versions**, including the 17 corrections and 12 drafts;
- it removed the 242 restricted legacy PDFs and videos, and `check-app` passed;
- the app is 27 MB and contains no PDF, no video, no manifest, register or reviewers file;
- it contains no original-question identifier (`rev-p1-`, `rev-p2-`, including the R3 drafts), no study-copy identifier, and no UI-test fixture identifier;
- the bank declares content policy `tmua-content-policy-v2` and manifest revision 1;
- as before R3, it still bundles the library's metadata manifests (source titles, topics and page numbers of the historical catalogue).

The gate itself is tested in `Scripts/tests/test_assemble_tmua_content.py` (28 tests):
- no manifest means an empty bank;
- the review and rights fields of an approved item come from the manifest;
- a change after approval stops the build;
- register decisions must match the manifest;
- a missing stage stops the build;
- AI reviewer names are refused;
- study copies and fixtures can never be published;
- a licensed question needs a verified grant that covers it and permits all five uses;
- unsupported markup fails the format check, and the gate's command list matches the renderer;
- duplicate question text is rejected;
- tampered bundles and private review files fail `check-app`;
- the reviewer's difficulty rating replaces the author estimate only for the same content.


## Diagnostic integration

- **Selector v3 unchanged.** The 13 selection-policy tests pass, including the frozen v2 and v3 goldens, which use fixture banks.
- **Statistical checks on the bundled bank still pass:** variety across 24 students, spread across papers, difficulty and expansion.
- **New versions take over for new work only.** The latest version of a corrected question is selected; existing diagnostics keep their pinned snapshots (`testNewerContentVersionLeavesAPinnedDiagnosticUnchanged`, unchanged).
- **All four lengths, pause and resume, all six expansion paths, scoring, evidence confidence and exposure tracking** are covered by the unchanged lifecycle and selection tests in the unit suite above.
- **What newly eligible content would do** (`TMUAPublicContentTests.testPublicCapacityIfOriginalsPassedReview`): approvals are stamped in memory only, and the original-only product decision is assumed. The results are in `R3_PUBLIC_CONTENT_PIPELINE.md`.

## Planner content availability

- **Development bank** (`TMUACatalogueAuditTests`: 36 scenarios, 14–180 days, three study loads, Balanced diagnostic):
  - no empty study day;
  - official questions make up 14–72% of practice tasks (27–74% in R2; the 12 new drafts and the corrected versions add original practice);
  - no question is used more than 4 times.
- **Public build today:** no approved questions, so no diagnostic and no plan. The library is reachable and its paper sessions link to publishers' sites.
- **Hypothetical public sets:** see `R3_PUBLIC_CONTENT_PIPELINE.md`. Development-bank capacity is not evidence of public capacity: the development bank's practice is mostly official study copies, which can never ship.

## Disk

18 GiB free on the startup disk at the end (15 GiB at the start of R3).
- R3 reused the existing `dd-r1` and `dd-release` derived-data folders and created no new one.
- Its own test result bundles and exported screenshots (about 270 MB) were deleted after their results were recorded here.
- Older scratch folders from earlier milestones were left alone.

## Remaining blockers

1. **Human review** of every question: no reviewer exists yet. Wave 1 of the queue holds 29 questions: 14 Paper 1 and 15 Paper 2.
2. **Rights:** no permission is held from any provider; nine drafts are ready but unsent. Openly licensed material needs the copy-protection question settled first.
3. **Product decision:** whether a public diagnostic may consist only of original questions (`publicAllowsOriginalOnlyDiagnostic` is false). Until it changes, or licensed questions exist, every public diagnostic stays unavailable even after originals are approved.
4. **Content gaps:**
   - no level-5 original;
   - only two Paper 1 originals at level 4 on both estimates;
   - Paper 2 has no ratio-and-proportion or statistics original;
   - too little fresh practice for long plans.
5. **Calibration:** needs student responses after publication.
6. **Physical iPhone:** not tested in R3.
