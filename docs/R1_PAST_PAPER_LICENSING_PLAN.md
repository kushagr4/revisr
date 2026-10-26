# R1 past and mock paper licensing plan

**Status (26 October 2026): no past or mock paper content has permission for in-app use. Nothing in this milestone changes that.** The public diagnostic stays blocked (`TMUAContentPolicy.publicAllowsOriginalOnlyDiagnostic = false`) until either licensed content exists or you decide to allow an original-only diagnostic.

This plan inventories the historical resource library, summarises what each rights holder publishes about reuse, and sets out what Revisr would ask for. It is not legal advice. Rights-holder summaries paraphrase each organisation's published pages as read on 26 October 2026; check them again before relying on them. Permission-request drafts are in the private content workspace (`rights/requests/`) and have not been sent.

## What Revisr would reproduce

A request should describe the use precisely:

- **Questions:** individual multiple-choice questions (stem, options, any diagram redrawn natively), never whole papers or the original PDFs.
- **Answer keys:** used to mark answers automatically.
- **Solutions:** either the rights holder's worked solutions or short solutions written by Revisr. These need separate permission, because a solution is a separate work.
- **Placement:** the diagnostic and practice, mixed with original Revisr questions. Each item carries a source label ("Licensed past examination question" or "Licensed mock paper question") and the holder's attribution text (`TMUAContentSource.attribution`). The student-visible distinction between original and past/mock items is preserved.
- **Distribution:** a commercial iOS app on the App Store, stored on the student's device. No web publication.
- **Rights fields per item:** `inAppUse`, `redistribution`, `commercialUse`, `answerKey` and `solution`, each with its own state. The build gate requires all five to be `cleared`, and the source URL and attribution to be present (`Scripts/assemble_tmua_content.py`, `TMUAContentPolicy`).

**Linking instead of reproducing.** The app may link to a rights holder's own public page (for example the official preparation-materials page), opening it in Safari. A link reproduces nothing, so it needs no permission. Only the holder's own page should be linked, not a third-party re-host.

## Rights holders: published terms and recommended route

| Rights holder | Library sources | Questions indexed | What their published terms say (paraphrased) | Route | Priority |
|---|---:|---:|---|---|---|
| **UAT-UK** (TMUA papers, specimen, practice, specification; older papers first published by Cambridge Assessment Admissions Testing, © UCLES) | 16 | 300 | Website terms: view, download and print for personal use only; no direct or indirect commercial use without express written permission; no modification; credit UAT-UK and contributors as authors. Preparation materials carry no separate licence. No published permissions process. Older UCLES papers not addressed. Pages read: esat-tmua.ac.uk/website-terms-of-use/, /tmua-preparation-materials/, /enquiries/ | Request a written licence (draft 01). Until granted, link to the official preparation page only. Ask who holds rights in UCLES-era papers. | **1** — most relevant content |
| **OCR / Cambridge University Press & Assessment** (STEP papers, hints and solutions, examiner reports; © UCLES) | 13 | 163 | Approved centres may reproduce past papers and mark schemes for in-centre teaching, unaltered and free. Otherwise no commercial exploitation, and copying or redistribution needs prior written consent. Cambridge terms forbid scraping or storing content in a database. Route: ocr.copyright@ocr.org.uk. Pages read: ocr.org.uk copyright policy and terms; cambridge.org/legal | STEP is not TMUA-format; link only. Request (draft 02) only if STEP practice becomes a product goal. | 3 |
| **University of Oxford** (MAT papers and mark schemes) | 15 | 240 | Copyright held by the department, University or licensors; unlawful copying prohibited. Commercial and app use not addressed; no permissions process (contact form only). The MAT page says the MAT will not run from 2026. Pages read: maths.ox.ac.uk MAT page, ox.ac.uk/legal | MAT multiple-choice questions are useful TMUA practice. Request (draft 02) or link. | 2 |
| **UK Mathematics Trust** (SMC, IMC, BMO, Maclaurin, Senior Kangaroo) | 39 | 753 | UKMT claims copyright in its papers. A single question with its solution may be discussed publicly, and schools may use the videos. Covering all or most of a paper, or a topic across several years, in any public-facing medium (apps named) needs written permission from the Managing Director. Commercial use of official solutions needs permission. Pages read: bmos.ukmt.org.uk usage note, ukmt.org.uk policies and papers pages | Mainly SMC/BMO preparation, not TMUA. Link only for TMUA; request (draft 02) if SMC/BMO return as a product. | 4 |
| **University of Cambridge / Climb Foundation** (CSAT sample tests) | 4 | 80 | University terms: personal, non-commercial printing only; no commercial use without a licence. The samples are now hosted by the Climb Foundation, whose usage page says nothing about reuse; ownership is unclear. | Drop from the TMUA product; link only if needed. | 5 |
| **TMUA.fyi** (challenge sets; also re-hosts other authors' papers) | 4 | 80 | Private-study licence only; no sharing, resale, scraping or competing product. Operator not named; challenge papers have no author credit. | Do not use. Authorship cannot be established. | — |
| **Independent mock authors** with published terms: JZ Maths (Joe Zhou), MioMath, TMUA Euclid (incl. Ascent and the cheat sheet), TMUA.co.uk (Uni Admissions Prep Ltd), Tyler Tutoring (Jacqueline Tyler; topic bank and the "TMUA Mock" sets A–D, which the library's solution metadata attributes to Tyler Tutoring) | 27 | 644 | Each states personal, non-commercial use only and requires written permission for reproduction or redistribution. JZ Maths states it uses CAAT past papers under fair dealing, so some of its content may itself be third-party. Contacts are on each author's own terms or contact page. | Request individually (draft 03), only for papers the author confirms are wholly theirs. | 3 |
| **Independent authors without published terms or contact**: Beyond Horizon, Yotta, Zetta, Zack, Rosie, James Chen, Asher Falcon, DπD Maths, sed, and the "9.0 TMUA Handbook" reference | 18 | 340 | Nothing published. Beyond Horizon's domain redirected to an unrelated "browser verification" site on 26 October 2026. | Do not use. Do not contact through the redirecting domain. | — |

Totals: 136 sources and 2,600 indexed question units in `revisr/Resources/AdmissionsManifest.json`; 120 solution documents in `AdmissionsSolutionsManifest.json`; 8 solution videos.

### Per-source rights status

Every source in the library currently has the same status:

| Field | Status for every source |
|---|---|
| In-app reproduction | **Not permitted.** No permission or licence is held. |
| Redistribution | Not permitted. |
| Commercial use | Not permitted. |
| Answer-key use | Not permitted. Keys are part of the rights holder's work. |
| Solution use | Not permitted. Solutions are separate works with their own rights. |
| Attribution requirement | Known for UAT-UK (credit UAT-UK and contributors) and OCR (keep copyright notices). Unknown elsewhere; to be set in each licence. |
| Distribution in Release builds | **Excluded.** The Release build strips all 242 PDFs and videos and bundles no third-party questions (`R1_RELEASE_READINESS.md`). |
| Present in Debug builds | Yes. The legacy personal programme and the SMC/BMO PDF diagnostics use them. |
| Public Git history | Yes, since the initial commit `ae50956` (2 September 2026). See `R1_RELEASE_READINESS.md` §Git history exposure. |

The appendix lists every source with its family, year, paper, indexed questions and solutions held.

## Solution videos

The 8 bundled MP4 files (`revisr/Resources/AdmissionsVideos`, 314 MB) correspond to `tmp/videos/chunk3` thumbnails whose filenames show they were saved with a YouTube downloader (for example `YTDown.com_YouTube_…`). Redistributing downloaded YouTube videos needs the creator's permission, and downloading itself conflicts with YouTube's terms. Recommendation: stop bundling them in every configuration, and link to each creator's own video page instead.

## Steps before any licensed item can ship

1. You decide which holders to approach (recommended order: UAT-UK, then Oxford MAT, then individual authors with clear sole authorship).
2. You send the requests yourself. Revisr software makes no rights claims.
3. Record each written grant in the private workspace (`rights/grants/<holder>.md`): scope, territories, fees, attribution wording, solution terms, term and expiry, and the person granting it.
4. Enter licensed items in the private bank: category `licensed_past_paper` or `licensed_mock`, `source` (organisation, year, paper, question number, URL, attribution) and rights fields set to `cleared` only within the grant's scope. Record the rights decision in the review register (`tools/review_workflow.py record … rights cleared --reviewer "<name>"`).
5. Human mathematical review of each item version (keys can be wrong in source papers too), then publication approval.
6. The build gate (`assemble_tmua_content.py`, `TMUAContentPolicy`) admits only items with all five rights cleared, human mathematical review, publication approval and a source URL and attribution.

## Appendix: per-source inventory

Generated from `AdmissionsManifest.json` and `AdmissionsSolutionsManifest.json` (metadata only; no question text). "Earlier use rule" is the legacy app's scheduling rule, not a rights status.

### UK Mathematics Trust

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| BMO | bmo-1975 | 1975 | — | 8 | — | - |
| BMO | bmo-1976 | 1976 | — | 6 | — | - |
| BMO | bmo1-2014 | 2014 | — | 6 | — | - |
| BMO | bmo1-2015 | 2015 | — | 6 | — | - |
| BMO | bmo1-2016 | 2016 | — | 6 | — | - |
| BMO | bmo1-2017 | 2017 | — | 6 | — | - |
| BMO | bmo1-2018 | 2018 | — | 6 | — | - |
| BMO | bmo1-2019 | 2019 | — | 6 | — | - |
| BMO | bmo1-2020 | 2020 | — | 6 | — | - |
| BMO | bmo1-2021 | 2021 | — | 7 | — | - |
| BMO | bmo1-2022 | 2022 | — | 6 | — | - |
| BMO | bmo1-2023 | 2023 | — | 6 | — | - |
| BMO | bmo1-2024 | 2024 | — | 6 | — | - |
| BMO | bmo1-2025 | 2025 | — | 6 | — | - |
| BMO | bmo1-2026 | 2026 | — | 6 | — | - |
| IMC | IMC-2015-q | 2015 | — | 25 | workedSolution | - |
| IMC | IMC-2016-q | 2016 | — | 25 | workedSolution | - |
| IMC | IMC-2017-q | 2017 | — | 25 | workedSolution | - |
| IMC | IMC-2018-q | 2018 | — | 25 | workedSolution | - |
| IMC | IMC-2019-q | 2019 | — | 25 | workedSolution | - |
| IMC | IMC-2020-q | 2020 | — | 25 | workedSolution | - |
| IMC | IMC-2021-q | 2021 | — | 25 | workedSolution | - |
| IMC | IMC-2023-q | 2023 | — | 25 | workedSolution | - |
| IMC | IMC-2024-q | 2024 | — | 25 | workedSolution | - |
| IMC | IMC-2025-q | 2025 | — | 25 | workedSolution | - |
| Maclaurin | maclaurin-2010-2014 (page 12) | — | 2010-2014 | 30 | combinedQuestionsAndSolutions | - |
| SMC | smc-2013-q | 2013 | — | 25 | solutionsAndInvestigations | - |
| SMC | SMC-2017-paper | 2017 | — | 25 | workedSolution | - |
| SMC | SMC2018_paper | 2018 | — | 25 | workedSolution | - |
| SMC | SMC_2019_Paper | 2019 | — | 25 | workedSolution | - |
| SMC | SMC_2020qp | 2020 | — | 25 | workedSolution | - |
| SMC | SMC_2021_paper | 2021 | — | 25 | workedSolution | - |
| SMC | SMC-2022-Paper | 2022 | — | 25 | workedSolution | - |
| SMC | SMC-2023-Paper | 2023 | — | 25 | workedSolution | - |
| SMC | SMC-2024-Paper | 2024 | — | 25 | workedSolution | - |
| SMC | SMC_2025_paper | 2025 | — | 25 | workedSolution | - |
| SMC | A4SMC_QP16 | — | — | 25 | workedSolution | - |
| SMC | SMC15_QP_A4 | — | — | 25 | workedSolution | - |
| Senior Kangaroo | sk-2011-2014-(page 22) | — | 2011-2014 | 80 | combinedQuestionsAndSolutions | - |

### University of Oxford

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| MAT | MAT 2007 | 2007 | — | 16 | markScheme | - |
| MAT | MAT 2008 | 2008 | — | 16 | markScheme | - |
| MAT | MAT 2010 | 2010 | — | 16 | markScheme | - |
| MAT | MAT 2011 | 2011 | — | 16 | markScheme | - |
| MAT | MAT 2014 | 2014 | — | 16 | markScheme | - |
| MAT | MAT 2015 | 2015 | — | 16 | markScheme | - |
| MAT | MAT 2016 | 2016 | — | 16 | markScheme | - |
| MAT | MAT 2017 | 2017 | — | 16 | markScheme | - |
| MAT | MAT 2018 | 2018 | — | 16 | markScheme | - |
| MAT | MAT 2019 | 2019 | — | 16 | markScheme | - |
| MAT | MAT 2020 | 2020 | — | 16 | markScheme | - |
| MAT | MAT 2021 | 2021 | — | 16 | markScheme | - |
| MAT | MAT 2022 | 2022 | — | 16 | markScheme | - |
| MAT | MAT Specimen 1 | — | Specimen 1 | 16 | markScheme | - |
| MAT | MAT Specimen 2 | — | Specimen 2 | 16 | markScheme | - |

### Cambridge University Press & Assessment (UCLES); administered by OCR

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| STEP | STEP 2013 Paper 1 | 2013 | STEP I | 13 | — | Local private question source |
| STEP | STEP 2014 Paper 1 | 2014 | STEP I | 13 | hintsAndSolutions | Local private question source |
| STEP | STEP 2015 Paper 1 | 2015 | STEP I | 13 | hintsAndSolutions | Local private question source |
| STEP | STEP 2016 Paper 1 | 2016 | STEP I | 13 | hintsAndSolutions | Local private question source |
| STEP | STEP 2017 Paper 1 | 2017 | STEP I | 13 | hintsAndSolutions | Local private question source |
| STEP | STEP 2017 Paper 2 | 2017 | STEP II | 13 | hintsAndSolutions | Local private question source |
| STEP | STEP 2018 Paper 1 | 2018 | STEP I | 13 | hintsAndSolutions | Local private question source |
| STEP | STEP 2018 Paper 2 | 2018 | STEP II | 13 | hintsAndSolutions | Local private question source |
| STEP | STEP 2019 Paper 1 | 2019 | STEP I | 11 | hintsAndSolutions | Local private question source |
| STEP | STEP 2019 Paper 2 | 2019 | STEP II | 12 | hintsAndSolutions | Local private question source |
| STEP | STEP 2020 Paper 2 | 2020 | STEP II | 12 | examinerReport, workedSolution | Local private question source |
| STEP | STEP 2021 Paper 2 | 2021 | STEP II | 12 | markScheme | Local private question source |
| STEP | STEP 2022 Paper 2 | 2022 | STEP II | 12 | examinerReport | Local private question source |

### UAT-UK / Cambridge University Press & Assessment (UCLES)

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| TMUA Actual | TMUA 2017 Paper 1 | 2017 | Paper 1 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2017 Paper 2 | 2017 | Paper 2 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2018 Paper 1 | 2018 | Paper 1 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2018 Paper 2 | 2018 | Paper 2 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2019 Paper 1 | 2019 | Paper 1 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2019 Paper 2 | 2019 | Paper 2 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2020 Paper 1 | 2020 | Paper 1 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2020 Paper 2 | 2020 | Paper 2 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2021 Paper 1 | 2021 | Paper 1 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2021 Paper 2 | 2021 | Paper 2 | 20 | workedSolution | Scheduled only as full timed paper |
| TMUA Actual | TMUA 2022 Paper 1 | 2022 | Paper 1 | 20 | workedSolution | Preserve — not scheduled |
| TMUA Actual | TMUA 2022 Paper 2 | 2022 | Paper 2 | 20 | workedSolution | Preserve — not scheduled |

### University of Cambridge, Dept of Computer Science and Technology

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| CSAT | CSAT sample-test-1 | — | Sample 1 | 20 | — | - |
| CSAT | CSAT sample-test-2 | — | Sample 2 | 20 | — | - |
| CSAT | CSAT sample-test-3 | — | Sample 3 | 20 | — | - |
| CSAT | CSAT sample-test-4 | — | Sample 4 | 20 | — | - |

### UAT-UK / UCLES

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| TMUA Practice | TMUA Practice Paper 1 | — | Paper 1 | 20 | workedSolution | - |
| TMUA Practice | TMUA Practice Paper 2 | — | Paper 2 | 20 | workedSolution | - |
| TMUA Specimen | TMUA Specimen Paper 1 | — | Paper 1 | 20 | workedSolution | - |

### UAT-UK

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Specification | TMUA_Content_Specification(1) | — | — | 0 | — | - |

### Independent author: JZ Maths TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| JZ Maths TMUA Mock | JZ Maths Set A Paper 1 | 2026 | Set A Paper 1 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set A Paper 2 | 2026 | Set A Paper 2 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set B Paper 1 | 2026 | Set B Paper 1 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set B Paper 2 | 2026 | Set B Paper 2 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set C Paper 1 | 2026 | Set C Paper 1 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set C Paper 2 | 2026 | Set C Paper 2 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set D Paper 1 | 2026 | Set D Paper 1 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set D Paper 2 | 2026 | Set D Paper 2 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set E Paper 1 | 2026 | Set E Paper 1 | 20 | workedSolution | Local private question source |
| JZ Maths TMUA Mock | JZ Maths Set E Paper 2 | 2026 | Set E Paper 2 | 20 | workedSolution | Local private question source |

### Independent author: Beyond Horizon TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Beyond Horizon TMUA Mock | Beyond Horizon Set 1 Paper 1 | — | Set 1 Paper 1 | 20 | — | Local private question source |
| Beyond Horizon TMUA Mock | Beyond Horizon Set 1 Paper 2 | — | Set 1 Paper 2 | 20 | — | Local private question source |
| Beyond Horizon TMUA Mock | Beyond Horizon Set 2 Paper 1 | — | Set 2 Paper 1 | 20 | — | Local private question source |
| Beyond Horizon TMUA Mock | Beyond Horizon Set 2 Paper 2 | — | Set 2 Paper 2 | 20 | — | Local private question source |
| Beyond Horizon TMUA Mock | Beyond Horizon Set 3 Paper 1 | — | Set 3 Paper 1 | 20 | — | Local private question source |
| Beyond Horizon TMUA Mock | Beyond Horizon Set 3 Paper 2 | — | Set 3 Paper 2 | 20 | — | Local private question source |
| Beyond Horizon TMUA Mock | Beyond Horizon Set 4 Paper 1 | — | Set 4 Paper 1 | 20 | — | Local private question source |

### Independent authors: "TMUA Mock" family (sets A–D attributed to Tyler Tutoring; Yotta papers 1 and 2)

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| TMUA Mock | TMUA Mock A | 2026 | Set A | 40 | combinedQuestionsAndSolutions | - |
| TMUA Mock | TMUA Mock B | 2026 | Set A | 40 | combinedQuestionsAndSolutions | - |
| TMUA Mock | TMUA Mock Set C | 2026 | Set A | 40 | combinedQuestionsAndSolutions | - |
| TMUA Mock | TMUA Mock Set D | 2026 | Set A | 40 | combinedQuestionsAndSolutions | - |
| TMUA Mock | Yotta TMUA Paper 1 | — | Yotta Paper 1 | 20 | videoSolution | - |
| TMUA Mock | Yotta_P2_QP | — | Yotta Paper 2 | 20 | videoSolution | - |

### Independent author: Tyler Topic Bank

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Tyler Topic Bank | Jacqueline Tyler Logic and Proof | 2026 | Logic and Proof | 25 | videoSolution | Local private question source |
| Tyler Topic Bank | Tyler Abstract Functions | 2026 | Abstract Functions | 15 | workedSolution | Local private question source |
| Tyler Topic Bank | Tyler Combinatorics | 2026 | Combinatorics | 50 | workedSolution | Local private question source |
| Tyler Topic Bank | Tyler Modulus Functions | 2026 | Modulus | 20 | workedSolution | Local private question source |
| Tyler Topic Bank | Tyler Number Theory | 2026 | Number Theory | 31 | workedSolution | Local private question source |
| Tyler Topic Bank | Tyler Statistics and Probability | 2026 | Statistics and Probability | 16 | workedSolution | Local private question source |

### Independent author: TMUA.fyi Challenge

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| TMUA.fyi Challenge | TMUA.fyi Challenge Set 1 Paper 1 | 2026 | Challenge Set 1 Paper 1 | 20 | combinedQuestionsAndSolutions | Local private question source |
| TMUA.fyi Challenge | TMUA.fyi Challenge Set 1 Paper 2 | 2026 | Challenge Set 1 Paper 2 | 20 | combinedQuestionsAndSolutions | Local private question source |
| TMUA.fyi Challenge | TMUA.fyi Challenge Set 2 Paper 1 | 2026 | Challenge Set 2 Paper 1 | 20 | combinedQuestionsAndSolutions | Local private question source |
| TMUA.fyi Challenge | TMUA.fyi Challenge Set 2 Paper 2 | 2026 | Challenge Set 2 Paper 2 | 20 | combinedQuestionsAndSolutions | Local private question source |

### Independent author: MioMath TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| MioMath TMUA Mock | MioMath 2024 Paper 1 | 2024 | Paper 1 | 20 | answerKey | Local private question source |
| MioMath TMUA Mock | MioMath 2024 Paper 2 | 2024 | Paper 2 | 20 | answerKey | Local private question source |

### Independent author: sed TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| sed TMUA Mock | sed TMUA Mock Paper 1 | — | Paper 1 | 20 | answerKey | Local private question source |
| sed TMUA Mock | sed TMUA Mock Paper 2 | — | Paper 2 | 20 | answerKey | Local private question source |

### Reference documents (TMUA Euclid cheat sheet; The 9.0 TMUA Handbook)

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Reference | The 9.0 TMUA Handbook | 2026 | — | 0 | — | Reference only; does not create questions |
| Reference | TMUA Euclid Cheat Sheet | — | — | 0 | — | Reference only; does not create questions |

### Independent author: R2DREW2 / TMUA Euclid

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| R2DREW2 / TMUA Euclid | TMUA Euclid R2DREW2 Paper 1 | 2026 | Paper 1 | 20 | markScheme | Local private question source |

### Independent author: TMUA Euclid

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| TMUA Euclid | TMUA Euclid Sample Paper 2 | 2026 | Paper 2 | 20 | markScheme | Local private question source |

### Independent author: Asher Falcon TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Asher Falcon TMUA Mock | Asher Falcon TMUA Paper 1 | — | Paper 1 | 20 | videoSolution | Local private question source |

### Independent author: TMUA Euclid Ascent

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| TMUA Euclid Ascent | Euclid Ascent: Algebra and Functions | 2026 | Algebra and Functions | 27 | markScheme | Local private question source |

### Independent author: Zetta TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Zetta TMUA Mock | Zetta TMUA Paper 1 | — | Paper 1 | 20 | answerKey, videoSolution | Local private question source |

### Independent author: Zack TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Zack TMUA Mock | Zack TMUA Mock Paper 1 | — | Paper 1 | 20 | answerKey, videoSolution | Local private question source |

### Independent author: James Chen TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| James Chen TMUA Mock | James Chen TMUA Paper | — | Mixed paper | 20 | combinedQuestionsAndSolutions, videoSolution | Local private question source |

### Independent author: DπD Maths TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| DπD Maths TMUA Mock | DπD Maths Mock Set 1 Paper 1 | 2026 | Set 1 Paper 1 | 20 | workedSolution | Local private question source |

### Independent author: Rosie TMUA Mock

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| Rosie TMUA Mock | Rosie Set A Paper 1 | — | Set A Paper 1 | 20 | videoSolution | Local private question source |

### Independent author: TMUA.co.uk R2Drew2

| Family | Source | Year | Paper | Questions indexed | Solutions held | Earlier use rule |
|---|---|---|---|---:|---|---|
| TMUA.co.uk R2Drew2 | TMUA.co.uk R2Drew2 Mock Paper 1 | 2026 | Paper 1 | 20 | answerKey, workedSolution | Local private question source |

