# Revisr Chunk 3 Import Audit

Completed: 31 August 2026

Scope: authoritative resource, question, solution, video, duplicate, and preparation-stream import only. The D4-D30 programme was not rebuilt and no physical-device installation was performed.

## 1-14. Inventory and questions

1. **Final supplied-file inventory:** 96 files: 88 PDFs and 8 MP4 videos, totalling 391,859,951 bytes. The complete per-file inventory, including SHA-256, normalized-text checksum, role, provider, family, page/duration, question count, and import decision, is in `.qa/chunk3/staging-v1/CorpusInventory.json` and `.qa/chunk3/staging-v1/CorpusInventory.md`.
2. **Logical resources:** 96. Every supplied file has one logical classification; none is unclassified.
3. **Duplicates:** no exact binary duplicate groups. The only normalized-text match is `Combinatorics v2.pdf` / `Combinatorics v2 Answers.pdf`; visual inspection proved them distinct question and worked-answer resources.
4. **Existing resources reused:** the existing 80 sources, 68 solution documents, and 1,358 mappings remain stable. Existing Yotta Paper 1 and Paper 2 question sources/IDs were reused for their videos.
5. **New sources:** 56 (54 question sources and 2 reference sources), producing 136 total sources.
6. **Questions before:** 1,573.
7. **Genuinely new questions:** 1,027.
8. **Existing questions reused:** 40 Yotta questions.
9. **Questions after:** 2,600.
10. **Duplicates skipped:** 40 potential Yotta creations were skipped because their canonical existing IDs were reused.
11. **Possible duplicates flagged:** 0. No uncertain semantic merges were made.
12. **Invalid/unusable questions:** 0.
13. **Unresolved transcriptions:** 0. All 40 MioMath questions were visually readable; automated OCR was not treated as authoritative.
14. **Unresolved classifications:** 0 fully unclassified. 763 enrichment questions deliberately have no exclusive primary stream but do have intended-use metadata.

## 15-27. Classification, solutions, and special audits

15. **Primary preparation streams:** TMUA 1,364; CSAT 80; SMC 300; BMO 93; Cambridge CS Interview 0; primary nil with intended uses 763; fully unclassified 0.
16. **Intended uses:** TMUA 1,920; CSAT 348; SMC 300; BMO 93; Cambridge CS Interview 268. The TMUA total includes 61 historically assigned crossover questions whose honest canonical primary remains SMC/CSAT/BMO/nil while TMUA intended-use preserves compatibility with their existing programme assignments.
17. **New solution documents:** 52, producing 120 total.
18. **New question-solution mappings:** 1,006, producing 2,364 total.
19. **Video solutions:** 8 shared local video documents.
20. **Video/question mappings:** 165. Seven 20-question walkthroughs plus the 25-question Jacqueline Tyler logic walkthrough; no timestamps were invented.
21. **Pending/missing solutions:** 140 newly imported Beyond Horizon questions have no supplied local solution. Existing honest gaps remain unchanged.
22. **MioMath audit:** all 20 pages across the two image-only papers were rendered and inspected. Authorship remains MioMath; TMUA.fyi was supplementary identity/answer verification only.
23. **MioMath Paper 2 Q20:** usable. Squaring `3 cos x = sqrt(x)` yields five squared-equation roots, but only three satisfy the original sign constraint, so answer D is coherent.
24. **Combinatorics pair:** one 50-question Tyler topic source plus one visually distinct handwritten worked-answer overlay. Both carry `verifiedDistinct` duplicate-review metadata.
25. **Yotta reuse:** all 40 existing `YOTTA-P1/P2-Q01...Q20` IDs were retained; two shared videos were linked without creating questions.
26. **STEP:** 13 paper sources and 163 questions imported (STEP I: 89; STEP II: 74). Examiner reports create zero Question records. Multi-paper solution relationships use shared documents where applicable.
27. **External verification:** [TMUA.fyi](https://tmua.fyi/past-papers), the [official TMUA 2020 Paper 1](https://uat-wp.s3.eu-west-2.amazonaws.com/wp-content/uploads/2024/05/07140953/TMUA-2020-paper-1.pdf), and Oxford's public trigonometry explanation were consulted. Local supplied resources remain canonical.

## 28-40. Bundle, data safety, and validation

28. **Bundle size:** question/solution/video payload grew from 53,308,385 to 445,168,336 bytes, an exact increase of 391,859,951 bytes. The complete `Resources` tree grew from 56,319,954 to 450,409,451 bytes, an increase of 394,089,497 bytes; the extra 2,229,546 bytes beyond the supplied corpus are generated manifests, inventory/index metadata, and the import report. Videos were not transcoded or duplicated. The Release app contains exactly 234 PDFs and 8 MP4s, each copied once by Xcode.
29. **Files modified:** V2 admissions and solution manifests; bundled paper/solution/video directories and source index/import report; `EXTERNAL_RESOURCES.md`; deterministic generator, manifest finalizer, and resource tests; corpus sandbox-import test; legacy count assertions; this audit. Detailed generated inventory and staging evidence remain under `.qa/chunk3/`.
30. **Manifest file SHA-256:** admissions `bdc5d295dd152c655df4e683adcf375423d0ffbcd37780f7860ea74c1e46d7ad` -> `1b367c65c900d68b36f84cf0b23a4212390b619719eb61c38720124b4879b3b2`; solutions `bdb86489c6eb25d9bcafae7826a2130e4769e3776bffb116d152bdbcf4c462e2` -> `7f50ac29d45befca2d0153388bbf57f40158e39269ea0e05b2012f329e66556e`.
31. **Database logical SHA-256:** `8e32de14ae596fdec01ceab97fe7edf94a40fe4f3eb4f6cb47aa11ef9332cbf0` -> `4e4fd3216e0b80d3c73e45738be94184fb68628f32a5c5d955a7f1ad5b4bbae7`. Change is expected from catalogue expansion/reclassification; SQLite integrity is `ok` before and after. The final migrated copy is retained at `.qa/chunk3/post-import-final/Revisr.store`.
32. **Attempts:** 48 -> 48. Attempt IDs, question relationships, timestamps, outcomes, error types, notes, duration, and review state are unchanged.
33. **Assignments:** 530 -> 530. Assignment IDs, question/day relationships, display order, and completion are unchanged.
34. **D1-D3 fingerprint:** `326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e`, unchanged. Completion remains D1 16, D2 16, D3 15.
35. **TMUA 2022 protection:** 40 before and after.
36. **Subjects:** TMUA active; Mathematics inactive; Further Mathematics inactive in the audited migrated store.
37. **Swift tests:** 119 passed, 0 failed in the clean full iOS Simulator suite. The final retained migrated-store import test also passed separately and confirmed repeat-import idempotency.
38. **Python/resource tests:** 8 passed, 0 failed. Includes atomic failure preservation, identifiers, relationships, checksums, resource uniqueness, page/time validity, special decisions, programme history, and protection.
39. **Release build:** succeeded for generic iOS Simulator with `CODE_SIGNING_ALLOWED=NO`. Simulator launch then confirmed the 2,600-question bank, 136/136 source-paper availability, 74/32/27 solution coverage, 2,364 mappings, and working local PDF/video rendering.
40. **Remaining decisions:** none required for Chunk 3. The 140 Beyond Horizon questions honestly remain without local solutions. Programme scheduling/rebuild belongs to Chunk 4 and was intentionally not started.

## Representative manual record checks

Records from JZ P1/P2, MioMath P1/P2, Beyond Horizon, Euclid/R2DREW2, Rosie, Yotta, Tyler Combinatorics, TMUA.fyi Challenge, STEP I/II, SMC, BMO, and CSAT were checked for stable source/question identity, page, topic, primary/intended stream, solution/video relationship, protection, and duplicate state. Representative PDFs were rendered and all eight video thumbnails/durations were inspected during the corpus audit. The final app was also inspected interactively in iPhone Simulator: Question Bank filters and counts, Solution Bank coverage, Source Papers, a source PDF, and local MP4 playback all rendered correctly. Canonical stream, nil-primary/intended-use, invalid eligibility, and protection behaviour were inspected through the migrated SwiftData/export assertions because the current UI does not expose canonical preparation stream as an end-user filter.
