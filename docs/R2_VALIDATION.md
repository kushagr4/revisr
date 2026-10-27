# R2 validation

27 October 2026. Everything here ran on the approved iPhone 17 Pro simulator (iOS 26.5, `977DC755…`) or on the Mac. **Nothing was tested on a physical iPhone:** it was reachable only over Wi‑Fi with its tunnel disconnected, and this milestone did not require it.

## Git

| Repository | Start | End | Pushed |
|---|---|---|---|
| `revisr` (branch `claude/revisr-r2-diagnostic-quality`, from `claude/revisr-question-bank-integration`) | `0863c36` | see the handover | No |
| `revisr-content-private` (`master`, no remote) | `f22af8d` | `bb6f3b2` | No remote |

## Automated tests

| Suite | Result |
|---|---|
| Full unit suite (`revisrTests`) | 250 run, 244 passed, 6 skipped, 0 failed. Before R2: 234 run, 228 passed, 6 skipped. The 6 skips are the same older migration tests, which need local staging stores. |
| New: `TMUASelectionPolicyTests` | 13 of 13 |
| New and changed: `MathTextLayoutTests` | 13 of 13 (10 existing, unchanged; 3 new) |
| Existing selection, lifecycle and integration tests under v3 | 40 of 40, unchanged |
| Full UI suite (`revisrUITests`), light mode | 12 of 12 passed in 42 minutes, with no crash reports: the 10 existing tests (journey accessibility audit, four first-run journeys, three lifecycle and expansion tests, two typography tests) and the 2 new question-screen tests. The journey audit now reports 4 Dynamic Type advisories on the question screen (152 before R2) and 307 advisories in total (602). |
| Focused question-screen UI tests, dark mode | 4 of 4: audit, disabled Previous, typography specimens, official question. Measurements identical to light mode. |
| Private content checks | R2 verifier: 10 of 10 verified. Content validator: 356 items, 0 structural problems, 0 publicly eligible. Register check: 0 problems, 0 human decisions. |

## Selector checks beyond the tests

- **Parity with the evaluated design.** v3 was tuned in a Python replica on the real bank. The Swift selector's picks equal the replica's for all 96 test diagnostics (4 lengths × 24 students), on both the pre-R2 bank and the R2 bank.
- **v2 frozen.** Swift v2's picks on the pre-R2 bank equal the saved pre-R2 baseline for all four lengths. Its picks on the R2 bank equal the v2 replica's.
- **Composition, spread, difficulty, variety and expansion:** see `R2_DIFFICULTY_AND_SOURCE_DIVERSITY.md`.

## Planner regression

`TMUACatalogueAuditTests` (Balanced diagnostic, exam 14–180 days ahead, three study loads; R2 bank, v3):
- every one of the 36 scenarios has no empty study day and needs no paper session;
- official questions make up 27–74% of practice tasks (38–75% before R2);
- no question is used more than 4 times.

The bank-wide planner audit (`TMUAPlannerAuditTests`, 351 questions) also shows no empty days in any scenario.

## Debug build and public Release gate

- **Debug build:** assembles the internal bank of 356 versions (259 official study copies, 97 original versions, of which 10 are new R2 drafts).
- **Release build:** the gate assembled 0 items and excluded 356, including all 10 new drafts.
  - The app is 26 MB and contains no PDF or video.
  - It contains none of: the specimen strings, an official question identifier, an original or new-draft identifier or title, test-fixture identifiers, or the typography bank flag.
  - It still bundles the library's metadata manifests, as before R2.
- **Unchanged:** the public gate rules and the Release stripping of restricted files.

## What kind of check each result is

| Kind | What it covers in R2 |
|---|---|
| Automated tests (simulator) | Everything above |
| AI-assisted mathematical checking | The new drafts: an author's derivation, a programmatic verifier and an independent blind re-solve (10 of 10 agree). The audit of the 32 existing Paper 2 originals (AI re-solve, 0 validity problems). |
| Human content review | None. No question, key, classification or difficulty has had human review, and the register records no human decision. |
| Difficulty | Every level is an estimate. The new drafts store the lower of two AI estimates. No difficulty is calibrated against student responses. |
| Copyright | Unchanged: no third-party permission is held. Official study copies remain private development content, excluded from public builds. |

## Disk

14 GiB free on the startup disk. R2 created no new derived-data folder: it reused `dd-r1` and `dd-release`, kept a 2.6 MB content snapshot and temporary result bundles. Older scratch folders from earlier milestones were left alone.
