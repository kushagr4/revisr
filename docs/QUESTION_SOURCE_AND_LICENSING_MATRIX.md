# Question source and licensing matrix

Status on 26 October 2026. **No third-party source has granted permission for Revisr to reproduce its questions, answer keys or solutions.** Revisr being free to students does not change that: free access and attribution are not a licence, and a public PDF link is not an open licence. Nothing below is legal advice. Provider terms are paraphrased from their own pages as read on R1 (26 October 2026) and re-checked where noted; check them again before relying on them.

The machine-readable form of this matrix is `revisr/Resources/TMUAResourceProviders.json`, which the app uses to decide what each build shows.

## Access categories

| Category | Meaning | Where it appears |
|---|---|---|
| **A. Approved in-app content** | Revisr may reproduce it (original questions after human review, or licensed questions within the grant) | Public and development builds, after the publication gate. **Empty today:** 0 approved items. |
| **B. Private development resources** | Held by the owner for personal study and internal development | Development (Debug) builds on the owner's device only, labelled "personal study copy". Never in Release builds or public Git history. |
| **C. External resources** | Freely offered by the provider on its own site, not licensed for redistribution | Listed with credit and a link to the provider's page. Students mark their own work. |
| **D. Restricted** | Premium, unclear ownership, personalised or prohibited | Never in public builds. Development builds may still open the owner's own copy as B. |

## Matrix

| Provider | Library sources (questions) | Public access in Revisr | Link (verified 26 Oct 2026) | What their terms say | Permission | Draft request |
|---|---|---|---|---|---|---|
| UAT-UK (© UCLES): TMUA 2017–2022, specimen, practice, specification | 16 (300) | **C, listed**: papers credited and linked | esat-tmua.ac.uk/tmua-preparation-materials/ (offers 2016–2023 papers, worked answers, answer keys) | Personal viewing, downloading and printing; commercial use and modification need written permission | None | 01 (updated for a free app; asks about showing questions as printed) |
| University of Oxford Mathematical Institute: MAT | 15 (240) | **C, listed** | maths.ox.ac.uk/study-here/undergraduate-study/maths-admissions-test (2007–2025 papers and solutions) | No reuse terms beyond copyright. MAT ended in 2025; Oxford applicants now sit the TMUA. | None | 04 |
| OCR / Cambridge University Press & Assessment (© UCLES): STEP | 13 (163) | **C, listed** | ocr.org.uk/students/step-mathematics/preparing-for-step/ (2014+; older in the STEP database) | Redistribution needs written consent; Cambridge terms forbid storing content in databases | None | 06 |
| UK Mathematics Trust: SMC, IMC, BMO, Maclaurin, Senior Kangaroo | 39 (753) | **C, listed** | ukmt.org.uk/competition-papers | Covering most of a paper, or a topic across years, in an app needs written permission; recent papers free, older sold | None | 05 |
| JZMaths (Joe Zhou) | 10 (200) | **C, provider only**: credited and linked, papers not listed | jzmaths.com | All rights reserved; free practice on site, some sets in a paid bundle; some material builds on UCLES papers under fair dealing | None | 07 |
| TMUA.co.uk | 1 (20) + guides | **C, provider only** | tmua.co.uk (paid platform; no terms page found) | Not stated; three Drive downloads are personalised and never used | None | 03 (generic) |
| Tyler Tutoring (Jacqueline Tyler): topic banks, mock sets A–D | 10 (317) | **D** (no public page verified; sets are sold in JZMaths' bundle) | none | Personal, non-commercial use only (R1) | None | 08 (route to confirm) |
| MioMath | 2 (40) | **D** (page not re-verified) | none | Personal, non-commercial use only (R1) | None | 09 (route to confirm) |
| TMUA Euclid (samples, Ascent, cheat sheet) | 4 (67) | **D** (page not re-verified) | none | Personal, non-commercial use only (R1) | None | 10 (route to confirm) |
| PMT Education: handwritten MAT solutions | Drive only (7 files) | **Not used.** Candidate for A within its licence, if Revisr stays non-commercial. | physicsandmathstutor.com | Cover states CC BY-NC-ND 4.0: unaltered, non-commercial sharing with credit | Licence notice, not yet confirmed with PMT | 11 |
| TMUA.fyi challenge sets | 4 (80) | **D** | none | Private-study licence; forbids sharing and competing products; authors not named | None | Do not use |
| Yotta, Beyond Horizon, Zetta, Zack, Rosie, James Chen, Asher Falcon, DπD Maths, sed | 17 (340) | **D** | none | No published terms or contact; one domain redirects to an unrelated site | None | Do not contact via that domain |
| Cambridge CSAT samples | 4 (80) | **D** (not part of the TMUA product) | none | Personal, non-commercial printing; ownership of hosted copies unclear | None | — |
| Percentile Labs: The 9.0 TMUA Handbook | 1 reference | **D** | none | All rights reserved | None | — |
| Revisr original questions | 82 questions (87 versions) | **A once reviewed**; today development builds only, labelled "draft, not yet reviewed" | — | Revisr's own; awaiting human mathematical, originality and pedagogical review | Not applicable | — |

## Attribution in the app

- **Question credit:** every question shows a short line under its options, visually subordinate to the mathematics:
  - "Original Revisr question · draft, not yet reviewed";
  - "Source: UAT-UK (© UCLES) · TMUA 2019 Paper 1 · Q11 · personal study copy";
  - later, licensed items in the holder's own wording.
- **Library credit:** every library source shows "Source: <provider credit>", its type (official TMUA, other admissions test, independent mock, competition, reference) and, where verified, a link that opens the provider's own page in Safari. Revisr links only to the provider's own page, never to a re-host.
- **No endorsement:** no text implies that UAT-UK, UKMT, JZMaths or any provider endorses Revisr.

## What would move a source to category A

1. You decide which holders to approach and send the request yourself (drafts in `revisr-content-private/rights/requests/`, none sent). Recommended order: UAT-UK (the 259 official questions are already prepared as study copies), Oxford MAT, then JZMaths and Tyler Tutoring for questions they confirm are wholly theirs.
2. Record each written grant in `rights/grants/` and the register (`tools/review_workflow.py record … rights cleared --reviewer "<name>"`).
3. Change those items' category to `licensed_past_paper` or `licensed_mock`, with rights fields `cleared` only within the grant and the holder's attribution wording. A human mathematical review of each key follows, then publication approval.
4. The build gate then admits them. If a grant allows showing questions as printed, the page-crop presentation built for study copies can be reused, but two changes are needed first. The licensed papers must be bundled outside the folders that Release builds strip. The public gate's rule that rejects any paper-presented item must also be relaxed for licensed categories.

Counts per provider come from `AdmissionsManifest.json` mapped through `TMUAResourceProviders.json` (136 sources, 2,600 questions in total).
