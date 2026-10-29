# R4 validation

29 October 2026. Everything ran on this Mac or on the approved iPhone 17 Pro simulator (`977DC755…`). **Nothing was tested on a physical iPhone.** No simulator or derived-data folder was created: R4 reused `dd-r1` and `dd-release`.

## Git

| Repository | Branch | Start | End | Pushed |
|---|---|---|---|---|
| `revisr` | `claude/revisr-r4-unified-question-bank` (from `claude/revisr-r3-content-readiness`) | `a70d4d2` | `01e20bc` catalogue, `c3f6128` Questions tab, `fb78de9` worksheet planner, then this documentation commit | No |
| `revisr-content-private` | `master` (no remote) | `86c0661` | `1f3b40b` | No remote |

No history was rewritten. Revisr Web, Vercel and Supabase were not touched. The public repository's changes contain no question text, answer keys, Drive file IDs or reviewer material.

## Kinds of result

| Kind | What it covers |
|---|---|
| Executed in R4 | The tests and checks below |
| AI-assisted (not human review) | Indexing of the 154 supplement questions; the duplicate judgements; the topic, paper-fit and difficulty estimates of new records |
| Human review | **None.** No question in the catalogue has been reviewed by a person |
| Calibration | **None.** Every difficulty is an estimate |
| Not run | Physical iPhone; the six migration tests that need local staging stores (skipped, as in R1–R3) |

## Automated tests

| Suite | Result |
|---|---|
| Full unit suite (`revisrTests`) | **270 run, 264 passed, 6 skipped, 0 failed** (R3: 259 run), on the R4 code before the final validation fixes below. The 6 skips are the same migration tests that need local staging stores |
| After the final fixes | The four test classes that reach the changed code were rerun: `TMUACatalogueTests` 12, `TMUACatalogueAuditTests` 1 (36 scenarios), `TMUAPublicContentTests` 9, `TMUAQuestionBankIntegrationTests` 14. **36 run, 36 passed.** The rest of the suite was not rerun: it leaves library sessions off, and no other code it reaches changed. The suite now has 271 tests |
| New: `TMUACatalogueTests` | 12 of 12. One identity per question; aliases resolve (an official question set twice, a mock reprinting MAT, a topic bank reprinting an official question, study-copy item IDs); adaptations stay linked variants; the diagnostic pool equals the automatic entries in both builds; no invented keys; the latest version in use, earlier ones resolvable; document presentation only from bundled study copies; a public build presents nothing itself and offers no restricted solution; Drive-only and solution-only papers listed honestly; topics within the syllabus; official papers keep their paper; difficulty always an estimate; reprints merge only when both appearances are in the build; an approved mixed original and licensed bank offers the mixed diagnostic at 20 + 20; worksheets use only self-marked questions, by topic, without repeats; worksheet topics follow the diagnostic's evidence, weakest first |
| Changed by the owner's R4 decision | `testPublicOriginalOnlyDiagnosticIsDisclosedNotSilentlySubstituted` (was `…IsBlocked…`) and the R3 original-only test now expect an original-only public diagnostic, disclosed to the student. Both also check that the switch, when off, still blocks it |
| Planner (`TMUACatalogueAuditTests`, extended) | 36 scenarios. Every paper session names a real paper; every worksheet question is a self-marked catalogue question; no worksheet question repeats or sits in a paper the plan sets whole; no day over capacity; no empty study day with library sessions; no question used more than twice with library sessions |
| Existing selection, lifecycle, integration, timing, typography and planner tests | Pass unchanged: selector v3 goldens, all four lengths, pause and resume, expansion, pinned versions, scoring and evidence |
| Assembler and release-gate tests | 29 of 29 (28 before R4; new: the reconciliation file may not carry keys, Drive IDs or notes, and the committed file passes) |
| Drive inventory tests | 9 of 9 (4 new: unchanged files; changed, moved, new and missing files; a returning file; no titles in the report) |
| Private workspace tests | 13 of 13 (4 new for the reconciliation builder: canonical order, public file current and free of private fields, valid duplicate links, new supplement identities) |
| UI suite (`revisrUITests`), full run | iPhone 17 Pro simulator, iOS 26.5. **14 run: 13 passed, 1 failed, 0 skipped**; no crash; Xcode result "Failed". The failure was the new `TMUAQuestionLibraryUITests`, at its first filter tap (see below) |
| UI, after the fixes | `TMUAQuestionLibraryUITests` was rerun alone. It failed once more at the credit check, and after the second test-query fix it passed all four later runs, the last on the final code. `TMUAFirstRunJourneyUITests.testStarterFirstRunJourney` also passed on the final code, because it generates a plan through the changed scheduler. The other 12 UI tests passed in the full run and were not rerun. They do not inspect worksheet contents, and the Practice filter and flag lookup changes do not reach their screens |

## Defects found and fixed in validation

| Defect | Kind | Fix |
|---|---|---|
| Worksheet days were counted as paper-session days (`testPaperSessionsFillOnlyEmptyDaysAndNeverCreateEvidence` failed, 109 against 87) | App | Separate `worksheetDays` count and message. The test passes unchanged |
| The new library UI test looked for a button labelled exactly "Marking". iOS announces a menu picker in a list as one button with its title and value ("Marking, Any marking") | Test query | The test finds the button whose label begins with "Marking". The expectation is unchanged |
| The test expected the question screen's credit to begin its label. The header is one combined VoiceOver element: question, paper, credit, details | Test query | The test checks that the label contains the credit |
| "Self-marked with the publisher’s solution" was too long for the filter row and was truncated | App | The filter option reads "Self-marked with solution". Rows and question screens keep the full explanation |
| The Practice list had lost R2's Strand filter | App (regression) | Restored. It appears once a topic is chosen and applies to the questions Revisr marks |
| A review flag was looked up under one identity only | App | Flags now match any identity of the question (catalogue ID, item ID or merged reprint), as recorded results already did |
| The worksheet planner reserved every question in the 99 papers *eligible* for a whole-paper session. Development builds never schedule one, so 909 of the 1,098 worksheet questions were locked away, and the heaviest plan stopped at 150 worksheet questions | App | A paper reserves its questions only once the plan sets it whole, and a paper with a worksheet question is not then set whole. The audit checks both. The heaviest plan now uses 979 worksheet questions in 138 worksheets; the other 35 scenarios are unchanged |

## Accessibility

- **Enforced audits pass on every audited screen.** Element descriptions, hit regions and traits pass on the R2/R3 journey, and in R4 on the Practice list, a document question and Sources.
- **Advisories on the new screens** are of the same kinds the journey baseline records:
  - contrast of secondary text and of section headers and footers;
  - partial Dynamic Type support in system list headers and footers;
  - "text clipped" on the Marking filter value and on the "Flag for review" toggle.
  The baseline in this run recorded 204 contrast, 68 Dynamic Type and 15 text-clipped advisories.
- **The clipped filter value was real** (see above) and is shortened. The audit still flags it after the test scrolls the list. That is probably scroll clipping, but it was not checked visually.
- **Largest accessibility text size:** the R2 journey passes at it. The new library screens were audited at the default size only.

## Storage

The R4 scratch folders were removed after checking that their outputs are committed in `revisr-content-private`, under `catalogue/` and `tools/`:
- extracted PDF text;
- rendered page images;
- candidate lists;
- one-off index scripts;
- test result bundles, which included screen recordings of third-party pages;
- logs.

| | Free on `/` |
|---|---:|
| Before | 16.98 GiB |
| After removing 339 MiB | 17.32 GiB |

**Kept:** `dd-r1` (1.3 GB) and `dd-release` (0.5 GB), the two derived-data folders R4 used. Earlier milestones' scratch folders were left untouched.

## Open issues found in validation

- **The adaptive planner is not deterministic across runs.** Identical scenarios gave slightly different distinct-question counts in two runs. Examples: public wave 1, 14 days, 23 then 22; development questions-only, 60 days at 12 hours, 341 then 340. Paper-session counts moved to match. Library sessions are not involved, so this predates R4. A likely cause is hash-order iteration (Swift seeds `Set` and `Dictionary` hashing per launch). It was not investigated in R4.
- **Drive folder ID in a pre-R4 doc.** `docs/GOOGLE_DRIVE_TMUA_RESOURCE_AUDIT.md`, committed in `6b82d45`, quotes the Drive folder's URL. The commit is local and has never been pushed. R4 adds no Drive ID. Decide before pushing whether that line should stay.

## Public Release content gate

Release build (`-configuration Release`, generic iOS Simulator), rebuilt on the final R4 code:
- assembled 0 items, excluding all 385 versions (manifest revision 1, empty);
- removed 242 restricted PDFs and videos, and `check-app` passed, including the new reconciliation check;
- the app is 28 MB (R3: 27 MB) and contains no PDF, video, manifest, register or reviewers file;
- it contains no original or study-copy question identifier (all 385 development-bank IDs were searched for; none was found), no UI-fixture identifier, no Drive folder or file ID, no `drive.google` link and no answer letter;
- it bundles the reconciliation metadata (29 duplicate links, 10 supplement papers) alongside the R1 library index and provider registry, as before;
- the catalogue a public build assembles holds 1,609 questions, all external links to UAT-UK, Oxford, OCR and UKMT, with no solutions. This was measured by `TMUACatalogueTests` on the same bundle judged as public, not by launching the Release app.

## Content checks

| Check | Result |
|---|---|
| Content validator (`assemble_tmua_content.py validate`) | 385 versions, 0 structural problems, 0 publicly eligible (manifest revision 1, empty) |
| Review register (`review_workflow.py check`) | 0 problems; 0 human decisions |
| Reconciliation file is current (`build_reconciliation.py --check`) | Up to date |
| Drive sync against the inventory | 343 unchanged; 0 changed, moved, new or missing |
| Drive inventory structure (`drive_inventory.py validate`) | 343 records, 0 problems |
| Catalogue invariants (`TMUACatalogueTests`) | See above: unique identities, aliases, the diagnostic pool equal to the automatic entries, no invented keys, topics in the syllabus, official papers keep their paper, difficulty always an estimate |
| Supplement IDs | All 154 are new identities; none collides with the library index (checked by the builder and its tests) |
| Duplicate records | All 29 links name indexed questions; no canonical question is itself a reprint |
