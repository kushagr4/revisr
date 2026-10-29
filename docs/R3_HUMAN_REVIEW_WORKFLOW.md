# R3 human review workflow

28 October 2026. How a question goes from draft to publishable, and how independent mathematical reviewers take part.

The tools live in the private content workspace (`revisr-content-private/tools/`), next to the questions they handle. This page describes them without quoting any question, key or reviewer material.

**Nothing has been reviewed yet.** No reviewer is registered, the register holds no human decision, and the approved-content manifest is empty.

## Four separate questions

| Question | What answers it | Can AI checking settle it? |
|---|---|---|
| Is the mathematics right: the question, its key and the worked solution? | The reviewer's own blind solution, then the stages *mathematical*, *answerKey* and *workedSolution* | No. AI re-solving and programmatic verification find errors and feed the queue, but they never pass a stage |
| Is it original and ours to distribute? | The *originality* stage for Revisr questions; the *rights* stage plus a verified grant for third-party questions | No |
| Is it good TMUA preparation? | The stages *distractors*, *wording*, *syllabus* and *pedagogical*, plus the reviewer's own difficulty rating | No; the AI tiers only rank the queue |
| May it ship? | The owner's *publication* decision, after every other stage, compiled into the manifest | No |

A mathematically correct question is not thereby publishable, and two AI solvers agreeing is not a review.

## Stages and roles

Each stage is a separate decision on one exact version. The decision binds to that version's content hash: the SHA-256 of what the student sees and is marked on (title, stem, options, key, solution, taxonomy, source, presentation).

| Stage | Decisions | Who may record it | Needed for |
|---|---|---|---|
| mathematical | approved / correction_required / rejected | mathematical reviewer | every publishable question; recorded before any other approval |
| answerKey | same | mathematical reviewer, after their own blind answer matches the key | every publishable question |
| workedSolution | same | mathematical reviewer | every publishable question |
| distractors | same | mathematical reviewer | every publishable question |
| wording | same | mathematical reviewer | every publishable question |
| syllabus | same | mathematical reviewer | every publishable question |
| originality | same | owner or originality reviewer | Revisr originals |
| pedagogical | same | mathematical reviewer | every publishable question |
| rights | cleared / not_permitted / pending | owner or rights reviewer | every publishable question; third-party questions also need a verified grant |
| publication | approved / withdrawn / rejected | owner only, after all other stages | every publishable question |

Two records are kept apart from the stages and never gate publication:
- **Blind answer:** a reviewer's own answer letter and time, recorded before they open the key.
- **Difficulty rating:** the reviewer's independent level (1–5) and time.

Difficulty therefore exists in three separate forms:
- **Author estimate:** stored with the question; for drafts made since R2 it is the lower of the author's and an AI estimate, with both named in its provenance.
- **Independent review:** the reviewer's rating. A public build uses it in place of the author estimate once it is recorded (see `R3_PUBLIC_CONTENT_PIPELINE.md`).
- **Student calibration:** does not exist yet. It needs real responses from students.

The R1 workflow made "difficulty calibrated" a gate before publication. Calibration needs students, and students need published questions, so nothing could ever have been published. R3 replaces that gate with the non-gating reviewer rating.

## Safeguards built into the tools

- **Registered humans only.** A reviewer is registered once (`add-reviewer`) with a real name and roles. A name or ID that looks like an AI tool (Claude, GPT, Codex, Copilot, Gemini, "assistant", "AI", "LLM") is refused. Every decision names a registered reviewer; none can be fabricated by the tooling, which never writes decisions on its own.
- **Blind answer first.** An answer-key approval is refused unless that reviewer's own blind answer for the same content matches the stored key.
- **Order.** Every approval waits for a mathematical approval of the same content, and publication waits for every other required stage.
- **Content binding.** If a question's student-facing content changes after a decision, that decision no longer passes, `check` reports it, and the public build stops. A change must become a new version.
- **All-or-nothing import.** A reviewer's sheet is imported as a whole or not at all. One invalid cell, such as an answer-key approval without a blind answer, rejects the file.
- **Study copies.** Official questions held as personal study copies can have their keys and classification checked by a person for internal use, but their rights and publication stages are refused: they can never be published.
- **Bank fields cannot claim more than the register.** `check` fails if an item's own fields claim an approval the register does not record.

These rules are exercised by `tools/tests/test_review_workflow.py` (9 tests, run on a temporary copy of the workspace).

## Review packets

`python3 tools/review_workflow.py packet --wave 1` (or `--paper 2 --topic logic`, or `--ids FILE`) writes a folder for a reviewer:
- `README.md`: instructions, the stage definitions and the 1–5 difficulty scale;
- `blind/paper-N-topic.md`: questions and options only, with the suggested time and a space for an answer;
- `key/paper-N-topic.md`: for each question,
  - the stable ID and version;
  - the separate correct answer;
  - the worked solution;
  - the classification, intended difficulty and its provenance, and the estimated time;
  - the authoring provenance and version history;
  - the content hash;
  - known concerns from AI pre-review, labelled as unverified;
- `decisions.csv`: one row per question with the content hash, blind answer and time, one column per reviewer stage, difficulty rating, time and notes.

Rights and publication are not on the reviewer's sheet; the owner records them.

The reviewer returns the sheet, and the owner imports it with `import decisions.csv --reviewer <id>`. Packets contain keys and solutions, so they stay private: do not commit them to a public repository or send them beyond the review team.

## Corrections

When a question fails review, or AI pre-review finds a genuine defect:
1. The existing version is left untouched. Submitted diagnostics store a full snapshot of what the student saw, and older versions stay resolvable.
2. A corrected version is written as version N+1 with the same stable ID, in a new bank file. R1 used `corrections-r1.json`; R3 uses `corrections-r3.json`.
3. `supersede OLD NEW --reason "…"` records why it changed in `review/corrections.json`, with both content hashes.
4. The register marks the old version as superseded and refuses new decisions on it. Decisions never carry over to the new version.
5. New diagnostics and practice use the latest version, while old responses keep pointing at the version answered. No stored response is rewritten.

R1's five corrections were recorded retroactively in R3. R3's own corrections are described in `R3_MATHEMATICAL_QUALITY.md`.

## The review queue

`python3 tools/review_workflow.py queue` ranks the latest version of every publishable question and writes `review/queue.md` and `queue.json` (private). The ranking uses the AI-assisted pre-review tiers and difficulty estimates and records no decision.

| Wave | Purpose | Rule |
|---|---|---|
| 1 | Initial public diagnostic | The strongest question for each syllabus topic in each paper, from those rated suitable for diagnosis or practice |
| 2 | The 40-question diagnostic with per-student variation | Up to 30 per paper, preferring topics with the fewest chosen so far and demanding questions |
| 3 | Follow-up practice | Everything else that is sound, including questions below TMUA level (marked as such) |
| Correct first | — | Versions with a defect worth a new version; they enter the queue once corrected |

Near-duplicate pairs are kept apart: the second member of each pair is marked "review after" its partner.

## Commands

```
python3 tools/review_workflow.py add-reviewer jsmith --name "J. Smith" --roles mathematical
python3 tools/review_workflow.py packet --wave 1
python3 tools/review_workflow.py import review/packets/<folder>/decisions.csv --reviewer jsmith
python3 tools/review_workflow.py record ID@vN rights cleared --reviewer owner-id
python3 tools/review_workflow.py record ID@vN publication approved --reviewer owner-id
python3 tools/approved_manifest.py build
python3 tools/review_workflow.py check
```

`approved_manifest.py build` compiles the manifest from the register; see `R3_PUBLIC_CONTENT_PIPELINE.md`.

## What the owner needs to provide

1. **Reviewers.** One or more independent reviewers with A-level Further Mathematics or university mathematics, ideally with TMUA, MAT or STEP experience. Register each one under their real name.
2. **Roles.** Decide who holds the owner role (rights and publication). It may be you. Holding it does not make you a mathematical reviewer, unless you also review the mathematics.
3. **A policy on second reviews.** The tools require one human decision per stage. If you want two independent mathematical reviews for diagnostic questions, say so; it is a small change to the stage rules.
