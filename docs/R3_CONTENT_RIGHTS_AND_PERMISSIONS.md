# R3 content rights and permissions

28 October 2026. What Revisr may do with each source today, what it would need to do more, and the permission requests prepared for the owner. No request has been sent and no permission is held.

This is an AI-assisted reading of each provider's published terms, checked on the provider's own pages where they could be fetched. It is not legal advice. The private matrix (`revisr-content-private/rights/matrix.json`) records the evidence URL, the date and a short summary for every entry. The raw research notes are in `rights/research-2026-10-28/`.

## Four categories

| Category | Meaning in Revisr | Sources today |
|---|---|---|
| Approved for in-app redistribution | A verified grant or licence covers showing questions, marking, worked solutions and App Store distribution | None |
| External linking only | The app credits the provider and links to its own pages; nothing is reproduced | UAT-UK (TMUA), Oxford MAT, OCR (STEP), UKMT, JZMaths, Tyler Tutoring, TMUA Euclid, TMUA.co.uk |
| Personal-development resource | The owner's own copies may appear in private Debug builds only; never in a public build | The owner's library: TMUA papers, MAT, STEP, UKMT, JZMaths, Tyler, TMUA Euclid, Yotta, TMUA.fyi and others |
| Restricted or unresolved | Not used in any public workflow until resolved | Cambridge University Press & Assessment (for older papers), MioMath, PMT Education, Yotta, TMUA.fyi, CSAT samples, unattributed mocks, Percentile Labs |

## Providers

| Provider | Published terms (checked 28 Oct) | Public use | Request |
|---|---|---|---|
| UAT-UK (official TMUA) | Personal viewing, download and printing; commercial use or modification needs written permission | Link to the preparation-materials page | Draft: up to 80 questions from 2017–2020 Papers 1 and 2 |
| Cambridge University Press & Assessment | Terms page refused automated access; R1 notes forbid scraping or storing content | None | Only if UAT-UK says the older papers are not theirs |
| OCR (STEP) | Centres may copy for in-centre teaching; other reproduction via the Publisher Relationship Manager | Link to OCR's STEP page | Not recommended: long-answer questions, linking suffices |
| Oxford MAT | Papers and solutions published with a copyright footer and no reuse terms | Link to the MAT page | Draft: up to 60 Question 1 multiple-choice items, 2007–2020 |
| UKMT | Single questions may be discussed publicly; systematic use in a public medium needs permission; official solutions not for commercial use | Link to the competition-papers page | Draft: up to 50 SMC questions, 2010–2019, with Revisr-written solutions |
| JZMaths | Personal, non-commercial licence; some material is UCLES-derived or by other authors | Credited link (new in R3) | Draft: up to 40 questions wholly the author's own |
| Tyler Tutoring | Copyright notice; public resources page now found (it was not in R1) | Credited link (new in R3) | Draft: up to 40 questions wholly the author's own |
| TMUA Euclid | Personal study only; the terms are marked as a placeholder pending legal review | Credited link (new in R3) | Draft: up to 30 questions; asks who can grant |
| TMUA.co.uk | Paid platform; no terms page | Credited link (unchanged) | None |
| MioMath | Personal study only; sells "post-exam recalls" of live papers; WeChat-only contact | None | Not recommended |
| PMT Education | Site says all rights reserved; R1 saw CC BY-NC-ND on some PDFs | None | Not recommended: it re-hosts official papers |
| Yotta, TMUA.fyi, unattributed mocks | No identifiable author or contact | None | No route |

**Links verified.** The eight provider links the app now shows were requested on 28 October and returned HTTP 200 at their stated addresses. They live in `revisr/Resources/TMUAResourceProviders.json`, together with the terms summaries the app displays.

## Permission requests prepared (not sent)

The drafts are regenerated from the matrix by `tools/rights_requests.py drafts`, so the scope and wording stay consistent. Each draft:
- explains that Revisr is free to students, that it is a personalised TMUA programme (diagnostic, then a schedule of topic practice, spaced review, timed sets and mocks), that it is not affiliated, and that every question carries the credit the rights holder chooses;
- asks for a stated, limited scope (named years, papers and a maximum number of questions), never a whole bank;
- asks for five rights separately, so the holder can grant some and not others:

  | Right | Grant field the build gate checks |
  |---|---|
  | Showing the questions in the app, as printed or re-typeset without changing the wording | `inAppDisplay` |
  | Marking with the published answer key | `answerOptionsAndKey` |
  | Showing worked solutions (theirs, or Revisr's own where theirs are restricted) | `workedSolutions` |
  | Distribution through the App Store, stored on the student's device, with Apple's copy protection | `appDistribution` |
  | Distribution free to students, and whether that would survive any future change | `freeAppStoreDistribution` |

- says that whole papers are never downloadable, that no scaled scores or official difficulty are claimed, and that material is removed on request;
- says what Revisr does if the answer is no: keep crediting and linking.

There is also a courtesy note for Isaac Maths. Its content is CC BY 4.0, so it needs no permission, but the note confirms the item-level licence, the credit wording and the copy-protection question below.

## Openly licensed alternatives

| Source | Licence (verified on the source's own page unless noted) | Fit for TMUA | Status |
|---|---|---|---|
| Isaac Maths (University of Cambridge) | CC BY 4.0 "unless stated otherwise", site-wide | High: A-level problem solving | Candidate; check each item's licence and copy items by hand (the terms forbid scraping) |
| forall x: Calgary | CC BY 4.0, solutions included | Medium-high for Paper 2 logic background; needs adapting to TMUA style | Candidate |
| An Infinite Descent into Pure Mathematics | CC BY-SA 4.0 | Medium-high for proof | Candidate; adapted questions must stay CC BY-SA |
| Active Calculus | CC BY-SA 4.0 (edition colophon) | Low: US calculus drill | Candidate, low priority |
| Illustrative Mathematics, first edition | CC BY 4.0 (later editions are CC BY-NC) | Low | Candidate, low priority |
| OpenStax | Now CC BY-NC-SA 4.0, no longer CC BY | Low-medium | Unresolved (non-commercial) |
| Book of Proof | CC BY-NC-ND 4.0 (from a search result) | Medium | Unresolved: no derivatives means no multiple-choice versions |
| Sundstrom, APEX, Stitz-Zeager | CC BY-NC(-SA) | Low | Unresolved |
| Mathematics Stack Exchange | CC BY-SA by post date | Variable; authorship of problems unclear | Unresolved |
| Underground Mathematics, NRICH, CK-12, Open Middle | All rights reserved or custom; Underground Mathematics names third-party apps as commercial use | High (Underground Mathematics) | Link only |
| MEI Integral, AoPS Wiki | Subscription or no licence | — | Restricted |

No openly licensed item has been imported. Two issues must be settled first:
1. **Copy protection.** Creative Commons licences forbid applying technical measures that restrict what recipients may do with the licensed material. App Store apps are delivered with Apple's FairPlay protection. Whether CC BY or CC BY-SA content inside an App Store app conflicts with this is unresolved. Publishing the same adapted questions openly on the web may be a mitigation. Take advice before shipping CC content.
2. **Non-commercial terms.** A free app with no advertising is arguably non-commercial, but that is untested, and any later monetisation would breach NC terms. R3 treats NC sources as unresolved.

A licensed item enters a public build only through the same manifest as originals. It also needs a verified grant (`rights/grants/<id>.json`) that covers its source and permits all five uses (see `R3_PUBLIC_CONTENT_PIPELINE.md`). For an open licence, that grant record holds the licence and a copy of the licence page as evidence.

## Decisions for the owner

1. Whether to send each draft, after checking the bracketed fields. In particular, confirm that Revisr will have no advertising, in-app purchases or subscription.
2. Whether to pursue openly licensed material, and if so whether to take advice on the copy-protection question first.
3. Whether to keep listing JZMaths, Tyler Tutoring, TMUA Euclid and TMUA.co.uk as credited links. Some of their material is paid, and the footer says so.
