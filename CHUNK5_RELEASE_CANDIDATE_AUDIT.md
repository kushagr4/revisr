# Revisr Chunk 5 Release-Candidate Audit

Date: 1 September 2026 (Europe/London)

Verdict: **PASS**

Scope: final pre-physical-device validation only. The paired physical iPhone was not installed to, uninstalled from, queried for mutation, or otherwise modified. No Chunk 6 action was performed.

Core evidence is retained under `.qa/chunk5/`. The authoritative machine-readable audit is `.qa/chunk5/RELEASE_CANDIDATE_AUDIT.json`; the repeat-import comparison is `.qa/chunk5/IDEMPOTENCY_AFTER_AUDIT.json`.

1. **Release-candidate verdict — PASS.** All acceptance gates are green and no release-blocking issue remains.

2. **Files changed during Chunk 5.** Added `Scripts/audit_chunk5_release_candidate.py`, `Scripts/tests/test_chunk5_release_candidate.py`, `revisrTests/Admissions/Chunk5ReleaseCandidateTests.swift`, and this report. Validation evidence was added below ignored `.qa/chunk5/`; ignored build products were added below `.derived/chunk5-*`. No production app source, resource, manifest, signing, version, or programme content was changed.

3. **Defects discovered.** No production-app defect was demonstrated. Validation work found three audit-coverage issues: optional resource checksums/page endpoints were initially treated too strictly, the first logical digest included Core Data's non-semantic `Z_OPT` counter, and the legacy catalogue/programme migrations lacked a single end-to-end test.

4. **Defects fixed.** The audit now follows the production preflight rules, excludes only `Z_OPT` transaction metadata from logical hashes, and includes a complete legacy Chunk-2-store-to-release-candidate migration/idempotency test. These were validation-only fixes.

5. **Remaining minor issues.** None in the app. Physical-device VoiceOver, thermal behaviour, and device-specific performance remain intentionally deferred to Chunk 6. XCTest logs contain an Apple CoreSimulator duplicate WebKit accessibility-class warning; it caused no test or app failure.

6. **Pre/post logical database digest.** Before repeat import: `37dc0871ea4fac04792945511a24d019d636ee542cd863b91b4e7dbb30ec4ade`. After two complete seed/import/migration passes: the same digest. Every table-level logical hash and row count also matched.

7. **Catalogue counts.** 2,600 questions, 136 sources, 120 solution documents, 2,364 question-solution mappings, and 8 shared local videos. SQLite integrity is `ok`; identifier uniqueness, relationships, page/media ranges, resource resolution, checksums, canonical Yotta IDs, MioMath resolution, the Combinatorics pair, and STEP report handling all passed.

8. **Historical performance counts.** 48 attempts, 47 unique attempted questions, 3 sessions, and 0 results. IDs, timestamps, outcomes, error types, notes, durations, question/assignment relationships, session data, results, review state, and topic state matched the trusted baseline.

9. **Programme counts.** 894 stored assignments, 452 active assignments, 47 completed assignments, 30 active numbered days, 47 active/completed D1-D3 assignments, and 405 active D4-D30 assignments.

10. **D1-D3 fingerprint.** `326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e`; all 47 IDs, day relationships, active states, and completion states are unchanged (D1 16, D2 16, D3 15).

11. **Canonical stream counts.** TMUA 1,364; CSAT 80; SMC 300; BMO 93; Cambridge CS Interview 0; nil-primary enrichment 763. Canonical fields override legacy `admissionsTest`, with compatibility fallback still tested.

12. **Intended-use counts.** TMUA 1,920; CSAT 348; SMC 300; BMO 93; Cambridge CS Interview 268. Nil-primary enrichment remains available through intended-use data without mass-rewriting the legacy field.

13. **Needs Review / Redo preservation.** 5 Needs Review and 2 Redo remain intact. Trusted history signatures are unchanged, and simulator solution/PDF/video viewing left attempts, sessions, results, and review state unchanged.

14. **D4-D30 date validation.** All dates exactly match the approved mapping from D4 31 Aug through D30 14 Oct; every numbered day exists once, all required gaps remain gaps, and no unavailable date contains mandatory work.

15. **D7/D11 diagnostics.** D7 is Euclid R2DREW2 Paper 1 and D11 is Euclid Sample Paper 2. Both are complete/coherent, resolve to local solution support, have all question IDs, are not materially attempted, and are accessible on their intended dates.

16. **Official benchmarks.** 2017 P1/P2, 2018 P1/P2, 2019 P1/P2, 2020 P1/P2, and 2021 P1/P2 are excluded from automatic practice before their approved dates, programme-accessible on those dates, and not re-protected afterward. Flex dates do not unlock them early.

17. **TMUA 2022 protection.** All 40 questions remain permanently protected, unscheduled, schedule-ineligible, and excluded from automatic practice before the programme, on flex dates, on D30, on exam day, and in a synthetic post-exam check.

18. **Flex/unavailable dates.** Simulator Today was manually validated on all 19 requested dates: 3, 5, 6, 10, 12, 13, 17, 20, 24, 26, and 27 Sep; 1, 3, 4, 8, 10, 11, 13, and 15 Oct. Every date showed neutral “No Mandatory Programme Work Today” copy, no D30 fallback, and no overdue language.

19. **Tuesday restriction.** All six mandatory Tuesdays (1, 8, 15, 22, 29 Sep; 6 Oct) were manually checked at 13:59 and 14:00. Before 14:00, Today showed “Programme Available After 14:00”; at 14:00, the correct questions were available. 13 Oct stayed non-mandatory.

20. **Repair validation.** D17, D22, and D29 use fixed, deterministic seeded repair sets rather than runtime adaptive selection. Their repeat questions and rationales are explicit in the manifest; deterministic-selection tests cover incorrect/partial/review priority, protection exclusion, empty candidates, and absence of networking/AI.

21. **Duplicate-assignment audit.** No duplicate active assignment ID, same-day question duplication, retained/replacement collision, or inactive mandatory work was found. The only cross-day repeats are the 14 documented repair/review questions; inactive history was retained and does not generate Today/overdue work.

22. **Progress analytics QA.** Historical attempts alone drive accuracy; unattempted imports, future/inactive assignments, and solution/video views do not. Empty/low-attempt streams render an em dash or zero state rather than NaN/divide-by-zero. The simulator showed `0 of 2600` and `0/452` correctly on a clean fixture.

23. **Topics QA.** Historical topic state (21 records) is byte-for-byte unchanged. Imported questions, solution mappings, and programme assignments create no study time or completion, and no duplicate topic seed was created.

24. **Today QA.** Simulator checks covered an ordinary day, all Tuesday boundaries, D7 and D11 diagnostics, D15 benchmark, D21 full simulation, D24 mixed SMC/BMO/CSAT, all flex/unavailable dates, D30, and exam day. Focus/date/duration/questions were correct, rows were unique, and the clean UI fixture remained at 0 attempts/sessions/results.

25. **Plan QA.** The 30-day timeline retained D1-D3 history and all intentional Aug-Oct gaps. Exact calendar mapping, flex/unavailable gaps, Tuesday timing, benchmark placement, and absence of obsolete overdue clusters passed manifest, model, and simulator inspection.

26. **Question Bank QA.** The simulator rendered 2,600 questions with source/paper/question/topic/difficulty/state and media badges. Automated local-open tests cover official/third-party TMUA, JZ, MioMath, Euclid, Beyond Horizon, Tyler, CSAT, SMC, BMO, MAT, STEP I/II, and Yotta; filters and protection/solution states remained coherent.

27. **Solution Bank QA.** It showed 120/120 local documents, 2,364/2,600 direct mappings, honest available/partial/pending coverage, and grouped sources. Worked PDF, combined paper/solution, challenge solutions, and video rows resolved locally; multi-source STEP relationships and non-fabricated page/time mappings passed tests.

28. **PDF viewer QA.** Bundled PDFs opened locally with the correct viewer title/resource, readable content, mapped-page support, navigation, rotation without crash, usable dark surrounding chrome, and safe Done/back return. The bundle-wide readable-PDF test passed for every manifest source and solution.

29. **Video playback QA.** The Asher Falcon bundled MP4 opened in AVKit, played, paused, resumed, sought forward, rotated without crash, and returned safely. No duplicate playback/session, attempt, result, correctness, or review mutation was created.

30. **Offline QA.** Runtime source contains no URLSession/NWConnection/web request, cloud database, or remote-resource call. Today, Plan, Question Bank, PDFs, video, progress, programme, and timer paths were exercised using bundle/store data only. TMUA.fyi is not a runtime dependency.

31. **Quick Study/timer regression.** Start, pause, resume, finish, complete-without-timer, persisted timestamp, navigation/background recovery, and relaunch/no-duplicate-session behaviours all passed the full Swift suite using fixtures.

32. **Settings/availability regression.** Sunday and Thursday remain unavailable; Tuesday starts at 14:00; editing/validation tests pass; TMUA is active while Mathematics and Further Mathematics are inactive. CSAT/SMC/BMO were not incorrectly introduced as generic Subject records.

33. **Export validation.** Revision and full exports are read-only/deterministic, decode/round-trip successfully, contain catalogue/stream/intended-use/validity/media/programme/history/state metadata, and exclude PDF/MP4 bytes, absolute device paths, secrets, credentials, and unrelated legacy records.

34. **Accessibility QA.** Accessibility trees expose meaningful labels/values for programme progress, question rows, filters, Source/Solution Bank, Done/back actions, video play/pause/seek controls, and protected/solution states. Accessibility-extra-large Today remained operable through its Scroll Down action. Full physical-device VoiceOver remains a Chunk 6 check.

35. **Dark-mode/layout QA.** Today, Plan, Progress, Topics, Settings, Question Bank, Solution Bank, PDF chrome, and video flow were inspected in light/dark and standard/accessibility-extra-large text. Content remained legible and scrollable with no horizontal overflow, missing controls, or catastrophic clipping.

36. **Performance/memory sanity.** Simulator launch command returned in 0.44 s and Today content was ready within the subsequent UI poll. Bank/viewer/tab navigation produced no hang. RSS was about 333 MiB after the complete 2,600-question seed and about 398 MiB after PDF/video use, returning to a fresh process on relaunch; no continuing growth or eager video/PDF-byte load was observed.

37. **Resource bundle count and size.** Release app: 234 PDFs and 8 MP4s exactly once; PDF/MP4 payload 445,168,336 bytes; source `Resources` directory 450,574,552 bytes; built simulator `.app` 459,516,714 bytes (439 MiB allocated). No duplicate binary groups, `.qa`, database, log, temp, or unintended JSON audit file is bundled. The four bundled JSON files are intentional manifests/registry data.

38. **Privacy/network audit.** No analytics/ad/cloud/account/telemetry/background-upload SDK or remote Swift package exists. “Analytics” source hits are local calculation types only. No runtime absolute `/Users/...` path exists; the one `/Users/` string is an export-redaction guard.

39. **Debug build.** Final iOS 26.5 simulator Debug build succeeded.

40. **Release build.** Final iOS 26.5 simulator Release build succeeded. A separate unsigned/signing-safe generic iOS Release build also succeeded without changing signing/team settings.

41. **Swift tests.** 128 passed, 0 failed. This includes corpus, resource, solutions/media, migration, programme, protection, export, timer, progress, topics, settings, failure rollback, clean seed, relaunch, idempotency, and the new full legacy-chain proof.

42. **Python/resource tests.** 16 passed, 0 failed. Resource inventory/checksums, identifiers/relationships, atomic generation rollback, corpus decisions, exact programme structure/content, workload, diagnostics, streams, duplicates, and Chunk 5 release gates passed.

43. **Catalogue-import idempotency.** Re-running bundled catalogue and solution import on the release-candidate copy created no question, source, solution, or link and changed no logical catalogue/history state.

44. **Programme-migration idempotency.** Re-running the Chunk 4 programme migration twice created no day/assignment, changed no historical attempt/D1-D3 state, and preserved the complete logical digest.

45. **Clean-install test.** A persistent empty store seeded 2,600/136/120/2,364, 30 days, 894 stored/452 active assignments, and zero attempts/sessions/results; reopening and repeated seed calls produced no duplication.

46. **Legacy-store full migration.** A copied trusted Chunk 2 fixture (1,573 questions, 48 attempts, 3 sessions, 0 results) ran the real schema/catalogue/solution/programme seed chain to the exact final counts. User history/D1-D3 signatures remained identical, and a second full run was idempotent.

47. **Relaunch result.** Persistent-store tests reopened and seeded more than once with stable counts, relationships, protection, and programme. Simulator relaunches across dates also loaded without duplicate seed/import or resource loss.

48. **Date-boundary result.** Deterministic tests passed for 30→31 Aug; 2→3→4 Sep; 14→15 Sep; 27→28 Sep; 11→12 Oct; 13→14 Oct; and 14→15→16 Oct. D30 is 14 Oct, 15 Oct is non-mandatory, 16 Oct never falls back to D30, and no post-exam day is fabricated.

49. **Repository/file hygiene.** `.qa/` and `.derived/` are ignored and absent from the app target; the Release bundle contains no QA/store/log/temp files. No source secrets/certificates/profiles/personal runtime paths were found; provisioning profiles exist only inside ignored historical `.derived` products. Caveat: this workspace's repository contents were already entirely untracked, so Git cannot provide a meaningful baseline diff; no history was rewritten.

50. **Physical-iPhone confirmation.** The paired physical iPhone was **NOT modified**. No install, uninstall, data reset, store replacement, signing change, or physical-device launch was performed.

51. **Chunk 6 readiness.** **READY FOR CHUNK 6 PHYSICAL DEPLOYMENT**, subject to explicit user approval. Chunk 5 stops here.

## Evidence index

- `.qa/chunk5/RELEASE_CANDIDATE_AUDIT.json`
- `.qa/chunk5/IDEMPOTENCY_AFTER_AUDIT.json`
- `.qa/chunk5/swift-tests-final.log`
- `.qa/chunk5/python-tests-final.log`
- `.qa/chunk5/debug-build-final.log`
- `.qa/chunk5/release-build-final.log`
- `.qa/chunk5/generic-ios-build-final.log`
- `.qa/chunk5/release-bundle-inventory.log`
- `.qa/chunk5/static-hygiene-audit.log`
- `.qa/chunk5/legacy-full-chain-test.log`
- `.qa/chunk5/simulator-ui-before-state.json`
- `.qa/chunk5/simulator-ui-after-state.json`
- `.qa/chunk5/simulator-memory-idle.log`
- `.qa/chunk5/simulator-memory-snapshot.log`
