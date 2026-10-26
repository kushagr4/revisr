# R1 release readiness

**Status (26 October 2026): not ready for public release.** The software journey is now exercised through real UI automation, but no question is human-approved, no past or mock content is licensed, and third-party files remain in public Git history. Nothing was pushed, merged, uploaded or made public in this milestone.

## Public-build safety (verified)

| Check | Result | How |
|---|---|---|
| Release build compiles (`generic/platform=iOS`, unsigned) | Succeeded | `xcodebuild -configuration Release` |
| Questions bundled in Release | **0** (all 87 draft item versions excluded) | Content phase log; `RevisrContentBank.json` in the built app: `distribution: public`, 0 items. Rechecked after the R1 drafts were added. |
| Restricted PDFs and videos in the Release app | **0** (242 stripped); 0 `.pdf`, 0 `.mp4` | `find` on the built `.app`; app size 15 MB |
| Release gate (`check-app`) | Passed | Build log |
| Debug-only code in the Release binary | None found: no UI-test switches, fixture bank, debug scenarios or draft question IDs | `strings` on the Release executable |
| Internal content in a non-Debug build | Refused unless `REVISR_ALLOW_INTERNAL_NON_DEBUG=1` is set for a local build | `resolve_distribution`, `Scripts/tests/test_assemble_tmua_content.py` |
| Internal content in an archive (TestFlight/App Store input) | Always refused, whatever the settings | Same unit tests, plus an actual `xcodebuild archive` with `REVISR_DISTRIBUTION=internal` (result: `ARCHIVE FAILED` with "internal content may never be assembled for an archive"; no archive produced) |
| Runtime gate | Release builds judge every item by the public gate even if a bank is labelled internal; fixtures load only in Debug with `--uitest-fixture-bank` and an isolated store | `TMUAContentContext.buildAllowsInternalContent`, `DebugUITestSupport` (`#if DEBUG`) |
| Original-only public diagnostic | Still blocked (`publicAllowsOriginalOnlyDiagnostic = false`). This awaits your product decision | — |

Debug builds still bundle the private drafts (87 item versions after R1, labelled "Development content · not yet reviewed") and the legacy PDFs. They are local development builds and must not be distributed.

## Where material lives

| Location | What is there | Exposure |
|---|---|---|
| **1. Inside a distributed app** | Nothing has ever been distributed (no TestFlight or App Store upload in these sessions). A Release build contains no questions and no third-party files. | None |
| **2. Committed to Git (current branch tip)** | 242 third-party PDFs and videos under `revisr/Resources/Admissions{Papers,Solutions,Videos}` (425 MB). 62 files under `tmp/`: rendered page images of the Tyler combinatorics and MioMath papers, and 8 video thumbnails whose filenames show YouTube-downloader origin. Metadata manifests (source names, question numbers, topics; no question text). | Same as row 3 |
| **3. Accessible through GitHub** | `github.com/kushagr4/revisr` is **public** (`gh api`, 26 October 2026). All three remote branches (`main`, `codex/ios-completion`, `codex/public-foundation-recovered`) contain the same 304 restricted blobs (about 439 MiB) since the initial commit `ae50956` (2 September 2026). GitHub reports 0 forks, 0 stars and, for the last 14 days, 10 clones (8 unique) and 0 page views. Clones may include your own machines; older traffic is not available. | Publicly downloadable since 2 September 2026 |
| **4. Private content repository only** | `revisr-content-private` (local git, no remote): the 60 drafts, R1 corrected versions and new candidates, answer keys, solutions, audit and review records, permission-request drafts. | Local only. No question text, key or reviewer note is in the iOS repository (leak scan, `R1_END_TO_END_VALIDATION.md`). |

## Git history exposure: remediation proposal (not executed)

Removing files from the current app bundle or branch tip does not remove them from Git history or from existing clones. **None of the following was done.** Each step needs your explicit approval.

1. **Stop further exposure (reversible).** Make `kushagr4/revisr` private in GitHub settings. This changes repository visibility, which you said must not happen without approval.
2. **Remove the files from the branch tips.** In one commit on each public branch:
   - delete `revisr/Resources/Admissions{Papers,Solutions,Videos}` and `tmp/`;
   - add them to `.gitignore`;
   - have Debug builds copy the legacy PDFs from the private workspace at build time, the same way the TMUA bank is assembled.

   History is unchanged, so this only prevents future versions from containing the files.
3. **Purge history (irreversible for collaborators).**
   - Rewrite every branch with `git filter-repo --path revisr/Resources/AdmissionsPapers --path revisr/Resources/AdmissionsSolutions --path revisr/Resources/AdmissionsVideos --path tmp --invert-paths`.
   - Force-push all three branches.
   - Ask GitHub Support to purge cached views and pull-request refs.
   - Re-clone every working copy.

   All commit hashes change (including `ae50956`, `341dfd9` and this milestone's commits), and local branches must be recreated from the rewritten history. Existing clones keep the files regardless.
4. **YouTube downloads.** Whatever is decided for the PDFs, the 8 downloaded videos should not be redistributed in any build. Link to the creators' own pages instead.

Recommended order: 1, then 2, then 3 once you are ready to re-clone. Before step 3, make a full local backup (`git bundle create revisr-backup.bundle --all`).

## Simulator cleanup (26 October 2026, authorised)

Following your instruction, simulator testing is now limited to iPhone 13 and newer, with no iPads (`IOS_TESTING_POLICY.md`).

| Measure | Result |
|---|---|
| Free space on the data volume before | 6.7 GiB (97% used) |
| Free space after | 21.6 GiB (90% used), measured with `df` after cleanup and test runs. macOS purgeable caches make this figure vary somewhat. |
| Space recovered (measured) | About 14.9 GiB |
| iPhone 12-or-older simulators deleted | 0; none existed |
| iPad simulators deleted | 12 (6 on iOS 26.2, 6 on iOS 26.5, including "MyBoard Verification iPad") |
| Redundant Revisr test simulators deleted | 3: "Revisr Bundled PDF QA", "Revisr Phase 3 QA", and the R1 "Revisr R1 SE QA" (iPhone SE, outside the policy) |
| Unavailable devices | None found |
| Runtimes removed | 0. `simctl runtime delete --unusable/--outdated --dry-run` matched nothing. iOS 26.5 (7.9 GB) serves the retained Revisr devices. iOS 26.2 (7.8 GB, last used 10 October) still backs 6 iPhones holding CityDone, ani and Revisr app data, and removing it would make them unbootable, so it was kept for your decision. |
| Data preserved before deletion | App data containers copied and verified byte-for-byte to `~/Documents/simulator-data-backups-2026-10-26` (38 MB, outside every repository): the MyBoard boards (3 JSON files), the Revisr store and five "Revision Snapshot 2026-08-22" exports from "Revisr Bundled PDF QA", and the Revisr store from "Revisr Phase 3 QA" |
| Kept untouched | The default iPhone 17, 17 Pro, 17 Pro Max, 17e, 16e and Air devices on both runtimes, and "CityDone Phase11E iPhone 15 Pro". These hold other projects' apps and possibly personal Revisr installs; all are iPhone 13+ models. |
| Remaining | 12 simulators, all iPhone 15 Pro or newer: 6 on iOS 26.2, 6 on iOS 26.5. Runtimes iOS 26.2 and 26.5. |
| Verification | The retained Revisr devices boot. Revisr builds for "Revisr Flexible TMUA QA". Smoke test (12 lifecycle unit tests) passed. The full unit suite then passed on that device (209 run, 203 passed, 6 skipped). |

No `simctl erase all`, no manual deletion inside CoreSimulator, no DerivedData purge, and no change to repositories, signing assets or Git history.

## Remaining release blockers

### Content and rights (need people, not code)

| # | Blocker | Status after R1 |
|---|---|---|
| 1 | Human mathematical review | **0 of 87** item versions (82 questions) have a human decision. The AI audit recommends corrections for 3 Paper 2 items (2 blocking, where a second option is equivalent to the key; R1 v2 drafts written) and polish for 31 more. Blind worksheets, key sheets and the review register are in the private workspace. |
| 2 | Originality review | 0 of 82 reviewed |
| 3 | Licensed past/mock content | None. Inventory and request drafts are ready (`R1_PAST_PAPER_LICENSING_PLAN.md`); nothing has been sent. |
| 4 | Product decision on an original-only public diagnostic | Pending your decision |
| 5 | Bank size and variety | See `R1_CONTENT_REVIEW_MATRIX.md`. All 46 strands now have at least one draft question, but 82 unreviewed drafts are far below the roughly 150–200 reviewed questions needed for long plans. 21 strands have a single question. |
| 6 | Difficulty calibration | Author and AI estimates only. The audit found the 20 web items easier than real TMUA (mostly level 1–2). |
| 7 | Answer-key position bias | The key is never the last option in any of the 60 items, and in numeric lists never the smallest or largest. New items rebalance this, but existing items need human-approved new versions. |
| 8 | Third-party files in public history | Proposal above; awaiting your decision |

### Software and QA

| # | Item | Status |
|---|---|---|
| 9 | VoiceOver on a device, including spoken mathematics | Not done. The automated audit covers descriptions, hit regions and traits only. |
| 10 | Physical device, older iPhones, performance traces | Not done. Simulators only (iPhone 17 Pro, iPhone SE 3rd generation, iPhone 17 Pro Max). |
| 11 | Real phone-call and lock interruptions on a device | Simulated with Home and termination in XCUITest |
| 12 | Historical store migration fixtures (6 skipped tests) | Still missing; not manufactured |
| 13 | TypeScript planner parity for the new TMUA-only options | Not ported to Revisr Web. Legacy parity is unchanged. |
| 14 | App Store metadata, privacy label, signing, TestFlight | Not started |
