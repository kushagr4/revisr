# Mixed-source question policy (`tmua-content-policy-v1`)

## Categories

| Category | Meaning | Public requirements |
|---|---|---|
| `revisr_original` | Written for Revisr | All rights fields `cleared`, mathematical review `human_approved`, originality review `human_approved`, publication `approved` |
| `licensed_past_paper` | Past examination question used under licence/permission | All rights fields `cleared` (in-app use, redistribution, commercial use, answer key, solution), mathematical review `human_approved`, publication `approved`, complete source record (organisation, examination, year, paper, question number, URL, attribution) |
| `licensed_mock` | Third-party mock question used under licence | As for past papers |
| `development_fixture` | Synthetic test data | Never eligible outside tests |

Each item records copyright holder, licence, attribution and the five rights states (`cleared`, `pending_review`, `not_permitted`, `not_applicable`). A file being downloadable, or present in the repository, is never treated as permission. The R1 inventory of every legacy source, the rights holders' published terms, and the steps to obtain and record permission are in `R1_PAST_PAPER_LICENSING_PLAN.md`. As of 26 October 2026 no source has permission.

## Enforcement (two independent layers)

1. **Build time** — `Scripts/assemble_tmua_content.py` runs as the "Assemble TMUA Content" build phase. It validates every item in the private workspace (structure, taxonomy, option/key consistency, markup) and writes `RevisrContentBank.json` into the built app:
   - `REVISR_DISTRIBUTION=internal` (Debug default): all structurally valid non-fixture items, with review state intact.
   - `REVISR_DISTRIBUTION=public` (Release default): only items passing the public gate; reviewer notes removed. Restricted legacy resources (every file under `AdmissionsPapers`, `AdmissionsSolutions`, `AdmissionsVideos`) are deleted from the product. A `check-app` gate then fails the build if any restricted file or ungated item remains.
2. **Runtime** — `TMUAContentContext` re-applies the public gate. Release builds (`#if !DEBUG`) treat any bank as public even if it claims to be internal, so a mislabelled bank cannot widen eligibility.

Question content never lives in this public repository. It is read at build time from `REVISR_PRIVATE_CONTENT_DIR` (default `../revisr-content-private`). If the workspace is absent the build bundles an empty bank and the app shows an honest unavailable state.

## Source mix

- Selection gives a modest bonus to real past or mock items (licensed, or personal study copies in development builds) until about half of a section is past or mock (`preferredLicensedShare = 0.5`; 0.3 before the question-bank integration, when a moving section total let it reach about 60% anyway). Coverage scoring outranks it, and at most one licensed item per topic receives the bonus, so licensed questions are not concentrated in one topic. There is no fixed ratio.
- Each diagnostic stores its actual composition (`sourceCompositionNote`), shown on the hub and results screens.
- Every question shows an unobtrusive attribution ("Original Revisr question", "Licensed past examination question", "Licensed mock paper question"); licensed items also show their source attribution. Nothing implies endorsement by an examination provider.

## When no licensed content is cleared (the current state)

`TMUASourceMixStatus`:
- **Public build** → `.blocked`. The diagnostic is unavailable, with the reason shown. It is never silently replaced by an original-only diagnostic. `TMUAContentPolicy.publicAllowsOriginalOnlyDiagnostic` is `false`; changing it requires an explicit product decision.
- **Development build** → `.originalOnlyDevelopment`. The diagnostic runs on unreviewed original drafts, with a visible notice that no past or mock content is cleared.

## Current content counts (26 October 2026)

| | Original | Licensed past | Licensed mock | Publicly eligible |
|---|---:|---:|---:|---:|
| Paper 1 | 34 | 0 | 0 | 0 |
| Paper 2 | 26 | 0 | 0 | 0 |

All 60 originals are AI-assisted drafts: rights `pending_review`, mathematical review `ai_derivation_only`, originality `pending`, publication `not_approved`. 20 Paper 1 items come from Revisr Web's private W3.0 candidate; 40 were authored on 26 October 2026. An independent blind AI re-solve matched all 60 keys. That is a QA signal, **not** human review.

## Permissions required before a mixed-source public release

For each past/mock question: the rights holder's written permission (or licence) covering in-app reproduction, redistribution in an App Store build, commercial use, reproduction of answer keys and of worked solutions, plus the required attribution text. UAT-UK's website terms permit personal use and fair linking only; commercial use needs express written permission (see Revisr Web `docs/EXAMINATION_CONTENT_RIGHTS_AUDIT.md`). No such permission exists today.
