# Revisr Chunk 4 — 30-Day Programme Migration Audit

Status: complete in source and in an isolated copy of the paired-iPhone store. Nothing was installed on the physical iPhone. Chunk 5 was not started.

Migration revision: `6cf15d8306ad208078c51ea181fe2674c73fdc09edc5a531aa34a0697f66b73e`

1. **Current pre-migration progress discovered.** The immediate paired-iPhone snapshot contained 48 attempts across 47 questions: 20 correct, 17 incorrect, 10 partial and 1 skipped. D1/D2/D3 had 16/16/15 completed assignments. It contained 530 assignments, 3 study sessions, no results, 18 planned blocks, 5 Needs Review questions and 2 Redo questions. The stored programme began 22 August 2026, the exam date was 16 October 2026, Sunday and Thursday were unavailable, Tuesday began at 14:00, TMUA was active, and Mathematics/Further Mathematics were inactive.

2. **New D4+ work preserved.** No D4+ attempt, manual completion or skip was found in the immediate pre-migration snapshot. The migration nevertheless freezes any D4+ assignment that has an attempt or completion; synthetic tests prove attempted and completed obsolete assignments survive with the same identity and history.

3. **Old D4–D30 assignments retained.** 41 existing high-value D4+ stable assignment IDs are reused. D1–D3's 47 assignments are untouched.

4. **Old D4–D30 assignments deactivated.** 442 obsolete, unattempted, history-free D4+ assignments are retained in storage but marked inactive, so they cannot appear as a mandatory overdue backlog.

5. **New assignments added.** 364 deterministic assignments were added. IDs are derived from programme/day/question/purpose rather than random programme identity.

6. **Final assignment count.** The migrated store contains 894 assignment records: 452 active and 442 inactive historical records. The active plan contains 47 D1–D3 assignments and 405 D4–D30 assignments.

7. **Exact D4–D30 date mapping.** The programme retains its 22 August start date and uses explicit offsets:

   | Day | Date | Day | Date | Day | Date |
   |---:|---|---:|---|---:|---|
   | 4 | 31 Aug | 13 | 15 Sep | 22 | 29 Sep |
   | 5 | 1 Sep | 14 | 16 Sep | 23 | 30 Sep |
   | 6 | 2 Sep | 15 | 18 Sep | 24 | 2 Oct |
   | 7 | 4 Sep | 16 | 19 Sep | 25 | 5 Oct |
   | 8 | 7 Sep | 17 | 21 Sep | 26 | 6 Oct |
   | 9 | 8 Sep | 18 | 22 Sep | 27 | 7 Oct |
   | 10 | 9 Sep | 19 | 23 Sep | 28 | 9 Oct |
   | 11 | 11 Sep | 20 | 25 Sep | 29 | 12 Oct |
   | 12 | 14 Sep | 21 | 28 Sep | 30 | 14 Oct |

8. **D4–D30 focus list.**

   | Day | Focus | Day | Focus |
   |---:|---|---:|---|
   | 4 | Graphs + existing error repair | 18 | CSAT + STEP/MAT + small BMO |
   | 5 | Calculus, area + interpretation | 19 | Official TMUA 2018 Paper 1 |
   | 6 | Statistics + probability foundations | 20 | Official TMUA 2018 Paper 2 |
   | 7 | Third-party Paper 1 diagnostic | 21 | Official TMUA 2019 full simulation |
   | 8 | Paper 2 logic foundations | 22 | Simulation analysis + light CSAT |
   | 9 | CSAT introduction | 23 | Hard Paper 2 mastery |
   | 10 | Geometry, coordinate geometry + trig repair | 24 | SMC/BMO + CSAT reasoning |
   | 11 | Third-party Paper 2 diagnostic | 25 | Official TMUA 2020 Paper 1 |
   | 12 | Number, ratio + bounds | 26 | Official TMUA 2020 Paper 2 |
   | 13 | Functions, graphs + recurrences | 27 | Error repair + exam efficiency |
   | 14 | Statistics + probability intensive | 28 | Official TMUA 2021 full simulation |
   | 15 | Official TMUA 2017 Paper 1 | 29 | Final targeted repair |
   | 16 | Official TMUA 2017 Paper 2 | 30 | Final consolidation + strategy |
   | 17 | Benchmark analysis + repair |  |  |

9. **D7 diagnostic.** Euclid R2DREW2 Paper 1 (`SRC-E29687FAAA262C5F`), 20 questions. It is a coherent, representative, unattempted local paper with verified-page solution support and is not an official future benchmark or deliberately extreme JZ material.

10. **D11 diagnostic.** Euclid Sample Paper 2 (`SRC-D475EB66A3CA6BF0`), 20 questions. It provides representative logic/reasoning coverage with local verified-page support without using a challenge set as the baseline diagnostic.

11. **Official benchmark mappings.** 2017 P1→D15, 2017 P2→D16, 2018 P1→D19, 2018 P2→D20, both 2019 papers→D21, 2020 P1→D25, 2020 P2→D26, and both 2021 papers→D28. Each paper contributes its complete 20-question set.

12. **Question counts by programme day.** D1–D30: `16, 16, 15, 12, 10, 12, 20, 10, 4, 12, 20, 12, 10, 14, 20, 20, 10, 5, 20, 20, 40, 8, 12, 10, 20, 20, 10, 40, 8, 6`.

13. **Expected minutes by programme day.** Values are question/review/total minutes:

   | Day | Minutes | Day | Minutes | Day | Minutes |
   |---:|---:|---:|---:|---:|---:|
   | 1 | 79/35/114 | 11 | 75/75/150 | 21 | 150/90/240 |
   | 2 | 77/35/112 | 12 | 75/40/115 | 22 | 60/75/135 |
   | 3 | 71/35/106 | 13 | 85/45/130 | 23 | 90/55/145 |
   | 4 | 90/45/135 | 14 | 95/50/145 | 24 | 85/55/140 |
   | 5 | 75/45/120 | 15 | 75/75/150 | 25 | 75/75/150 |
   | 6 | 85/40/125 | 16 | 75/75/150 | 26 | 75/75/150 |
   | 7 | 75/75/150 | 17 | 70/55/125 | 27 | 70/50/120 |
   | 8 | 70/50/120 | 18 | 100/45/145 | 28 | 150/90/240 |
   | 9 | 95/45/140 | 19 | 75/75/150 | 29 | 55/55/110 |
   | 10 | 85/45/130 | 20 | 75/75/150 | 30 | 35/55/90 |

14. **Assignments by stream.** Across D4–D30, canonical primary streams are TMUA 350, CSAT 10, SMC 16, BMO 3 and honest nil-primary crossover 26. Intended-use membership is TMUA 376, CSAT 14, SMC 16, BMO 3 and Cambridge-CS-interview 4; intended-use totals overlap by design.

15. **CSAT integration.** Ten primary CSAT questions plus four additional CSAT-intended crossover questions are deliberately placed in D9, D13, D18, D22 and D24. Sessions require decomposition, think-aloud explanation, adaptation and reflection rather than another MCQ block.

16. **SMC integration.** Sixteen SMC questions are used as bounded speed/observation/counting segments on D6, D12, D14 and D24; they never displace the TMUA core.

17. **BMO integration.** Three BMO questions are used only in D18 and D24 for proof structure and multi-step explanation. No full BMO paper is assigned.

18. **Interview crossover.** Four explicitly interview-intended questions, plus selected CSAT, STEP and MAT work, introduce explaining aloud, stating assumptions, reacting to hints and summarising arguments. No premature standalone interview syllabus was created.

19. **Weak-area repair.** D4/D5/D10/D14 directly address graph sketching, transformations, signed area, trig values/periods, coordinate geometry and statistics/probability. D8/D23 address Paper 2 logical form and approach recognition. D17/D27/D29 repair knowledge, approach, careless and algebra error classes and train abandon/return decisions.

20. **Needs Review/Redo handling.** The 5 Needs Review and 2 Redo states from the live snapshot are preserved. Current repair candidates seed D4, D17 and D29 deterministically; migration creates no fake outcome. Later benchmark-driven changes require an explicit future plan refresh because the migration intentionally does not implement an opaque adaptive planner.

21. **Benchmark protection.** The ten official 2017–2021 papers are excluded from automatic practice before their exact scheduled calendar date and unlock on that date. Tests exercise the day-before and scheduled-day policy for every paper.

22. **TMUA 2022 protection.** All 40 questions remain permanently protected, are absent from every programme day, and remain excluded from Extra Practice.

23. **Flex-day validation.** 5 Sep, 12 Sep, 26 Sep, 3 Oct, 10 Oct and 13 Oct map to no programme day. Sundays, Thursdays and 15 Oct also have no mandatory day. Automated tests prove there is no D30 fallback; simulator QA on 3 Sep, 5 Sep, 13 Oct and 15 Oct displayed “No Mandatory Programme Work Today.”

24. **Tuesday restriction.** D5, D9, D13, D18, D22 and D26 use `earliestStartMinute = 840`. Simulator QA for 1 Sep showed “Programme Available After 14:00” at 13:00 and exposed Day 5 at 14:30.

25. **D1–D3 fingerprint.** Unchanged: `326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e`. Assignment IDs and the 16/16/15 completions are byte-for-byte preserved.

26. **Attempts before/after.** 48 → 48. The attempt-table logical digest remains `d306e1bcec9393636925bbac62bb6993c38f7746c77a5d464de27f5914ff0234`.

27. **Sessions/results before/after.** Sessions 3 → 3; results 0 → 0. Session digest remains `9ec5b56cb99f4d82e18007d6794fb607e7081d336348ae0f230a5db5669bf37f`. No benchmark was marked complete and no fake result was created.

28. **Questions/sources/solutions before/after.** The immediate phone snapshot was still on its pre-Chunk-3 catalogue: 1,573/80/68 with 1,358 links. The isolated production seed first applied the already-approved, unchanged Chunk-3 bundle, yielding 2,600/136/120 with 2,364 links; Chunk 4 itself adds no corpus import or broad reclassification. Catalogue and solution manifest SHA-256 values remain `1b367c65c900d68b36f84cf0b23a4212390b619719eb61c38720124b4879b3b2` and `7f50ac29d45befca2d0153388bbf57f40158e39269ea0e05b2012f329e66556e`.

29. **Database digest before/after.** Immediate snapshot logical digest: `69ec06fbec136904eaf92b26197943e050b2e07d7693a2a6ae8797463e436087`. Migrated sandbox after the approved Chunk-3 seed plus Chunk-4 programme migration: `ce72c9462a06d2ba5b23a92bc1c34739c5dfba73b8ec7256749cd0db0667df94`. Change is expected for catalogue/programme tables; attempts, sessions, results, settings, blocks, subjects, modules, topics and timers retain identical table digests. SQLite `integrity_check` returns `ok`.

30. **Idempotency.** The production seed and programme migration were run twice against the paired-iPhone copy. Catalogue and assignment signatures were identical after run one and run two; no duplicate programme, day, assignment or protection record appeared.

31. **Swift tests.** 122 tests executed, 0 failures, 0 unexpected failures. The final test result bundle is `/Users/kushagra/Library/Developer/Xcode/DerivedData/revisr-acrokdwyyuijjrgznuvzhviwxfsm/Logs/Test/Test-revisr-2026.08.31_20-37-48-+0100.xcresult`.

32. **Python/resource tests.** 14 tests executed, all passed. These cover atomic generation, complete Chunk-3 corpus/resource integrity, D1–D3 byte equivalence, exact diagnostics/benchmarks, flex and Tuesday dates, repeat policy and workload/stream integration.

33. **Release build.** Release build for generic iOS Simulator succeeded with code signing disabled. The Debug-only QA clock is compiled out of Release behavior.

34. **Manual QA.** Passed on iPhone 17 Pro simulator. Inspected Today D4; Plan D5, D7, D11, D15, D21, D24, D28 and D30; Tuesday before/after 14:00; unavailable Thursday; 5 Sep flex; 13 Oct contingency; and 15 Oct rest. Labels, question counts, dates, briefs and durations were coherent. There was no giant overdue backlog, duplicate active assignment, guilt copy or D30 fallback.

35. **Remaining issues requiring a decision.** None within Chunk 4. The paired iPhone has deliberately not been modified, so it still holds the older on-device catalogue and programme until explicit approval for the physical-device/Chunk-5 step. Approving that later step will apply the already-approved Chunk-3 additive seed and this Chunk-4 migration together while preserving the audited history.

