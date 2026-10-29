# R3 public content pipeline

28 October 2026. How approved questions reach a public build, and why none do today.

## Five content tiers

| Tier | Where it lives | Reaches |
|---|---|---|
| Private development bank | `revisr-content-private/bank/*.json`: every version of every original draft, correction and personal study copy | Debug builds only, labelled as unreviewed or as study copies |
| Unpublished draft bank | Every version not listed in the approved manifest (today: all of them) | Debug builds only |
| Approved original bank | `approved/manifest.json` → `approvedOriginal` | Public builds |
| Approved licensed bank | `approved/manifest.json` → `approvedLicensed`, each entry with a verified grant in `rights/grants/` | Public builds |
| External-only resources | `revisr/Resources/TMUAResourceProviders.json`: providers with `publicAccess` `listed` (papers listed and linked) or `provider` (site credited and linked) | Every build, as links; nothing is reproduced |

## How an item gets in

```
bank/*.json ──► review/register.json ──► tools/approved_manifest.py build ──► approved/manifest.json
  (content)       (human decisions,         (compiles; never decides)          (versioned, revision N)
                   bound to content hash)                                              │
rights/grants/*.json (verified permissions) ──────────────────────────────────────────┤
                                                                                       ▼
                     Scripts/assemble_tmua_content.py, public distribution (every Release build and archive)
                     1. validate the whole bank (structure, markup, duplicate question text)
                     2. for each manifest entry: same content hash as the bank; every required stage
                        in the manifest AND in the register, by a registered human, for this content;
                        third-party items: a verified grant covering the source and permitting all five uses
                     3. stamp review, rights and approval record; drop reviewer notes and identities;
                        use the reviewer's difficulty rating if one was recorded for this content
                     4. public gate (rights fields, review fields) + format check (renderer markup,
                        no bundled-paper presentation, a worked solution)
                     5. any failure stops the build; it never silently ships fewer items
                                                                                       ▼
                     RevisrContentBank.json (distribution public, approvedManifestRevision N)
                     + restricted PDFs and videos stripped + check-app re-verifies every item
                                                                                       ▼
                     App at runtime: public eligibility = public gate AND an approval record
```

**Defaults stay restrictive.**
- With no manifest, or an empty one, the public bank is empty.
- Debug builds assemble the internal bank as before. An archive (`ACTION=install`) is always public.
- Internal content outside Debug still needs an explicit local override. That rule is unchanged from R1.

**Nothing is hidden behind a flag.** A public build simply does not contain unapproved question text, keys, solutions, PDFs or videos; `check-app` fails the build if any are present. It also fails if the build bundles a manifest, a register or a reviewers file.

**Versions and hashes.**
- The content hash covers the title, stem, options, key, solution, taxonomy, source and presentation.
- It deliberately excludes difficulty and minutes, because reviewers may revise those estimates.
- A decision recorded for one hash does not cover a changed question, and the build stops if the bank and manifest disagree. A changed question needs a new version and new decisions.

**Runtime check (content policy v2).** `TMUAContentPolicy.approvalFailures` requires every public item to carry an approval record with the approval policy version and a content hash. A bank whose own fields claim approval but which never passed through the manifest is therefore still excluded. Saved diagnostics keep the policy version they were created under.

## What "supported app format" means

The format check rejects, for a public build:
- a TeX command the renderer does not support, because it would show as raw text. The list is checked against `MathText.swift` by a unit test, so the two cannot drift;
- TeX outside `\( … \)` or `\[ … \]`;
- a question shown from a bundled paper region, since public builds never bundle papers;
- a missing worked solution.

## Today's state

| | Count |
|---|---|
| Manifest revision | 1 (empty) |
| Approved original | 0 |
| Approved licensed | 0 |
| Registered reviewers | 0 |
| Human decisions | 0 |
| Release build | 0 questions bundled, 373 versions excluded, no PDF or video, no private review file |

So every diagnostic length is unavailable in a public build, and the app says why (`R3_STUDENT_RESOURCE_EXPERIENCE.md`).

## How much approved content is enough

Section sizes per paper: Starter 5, Quick 8 (Paper 2: 7), Balanced 10, Comprehensive 20.

`Scripts/public_content_readiness.py` reports, from exactly what a Release build would bundle:
- per paper: counts, topics and levels;
- for each length, whether it is **offered**: each paper has at least its section size;
- for each length, whether it is **offered well**: each paper also has
  - about 1.5 × the section size, so students do not all receive the same set;
  - min(section size, applicable topics) topics;
  - the v3 selector's demanding share at levels 4–5;
- how many study days of new practice would remain after the longest diagnostic it supports.

`--assume FILE` answers "what if these passed review?" without approving anything.

The minimum below is derived, not invented:
- A Balanced diagnostic needs 10 per paper. Per-student variation needs about 15 per paper.
- Topic coverage needs one question per topic: 14 topics in Paper 1 and 17 in Paper 2.
- Expansion from 10 to 40 questions needs 20 distinct per paper, and variation needs about 30.
- Practice must not reuse a student's diagnostic questions as fresh. At 5 hours over 6 days a week, a plan uses about 2.9 new questions per study day (R2 planner audit), so every 30 calendar days of fresh practice needs roughly 75 more questions.

### Measured, not assumed

**What the queue's waves would support, if every question in them passed review** (`public_content_readiness.py --assume …/queue.json:N --ai-levels`; levels counted with the lower of the stored and independent AI estimates):

| Approved set | Paper 1 / Paper 2 | Topics P1 / P2 | Level 4–5 P1 / P2 | Starter | Quick | Balanced | Comprehensive |
|---|---|---|---|---|---|---|---|
| Wave 1 | 14 / 15 | 14 of 14 / 15 of 17 | 2 / 3 | offered well | thin (demanding) | thin (variety, demanding) | unavailable (6 and 5 short) |
| Waves 1–2 | 30 / 30 | 14 / 15 | 2 / 3 | offered well | thin | thin | thin (demanding, 2 Paper 2 topics) |
| All 104 originals | 58 / 46 | 14 / 15 | 2 / 3 | offered well | thin | thin | thin |

**Plans with that content,** measured with the real planner (`TMUAPublicContentTests`, Balanced diagnostic, 5 hours over 6 days a week, approvals stamped in memory only, original-only diagnostic assumed). Each cell gives distinct practice questions, then paper sessions linked to publishers, then empty study days:

| Approved set | 14 days | 30 days | 60 days | 90 days | 120 days | 180 days |
|---|---|---|---|---|---|---|
| Wave 1 (29) | 20 / 0 / 0 | 29 / 1 / 0 | 29 / 8 / 0 | 29 / 27 / 0 | 29 / 53 / 0 | 29 / 55 / **49** |
| Waves 1–2 (60) | 32 / 0 / 0 | 50 / 0 / 0 | 60 / 0 / 0 | 60 / 0 / 0 | 60 / 3 / 0 | 60 / 7 / 0 |
| All originals (104) | 32 / 0 / 0 | 72 / 0 / 0 | 93 / 0 / 0 | 98 / 0 / 0 | 104 / 1 / 0 | 104 / 1 / 0 |

Beyond the first month, the 60- and 104-question sets keep days full by spaced review: questions are used up to four times, and new questions stop arriving 6 to 30 days before the exam. Wave 1 alone falls back on linked papers after a month and leaves 49 empty days in a six-month plan.

**The minimum useful public set, given all this:**
- **Tier A, a credible first release:** waves 1–2 approved, about 60 questions (30 per paper). That offers all four lengths with per-student variation and plans up to about two months without padding. It still needs either the original-only product decision or licensed questions, and it is short of demanding questions. *(R4: the owner has since allowed an original-only public diagnostic; see `R4_DIAGNOSTIC_CONTENT_INTEGRATION.md`.)*
- **Tier B, all four lengths offered well:** on top of Tier A, about 8 more level 4–5 questions in each paper, Paper 2 questions in ratio and proportion and in statistics, and about 15 more per paper for variety.
- **Tier C, three to six months of fresh practice:** about 75 further questions for every extra month at a moderate load. The realistic route to that volume is licensed past and mock questions, not ever more originals.

These figures come from the capacity audit and the readiness tool, both rerun on the final R3 bank; development-bank capacity (mostly official study copies) is not public capacity.


## Commands

```
python3 Scripts/assemble_tmua_content.py validate              # bank checks and manifest status
python3 Scripts/public_content_readiness.py                    # what a public build could offer
python3 Scripts/public_content_readiness.py --assume ../revisr-content-private/review/queue.json:2
python3 ../revisr-content-private/tools/approved_manifest.py build
python3 -m unittest discover -s Scripts/tests -p 'test_assemble*.py'
```
