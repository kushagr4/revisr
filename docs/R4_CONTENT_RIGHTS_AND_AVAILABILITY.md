# R4 content rights and availability

29 October 2026. The owner's R4 decision selects every Drive question for Revisr's library. That is an editorial decision, not a licence. Third-party copyright still belongs to the papers' authors and publishers, so public distribution is still gated question by question (R3 pipeline, unchanged).

## Four capabilities, kept apart

| Capability | What it allows | Where | Today |
|---|---|---|---|
| 1. Private internal catalogue | Index, classify and link every question the owner holds | `revisr-content-private`, and metadata in the app | All 2,851 questions |
| 2. Personal-study presentation | Open the owner's own copies of papers and solutions inside a development build | Debug builds on the owner's devices only; never distributed | 2,697 questions: 104 originals and 2,593 from the 133 bundled papers that contain questions (259 of those marked by Revisr; 2,334 opened at their page) |
| 3. Licensed in-app public content | Reproduce a question, key and solution in the distributed app | Release builds, through the approved-content manifest and a verified grant | 0. No grant exists; no original has passed human review |
| 4. External provider-linked content | Credit the paper and link to the publisher's own page | Every build | 1,609 questions in 93 papers (UAT-UK, Oxford, OCR, UKMT); 4 more providers linked at site level |

**Restricted providers.** MioMath, Yotta, TMUA.fyi, CSAT samples, Percentile Labs and the unattributed mocks are listed only in development builds, as personal study copies. MioMath sells recalls of live papers, and the R3 rights matrix keeps it restricted. The owner's selection includes these papers for personal study. Nothing from them reaches a public build, not even a link.

## Public Release rules (enforced, not hidden behind flags)

- **Approved questions only.** Only versions in the approved-content manifest are bundled, with human decisions for that content hash and, for third-party items, a verified grant (R3).
- **Restricted files are deleted.** Every restricted PDF and video (242 files) is removed from the built product, and `check-app` fails the build if any remain.
- **Private files fail the build.** It also fails if a review register, reviewers file or manifest is bundled.
- **New in R4:** it fails if the catalogue reconciliation file carries answer keys, Drive file IDs or notes (`reconciliation_failures`; tested).
- **Runtime check.** Public eligibility is checked again at runtime (content policy v2).
- **What a public build lists:** the papers of providers whose own pages offer them, each with the publisher's link and credit. It shows no solution, no Drive reference, and no restricted provider.

## Attribution

- **Paper credit:** every paper and question shows its provider's credit from `TMUAResourceProviders.json`, for example "Source: UAT-UK (© UCLES) · TMUA 2019 Paper 1 · Q11". Providers were verified in R1–R3 by title, folder or cover check.
- **Every provider page says** "Revisr is not affiliated with or endorsed by …".
- **Originals** say "Original Revisr question", with a draft label until approved.
- **No author is invented.** The eight unattributed mocks are grouped as "independent authors" under the names their files carry.

## Unresolved permissions

None has changed since R3. Every provider is still without a grant. Six permission drafts and one courtesy note are ready in `revisr-content-private/rights/requests/`, and **none has been sent**. Open-licence options are listed in `R3_CONTENT_RIGHTS_AND_PERMISSIONS.md`: Isaac Maths under CC BY 4.0, subject to the question of whether App Store copy protection is compatible with Creative Commons licences.

## Drive privacy

- **Drive file IDs** exist only in the private inventory and snapshot.
- **Question indexes** for the Drive-only papers carry no question text in public Git. Their public form is question numbers, pages, topic and estimated difficulty, the same kind of metadata the R1 library index already ships.
- **The 125 answer letters** read from those papers' solutions stay private.
