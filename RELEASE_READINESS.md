# Revisr — Release Readiness Report

# READY FOR PRIVATE LOCAL USE

Current distribution decision: 22 August 2026

## Distribution

**Private local use only.** Revisr is installed directly from Xcode onto the owner's iPhone. TestFlight and App Store distribution are intentionally out of scope; no public distribution is planned.

- App Store Connect: Not used.
- TestFlight: Not used.
- App Store submission: Not planned.
- Bundle identifier: `com.kushagra.revisr` — preserve unchanged so future Xcode builds upgrade the existing installation.
- Signing: automatic Apple Development signing for team `JLX428R3Y7`, verified working on the intended physical iPhone.
- The pending Apple Developer Program License Agreement affects only Apple distribution services and is not a Revisr release blocker.

## Installation

1. Open `revisr.xcodeproj` in Xcode.
2. Connect and unlock the intended iPhone; keep Developer Mode enabled and trust the Mac if prompted.
3. Select the `revisr` target and confirm team `JLX428R3Y7` with automatic signing.
4. Select the connected physical iPhone as the run destination.
5. Choose Product → Run, or press Command-R.
6. Keep bundle identifier `com.kushagra.revisr` and install over the existing app. Do not uninstall during routine development.

Before a future migration-heavy update, copy and retain the existing app container using the proven physical-device backup procedure under `.qa/admissions-physical/pre-upgrade-appdata`.

## Current private-use acceptance

- Xcode physical-device installation: Passed.
- Debug installation and launch: Passed.
- Release installation and launch: Passed.
- Persistent-store migration: Passed; historical records preserved.
- Admissions import: 1,573 questions, 530 assignments, 30 programme days, and 80 source records.
- Revision Data Export: Snapshot JSON and Full Export ZIP implemented under Settings → Data, with local native sharing and no automatic upload.
- Regression: 108 tests passed, 0 failed.
- Crashes: no Revisr crash report detected during the device gate.
- Privacy/resources: passed; all question and solution PDFs are bundled only in the private local installation and remain excluded from revision exports.
- Known application blockers: none.

All TestFlight/App Store planning later in this document is retained only as historical release-gate evidence and is superseded by this private-use decision.

## Local Solution Bank — 22 August 2026

- Input handling remained local-only: 69 supplied PDFs were processed into 66 canonical unique PDFs after three semantically identical duplicate copies were reconciled. No internet search, scraping, download, or generated solution was used.
- Runtime inventory: 68 `SolutionDocument` records (66 new bundled PDFs plus the existing Maclaurin and Senior Kangaroo combined books) and 1,358 stable question links.
- Mapping audit: 1,328 verified direct-page mappings and 30 honest source-section mappings for Maclaurin. MAT 2010 Question 6 and MAT 2011 Question 7 have no direct mapping because those questions are absent from the supplied mark schemes.
- Coverage is computed, not claimed as complete: 55 question-paper sources are available with direct mapping, 3 are partial, and 21 / 213 questions remain pending across BMO, Yotta, and CSAT. Ten supplied solution PDFs are catalogued without an invented source relationship because the corresponding question papers are not present in this bank version.
- UI: Solution Bank is available from Topics and Settings without adding a tab. Source details show paper/solution state; Question Bank adds available/worked/mark-scheme/pending/no-direct filters; question, attempt, and Needs Review routes share direct solution access.
- Reveal safety: unattempted questions require confirmation; protected and future official benchmarks always require the stronger deliberate confirmation. Viewing a solution does not save an attempt or alter review/programme state.
- Exports: question/source solution metadata plus `solutions.json` are available; solution PDFs and full solution text remain excluded. Export ZIP validation explicitly rejects PDF entries.
- Import safety: solution entities are additive, stable-ID upserts are idempotent, and no PDF binary/full solution text is stored in SwiftData.
- Regression: 108 tests passed with 0 failures. Final result bundle: `.qa/solution-bank/final-tests.xcresult`.
- Builds: clean Debug tests and final Release builds passed for the iOS Simulator and signed generic iPhoneOS destination. Strict code-signature verification passed for bundle `com.kushagra.revisr`, team `JLX428R3Y7`.
- Final signed Release app: 59,416 KiB (58.02 MiB). It contains exactly 146 intended PDFs—80 question papers and 66 new solution resources—with an aggregate PDF payload of 53,308,385 bytes. No ZIP, workbook, report, QA artifact, database, or test result is present in the product.
- Clean simulator: first launch produced 1,573 questions, 80 sources, 68 solution documents, 1,358 links, and no fabricated attempts, sessions, or results. SQLite integrity returned `ok`.
- Physical migration: a new pre-upgrade backup was captured at `.qa/solution-bank/physical-pre-upgrade` before installation. The final signed Release was installed over the existing iPhone app with no uninstall.
- Physical post-install store: SQLite integrity returned `ok`; it contains 1,573 questions, 80 sources, 68 solutions, 1,358 links, the existing 1 attempt, 3 sessions, and 0 results.
- Preservation proof: all values in all 19 pre-existing domain tables (2,312 rows total) match the pre-upgrade backup after excluding only Core Data's internal `Z_ENT` and `Z_OPT` bookkeeping columns. Evidence: `.qa/solution-bank/final-domain-preservation.json`.
- Relaunch idempotence: every existing and new domain table remained identical across consecutive launches. Evidence: `.qa/solution-bank/relaunch-idempotence.json`.
- Stability/crash audit: the final candidate remained alive on the iPhone for more than two minutes and no later Revisr crash report appeared. One `0x8BADF00D` report at 13:05:47 was generated by the QA harness requesting process termination during a backup (the report explicitly records `FRONTBOARD` “Failed to terminate gracefully”); it was not an unprompted user-path exit. Evidence: `.qa/solution-bank/physical-crash-logs-final`.
- Remaining direct-touch checkpoint: manually open representative TMUA, MAT, SMC, combined, protected, attempted, pending, and Needs Review paths on the iPhone; verify PDF page/zoom/scroll and Airplane Mode. Automated build, resource, migration, integrity, and launch checks do not imply those touch interactions.

## Complete bundled question and PDF library — 22 August 2026

- The authoritative admissions model remains 1,573 unique questions, 530 assignments, 30 programme days, 1,003 standby questions, 40 protected official-TMUA-2022 questions, and 80 source records.
- All 80 source records now resolve uniquely to 80 bundled PDFs. The PDF payload is 24,281,111 bytes; the staging audit reports no missing, ambiguous, duplicate, or invalid mappings.
- The supplied 79-PDF archive was completed with the current official UAT-UK TMUA content specification. The runtime library uses stable source-ID filenames plus a deterministic checksum/page-count index.
- Source papers require no import or relink step. Settings reports actual bundle resolution, each source row opens inside Revisr, and question detail and attempt flows open the linked paper at the stored PDF page.
- PDFKit is configured for native vertical scrolling, zooming, page breaks, and mathematical notation. Page navigation occurs after initial PDF layout so it cannot snap back to page 1.
- Bundled resources are authoritative. The old app-managed file location is read-only migration fallback and no longer drives the availability UI.
- Revision Snapshot and Full Data Export still exclude source PDF binaries and internal paths. No network, account, analytics, advertising, tracking, third-party SDK, or cloud behavior was added.
- Clean-install validation produced exactly 1,573 questions, 80 sources, 530 assignments, 30 programme days, and zero fabricated attempts or results.
- Regression: 101 tests passed with 0 failures. Result bundle: `.qa/bundled-pdfs/BundledPDFsFullTests.xcresult`.
- Builds: Debug and Release passed for the iOS Simulator and signed generic iPhoneOS targets. The signed Release product passes strict code-signature verification for team `JLX428R3Y7`.
- Final signed Release app: 29,928 KiB (29.23 MiB), compared with 5,964 KiB (5.82 MiB) before bundling: an increase of 23,964 KiB (23.40 MiB). The PDF payload itself is 24,281,111 bytes (23.16 MiB).
- Final resource audit: exactly 80 PDFs; every size and SHA-256 matches `BundledAdmissionsPapers.json`; no workbook, ZIP, import/bundle report, database, QA artifact, or test result is present in the product.
- Clean simulator: Source Papers reports 80 of 80, no import-first controls are present, a standalone source opens in-app, and scheduled `TYLER-C-P1-Q06` opens on page 2 containing question 6. Relaunch retains the clean 1,573/80/530/30 store with no fabricated history.
- Physical migration: a new backup was captured before installation at `.qa/bundled-pdfs/physical-pre-upgrade/Application-Support`. Signed Debug and final signed Release builds installed in place and launched on the paired iPhone 15 without uninstalling.
- Post-Debug and post-Release SQLite integrity both return `ok`. All 19 persisted domain tables—including 1,573 questions, 80 sources, 530 assignments, 30 days, the existing 1 question attempt, 3 study sessions, and settings/topic state—are byte-for-byte logically identical to the pre-upgrade snapshot when SwiftData's internal `Z_OPT` revision counter is excluded.
- Post-upgrade backups: `.qa/bundled-pdfs/physical-post-debug/Application-Support` and `.qa/bundled-pdfs/physical-post-release/Application-Support`.
- Device crash-log audit after final launch found no Revisr crash report; evidence is under `.qa/bundled-pdfs/physical-crash-logs`.
- Manual on-device TMUA/SMC/MAT, scheduled/standby, attempt-return, and Airplane Mode checks remain a direct-touch checkpoint and are not implied by the automated device smoke test.

## Revision Data Export — 22 August 2026

- UI: Settings → Data → Export Revision Data provides a recommended Revision Snapshot, a Full Data Export, a privacy disclosure, and a copyable ChatGPT prompt.
- Formats: `revisr.export.revision.v1` JSON and `revisr.export.full.v1` ZIP, both at schema version 1.
- Contents: active TMUA profile/settings, programme progress and upcoming work, all attempt history, transparent performance metrics, Needs Review, specification coverage, results, standby and protected-question metadata, topics, and source inventory metadata.
- Exclusions: source PDFs, full copyrighted question wording, internal file paths, debug/migration logs, and inactive Mathematics/Further Mathematics data.
- Privacy: exports are generated locally and handed to the native iOS Share Sheet. Revisr contains no upload, ChatGPT, analytics, or other network integration.
- Automated validation: 97 tests passed with 0 failures, including schema, relationships, multiple attempts, dates/durations, protection, legacy exclusion, ZIP contents/safety, and read-only idempotence.
- Builds: Debug and Release passed for both the iOS Simulator and signed generic iPhoneOS targets.
- Simulator QA: Snapshot JSON and Full Export ZIP generated; both displayed the native Share Sheet and Save to Files action. Generated JSON parsed successfully and ZIP integrity passed with the expected entries and no PDFs.
- Physical upgrade: signed Debug and Release builds were installed over the existing app without uninstalling and launched on the intended iPhone 15.
- Physical export QA: Settings entry, Snapshot generation, Share Sheet, Save to Files, JSON opening, Full Export generation, ZIP opening, and expected archive contents were confirmed on the iPhone. The recovered device artifacts independently passed JSON, ZIP, manifest, relationship, privacy, and exclusion checks.
- Persistence evidence: pre-upgrade, post-Debug, and post-Release backups all retained 1,573 questions, 530 assignments, 30 programme days, 80 sources, 21 admissions topics, 18 planned blocks, 3 sessions, and all other domain-table counts. User-visible stored values were unchanged; startup only advanced SwiftData revision counters for normalized settings/subject rows.
- Post-export relaunch: passed. SQLite integrity returned `ok`, and every persisted domain value matched the pre-upgrade backup when SwiftData's internal revision counter was excluded.
- Preserved pre-upgrade store: `.qa/revision-export/physical-pre-upgrade/Application-Support`.
- Recovered physical exports: `.qa/revision-export/physical-generated/Revisr-Exports`.
- Result bundle: `.derived/export-final-tests/Logs/Test/Test-revisr-2026.08.22_11-04-31-+0100.xcresult`.
- Revision Data Export blockers: none.

## Historical Phase 5 evidence — superseded distribution context

Date: 15 August 2026

## Verdict

The codebase and local data model are technically ready for a signed-device candidate build. Revisr is **not yet ready for TestFlight or a public App Store release** because the connected iPhone cannot be provisioned with the current Xcode account state, so the required physical-device, VoiceOver, lock/unlock, keyboard, offline, and battery passes remain pending.

### Severity summary

- **Code blockers:** None found.
- **Device QA blocker:** Physical-device verification is pending because signing/provisioning failed.
- **Administrative blockers:** Configure the Apple Developer account/team and provisioning; create/confirm the App Store Connect record; host privacy-policy and support URLs; complete App Privacy, age-rating, accessibility, and product-page metadata.
- **Important before public release:** Complete the full physical accessibility/common-task pass before selecting any Accessibility Nutrition Labels.
- **Minor/future:** No new feature work is required for this release gate.

## Build

- Debug simulator build: **Passed**.
- Release simulator build: **Passed**, including App Store-oriented product validation.
- Release static analysis: **Passed**.
- Unsigned generic-iOS archive: **Passed** at `.derived/phase5-final3/Revisr.xcarchive`.
- Signed development-device build: **Blocked externally**. The connected iPhone was found, but Xcode has no usable account/profile for team `3JFF8U5HZ7` and bundle ID `com.kushagra.revisr`.
- Distribution validation/upload: Not attempted; a signed archive and App Store Connect access are unavailable.
- Xcode: 26.6 (17F113).
- Archive SDK: iPhoneOS 26.5.
- Minimum deployment target: iOS 17.0.
- Bundle ID: `com.kushagra.revisr` (valid reverse-domain form; confirm it is the intended permanent ID before creating the App Store record).
- Version/build: 1.0 (1). Settings reads and displays these bundle values correctly.
- Product/display name: product `revisr`; Home Screen display name `revisr`.
- Device family/orientation: iPhone only, portrait only. Mac-designed-for-iPhone/iPad availability was disabled because it has not been tested or polished. Catalyst and Vision are disabled.
- App Store category build setting: Education.
- Release settings: whole-module optimisation, dead-code stripping, assertions disabled, product validation enabled, dSYM generation enabled.
- App icon in the asset catalogue: 1024×1024, no alpha. The supplied artwork was used and appears correctly centred without a second rounded canvas.
- Final app bundle: approximately 2.5 MB, arm64. Only Apple system frameworks are linked; no embedded third-party frameworks or app extensions are present.
- Release archive contains no preview services, debug launch scenarios, runtime SwiftData stores, provisioning profile, or personal QA data.

## Tests

- Unit tests: **85 passed, 0 failed**.
- Final result bundle: `.derived/phase5-final-tests/Logs/Test/Test-revisr-2026.08.15_20-56-22-+0100.xcresult`.
- UI tests: None added. The project has no UI-test target, and a new brittle suite was not justified for this release-only phase.
- Added boundary/regression coverage: exam today/tomorrow/yesterday; leap day and midnight boundaries; clock rollback; recovered timer plus repeated-finish deduplication.
- Existing suite also covers seed idempotence, settings singleton/migration, timer pause/resume/finish, one-session invariants, result validation/deletion, plan overlaps/unavailable days, week/month/year boundaries, and historical snapshots after plan/topic edits or deletion.
- Clean production store: **Passed**. First launch produced 1 settings record, 3 subjects, 9 modules, 33 topics, 18 planned blocks, 0 sessions, 0 results, 4 focus items, and 1 timer state. Relaunch produced identical counts, proving the seed runs once and includes no fake history/results.
- Existing populated store: **Passed**. Before and after installing/launching the current release build, counts remained 1 settings, 3 subjects, 9 modules, 34 topics, 18 blocks, 13 sessions, 9 results, 4 focus items, and 1 timer state. The store hash remained `802523a2fd3b666fe88527669ff315f7ce44b514b67cb51d0498ae56dd4056ef`.
- Preserved store backup: `.qa/phase5/store-backup/Application-Support`.
- Runtime persistence check: Force-quit/relaunch retained the same running timer identity and timestamps and did not create a StudySession (17 before, 17 after). The timer continued from persisted timestamps.
- Current-run logs: No crash, assertion, error, or fault reproduced in the final Release run.

## Physical iPhone

**Pending physical-device verification.**

- Connected device detected: iPhone 15, iOS 26.6, UDID ending `A01E`.
- Install/build result: blocked because no development team is configured in the project/account, no account is logged in for the installed signing identity's team, and no matching development provisioning profile exists.
- Workflows tested on hardware: none; this report does not imply otherwise.
- Timer lock/unlock, backgrounding, restart, tactile targets, hardware keyboard/software keyboard behaviour, VoiceOver, Airplane Mode, and battery behaviour: not verified.

### Exact physical-device checklist

1. Sign into Xcode with the intended Apple Developer team, enable automatic signing, and install build 1 on the connected iPhone 15.
2. Run one end-to-end workflow: Today → start planned timer → lock/unlock → pause/lock → resume/background/use another app → force quit/relaunch → finish; confirm exactly one session.
3. Move a later plan block, log Quick Study, add/delete a result, change a topic status/Needs Review/notes, change a target, relaunch, and confirm all changes persist.
4. Exercise all five tabs with VoiceOver, including the Progress charts; then repeat critical tasks at maximum text size, Dark Mode, Increase Contrast, Button Shapes, and Reduce Motion.
5. Check the listed tab, timer, swipe, week-navigation, add/edit, percentage, and keyboard targets by touch.
6. Enable Airplane Mode and verify normal workflows; briefly observe active-session battery/activity and confirm no background capability indicator appears.

## Accessibility

| Feature | Status | Evidence and release recommendation |
| --- | --- | --- |
| VoiceOver | **Not verified** | Code-level labels/traits were reviewed and chart descriptions were improved, but no formal hardware common-task pass occurred. Do not select VoiceOver in App Store Connect yet. |
| Larger Text | **Partially verified** | Today, Plan, and Topics were visually inspected at the maximum accessibility size. Content reflows and remains scrollable, but every common task was not completed on hardware. Do not select until the physical pass. |
| Dark Interface | **Verified in representative simulator states** | Today and Progress were inspected in Dark Mode with Increase Contrast. Complete the hardware common-task pass before claiming the label. |
| Differentiate Without Color Alone | **Partially verified** | Selected days use a shape/selected trait; completion uses a checkmark; skipped/status/review states use text and symbols; charts use point symbols and accessible value summaries. Confirm with VoiceOver and display settings on device. |
| Sufficient Contrast | **Partially verified** | Representative light, dark, and Increase Contrast states were visually inspected. No formal contrast measurement or complete physical pass was performed. |
| Reduced Motion | **Partially verified** | Custom Today, Plan, Progress, and week-selector animations conditionally disable under Reduce Motion by code review. Runtime hardware verification remains pending. |
| Button Shapes | **Not verified** | Native controls are retained, but the display setting was not manually exercised. |

The active timer was changed from a nested one-second `TimelineView` to SwiftUI's efficient system timer text. Release-simulator CPU while the active timer was visible fell from a sustained roughly 83–87% to about 0.4%, while its persisted timestamp remained the source of truth.

## Visual/interaction audit evidence

1. **Today — healthy:** progress, active/next-plan hierarchy, and primary add control are clear. Evidence: `.qa/phase5/screenshots/01-today.png` and `.qa/phase5/screenshots/13-efficient-active-timer.png`.
2. **Plan — healthy:** week navigation, selected day, schedule, any-time section, and active-timer banner are understandable. Evidence: `.qa/phase5/screenshots/02-plan.png` and `.qa/phase5/screenshots/12-plan-en-US.png`.
3. **Progress — healthy:** range selection, study total/allocation, results, and chart hierarchy are coherent. Evidence: `.qa/phase5/screenshots/03-progress.png` and `.qa/phase5/screenshots/10-progress-dark-increased-contrast.png`.
4. **Topics — healthy:** search, Needs Review, status, hierarchy, and subject navigation are scannable. Evidence: `.qa/phase5/screenshots/04-topics.png` and `.qa/phase5/screenshots/08-topics-max-text.png`.
5. **Settings — healthy:** schedule, targets, exam, local-storage disclosure, version, and build are clear. Evidence: `.qa/phase5/screenshots/05-settings.png`.
6. **First launch/data upgrade — healthy:** clean and populated stores both rendered successfully. Evidence: `.qa/phase5/screenshots/01-clean-first-launch.png` and `.qa/phase5/screenshots/02-existing-store-launch.png`.

## Privacy and dependency audit

- Network/user-data transmission: no app source uses `URLSession`, network requests, CloudKit, web views, external APIs, remote logging, analytics, telemetry, advertising, or tracking. Normal app operation has no code-level network dependency.
- Data collection: the implementation stores study plans, settings, timer state, sessions, results, topic status, and notes locally with SwiftData. It has no account system.
- Third parties: no Swift Packages, CocoaPods, Carthage, binary frameworks, manually embedded frameworks, analytics SDKs, ads SDKs, or crash SDKs.
- Permissions: the final Info.plist has no camera, microphone, photos, location, contacts, calendars, motion, Bluetooth, or tracking usage descriptions.
- Entitlements/background modes: none. There is no iCloud, push, associated domains, app groups, HealthKit, Sign in with Apple, background audio, location, or processing entitlement.
- Required Reason APIs: no direct app use of UserDefaults/AppStorage, file timestamps/metadata, disk-space APIs, system uptime/boot time, or other audited Required Reason APIs was found.
- Privacy manifest: no `PrivacyInfo.xcprivacy` is present. Based on direct source and archive audits, no covered app API or third-party SDK currently requires one. Recheck the signed archive's App Privacy Report/validation warnings before upload; do not add invented reasons.
- Secrets/logging: no API keys, credentials, passwords, private model dumps, `print`, `debugPrint`, or `NSLog` calls were found.
- Offline: source and archive audits prove there is no app network dependency, but an actual Airplane Mode common-task pass remains part of the physical gate.

### Privacy-policy technical summary

Revisr stores the user's revision plan, study settings, active timer timestamps, study sessions, results, topic status, and notes in the app's local SwiftData store on the device. The audited app does not transmit this information, has no user account, and includes no third-party SDKs, analytics, advertising, or tracking. Deleting the app removes its local container. Individual plans, results, topics where permitted, and other editable records can be changed or deleted through the app. Cloud backup is not provided. The user can create a local revision export and choose its destination through the native iOS Share Sheet; nothing is uploaded automatically.

For App Store Connect, `Data Not Collected` is the technically consistent App Privacy answer if the signed upload remains identical to this audit. A public privacy-policy URL and support URL are still administrative requirements to complete before public distribution.

## Data integrity and failure handling

- Seed: idempotent; clean production seed contains curriculum/default configuration only, with no completed sessions or scores.
- Migration/upgrade: existing populated store opened without count or hash changes.
- Settings: duplicate settings are canonicalised to one record; covered by tests.
- Exactly-one-session: timer finish, completion without timer, repeated attempts, and relaunch/recovered-timer cases are covered; no duplicate was produced.
- Historical preservation: sessions retain subject/module/topic/activity snapshots after current plan/topic deletion or allowed edits; covered by tests.
- Timer clock safety: negative elapsed intervals are clamped to zero, so a backward wall-clock change does not corrupt accumulated time. Forward manual clock changes can increase elapsed time because wall-clock `Date` timestamps are intentionally the persisted source of truth; this is an acceptable documented limitation for the MVP.
- Save failures: critical mutation paths surface errors. Startup now displays a noninteractive data-preservation error screen if the persistent store cannot open rather than allowing normal use of an ephemeral store. Topic notes no longer use a silent save on view dismissal.
- Low-storage simulation: not performed destructively; physical-device save-failure conditions remain impractical to force safely.

## App Store preparation

### Recommended product information

- App Store name: **Revisr**. Keep the installed display label `revisr` if the lowercase styling is intentional.
- Primary category: **Education**. The core purpose is structured revision for TMUA, Mathematics, and Further Mathematics; Productivity can be considered as a secondary category if App Store Connect offers an appropriate choice.
- Subtitle options (all at or below 30 characters):
  - Plan and track your revision
  - Revision planner and tracker
  - Study planning made simple
- Promotional text: `Plan each study day, log focused sessions, track results, and keep important topics ready for review.`
- Keywords (96 characters): `revision,study planner,study tracker,TMUA,mathematics,further maths,exam planner,progress,topics`

### Description draft

Revisr is a focused, local-first revision planner for TMUA, Mathematics, and Further Mathematics.

Plan each study day, start a focused timer or log a quick session, and see how your actual study time compares with your plan. Track TMUA and A-Level results, keep important topics marked for review, and adjust your weekly targets as your priorities change.

Key features:

- Daily and weekly revision planning
- Scheduled and flexible study blocks
- Persistent study timer and quick study logging
- Study-time, subject-allocation, TMUA, and A-Level progress
- Topic status, review flags, notes, and recent study history
- Local on-device storage with no account, advertising, or analytics

Revisr is designed for a simple personal workflow. Your study data stays in the app on your iPhone. You can create a local revision export and choose where to save or share it; cloud backup and automatic uploads are not available.

### Review notes draft

`Revisr requires no account or network connection. All study data is stored locally. The app opens on Today; the five tabs cover Today, Plan, Progress, Topics, and Settings. No special credentials or hardware access are required.`

### Age-rating factual content

The app contains no violence, sexual content, profanity, gambling, contests, simulated gambling, alcohol/drug/tobacco references, horror/fear content, unrestricted web access, advertising, social networking, messaging, user-generated public content, or loot boxes. Complete Apple's current questionnaire with these factual answers; do not infer the resulting rating in advance.

### Screenshot plan

Use a dedicated safe demo store—not personal QA notes or results—and capture the actual UI at an accepted App Store device size:

1. Today with a credible daily plan, progress, and a clear next block.
2. Plan with a balanced populated week and selected day.
3. Active timer or Quick Study, showing the fastest logging workflow.
4. Progress with realistic study allocation and a factual TMUA trend.
5. Topics with several meaningful Needs Review items.

Marketing captions can be framed outside the captured app UI, but the shown interface must remain genuine.

### TestFlight “What to Test”

`Please test the daily plan from start to finish: create/edit/move a block, start/pause/resume/finish the timer across lock, backgrounding, force quit and relaunch, and confirm exactly one session. Also log Quick Study, add/delete a result, update a topic and Needs Review, change study targets, verify persistence after relaunch, and report any VoiceOver, Larger Text, Dark Mode, contrast, keyboard or touch-target issue.`

### TestFlight upload checklist

1. Sign into Xcode with the intended paid Apple Developer team and enable coherent automatic signing.
2. Confirm/register the permanent Bundle ID `com.kushagra.revisr` and create the matching App Store Connect app record.
3. Increment the build number for any build after 1 and create a signed Release archive.
4. Run Validate App and inspect signing, privacy-manifest, required-reason API, icon, and asset warnings.
5. Upload to App Store Connect and wait for processing; do not submit for review.
6. Complete export-compliance, App Privacy, age rating, accessibility, category, descriptions, support URL, and privacy-policy URL.
7. Add the developer's own iPhone as the first internal test; invite only a few trusted testers later if useful.
8. Run the physical checklist on the processed TestFlight build before considering public review.

## Remaining blockers

### Code blockers

None found.

### Device QA blockers

- **Blocker:** The connected iPhone cannot install the app until Xcode has a valid Apple Developer account/team and provisioning profile.
- **Blocker before claiming release readiness:** Physical timer lock/background/restart, tactile, keyboard, VoiceOver, offline, and battery checks have not been performed.

### Apple Developer / App Store Connect administrative blockers

- **Blocker for TestFlight:** Configure signing and produce/validate/upload a signed distribution archive.
- Confirm the permanent bundle identifier and create the App Store Connect record.
- Host public privacy-policy and support URLs.
- Complete the current App Privacy and age-rating questionnaires.
- Select Accessibility Nutrition Labels only after the documented physical common-task pass.
- Produce App Store screenshots from a dedicated safe demo store.

## Final acceptance

Revisr meets the local technical gates: Debug/Release/archive pass, 85 tests pass, static analysis passes, no current-run crash is reproduced, first-launch and existing-store persistence pass, exactly-one-session and historical-snapshot invariants pass, permissions/entitlements/dependencies/network activity are clean, and the final app icon/version/device-family configuration is coherent.

The overall release gate remains **pending** until the connected iPhone completes the physical and accessibility checklist and a signed Release archive is produced.

## Signing and Physical Device Gate

Gate resumed: 15 August 2026

### Signing configuration

- Bundle identifier: `com.kushagra.revisr` — preserved unchanged.
- Project development team: `JLX428R3Y7` for Debug and Release.
- Code-signing style: Automatic for Debug and Release.
- Signing certificate setting: Apple Development for Debug and Release.
- Provisioning profile/specifier: not explicitly configured; automatic signing resolved `iOS Team Provisioning Profile: *` for team `JLX428R3Y7`.
- Development certificate: resolved successfully through the selected Xcode account/team.
- Profile expiry: 8 August 2027.
- Signed application identifier: `JLX428R3Y7.com.kushagra.revisr`.
- Effective Debug entitlements: application identifier, team identifier, and development-only `get-task-allow`; no product capability entitlement was introduced.
- Xcode account status: **working**.
- Provisioning status: **working** for the connected development device.
- Signing changes made: the user selected the intended team in Xcode. No bundle-ID change, manual profile, duplicate certificate, revocation, or app-code change was made by this gate.

### Physical device state

- Device: `kushagra’s iphone`, iPhone 15 (`iPhone15,4`).
- iOS: 26.6.
- Connection: wired and connected.
- Pairing/trust: paired with manual pairing authentication.
- Developer Mode: enabled.
- Developer disk-image services: available.
- Xcode destination: detected and eligible as an iOS arm64 run destination.
- Debug build/sign: **passed** for arm64 iPhoneOS.
- Install: **passed**; the device reports Revisr 1.0 (1) installed as `com.kushagra.revisr`.
- Launch: **passed technically**; CoreDevice launched the application and confirmed the Revisr process remained running. Visual launch confirmation still requires looking at the iPhone.
- Installed icon: generated by the physical device at 1024×1024 and visually inspected; it is the expected Revisr artwork and is not a placeholder.
- Clean first-launch store: 1 settings, 3 subjects, 9 modules, 33 topics, 18 planned blocks, 0 sessions, 0 results, 4 focus items, and 1 timer state.
- Clean relaunch store: identical counts; no duplicate seed data or fake history/results were introduced.
- Tactile and manual physical QA: **pending**. No keyboard, timer lifecycle, VoiceOver, display-setting, offline, rotation, heating, or battery claim is made yet.

### Gate results

- VoiceOver: not tested.
- Larger Text: not tested on device.
- Reduce Motion: not tested on device.
- Increase Contrast: not tested on device.
- Dark Mode: not tested on device.
- Airplane Mode: not tested.
- Timer lock/background/relaunch: not tested on device.
- Battery/CPU sanity: not tested on device.
- Final regression count: existing Phase 5 result remains 85 passed, 0 failed; no app code changed during signing, installation, or launch.
- Signed archive: unavailable.
- TestFlight readiness: **NOT READY FOR TESTFLIGHT**.

### Current manual checkpoint

Revisr is installed and launched on the connected iPhone. The next gate requires direct observation and touch on the device: confirm the installed icon/Home Screen label, Today screen, five tabs, absence of a permission prompt, and basic launch stability. Continue with tactile and accessibility QA only after that visible checkpoint passes. Do not upload to TestFlight yet.

---

# Admissions Preparation System — 21 August 2026

## Current verdict

The admissions migration passes the automated, simulator, deterministic-import, signed Release-archive, privacy, resource, and physical iPhone technical-smoke gates. Both Debug and the signed Release archive installed over the preserved legacy store and launched successfully. Manual tactile and hardware accessibility checks are reported separately and are not implied by the technical smoke result.

## Product and data migration

- Mathematics and Further Mathematics no longer appear as active product domains or fresh-install seed content.
- Existing legacy subjects are marked inactive rather than deleted. Historical sessions, results, plan records, topic relationships, and their display snapshots remain intact.
- A clean installation creates the TMUA admissions domain and a lightweight TMUA compatibility subject for retained result history; it creates no school-subject programme and no fabricated attempts/results.
- Seed/import version 4 is idempotent. Reimport upserts by stable IDs, separates import-owned metadata from user-owned state, and marks obsolete imported records inactive without deleting history.
- TMUA is active. CSAT has a supported profile/status model but no active programme, scoring model, or fabricated content experience.

## Import and programme

- 1,573 workbook question rows; 1,573 unique IDs; 0 duplicates; 0 malformed rows.
- 530 assignments across 30 days; all joins and per-day counts validate.
- 1,003 standby questions and 40 protected official-TMUA-2022 questions.
- Historical state at that gate: 80 source records and 79 supplied PDFs. This is superseded by the complete bundled-library section above; the missing specification is now supplied from the official UAT-UK source and all 80 resolve.
- The importer is deterministic: an immediate rerun produced byte-identical manifest and report files.
- The supplied programme starts 22 August 2026 by default. Day/date resolution is calendar-derived from the user-owned programme start date.
- Official TMUA 2022 questions are always protected. Questions from future preserved benchmark papers are excluded from automatic extra-practice selection until their programme day passes.
- `CSAT` remains source-family provenance for 80 items (13 used by the authoritative supplied TMUA programme); this does not activate the separate CSAT domain.

## Attempts and UI

- Every attempt is append-only and records origin, outcome (Correct, Incorrect, Partial, or Skipped), error type, time, and timestamp. Repeat attempts remain in history while latest-result analytics update independently.
- Needs Review/Redo is independent of outcome and imported metadata. Error history is retained.
- Attempt timers persist timestamp-based running/paused state across backgrounding and relaunch.
- Today, Plan, Progress, Topics, Question Bank, question detail/attempt, Extra Practice, Sources, and Settings are implemented. CSAT shows an explicit inactive/not-started state.
- Progress distinguishes all-attempt statistics from latest-result-per-unique-question statistics and states the skipped-attempt denominator policy.
- Visible specification coverage is TMUA only. No Mathematics, Further Mathematics, A-Level, or Further Maths coverage appears in the active interface.

## Regression and release evidence

- Tests: 93 passed, 0 failed. Result: `.derived/admissions-final-tests/Logs/Test/Test-revisr-2026.08.21_23-10-12-+0100.xcresult`.
- Obsolete fresh-seed Mathematics/Further Mathematics hierarchy assertions and A-Level result-creation assertions were deliberately replaced with admissions-domain, TMUA-only, migration-preservation, import, programme, attempt, protection, selector, and timer tests. Unrelated timer, historical-snapshot, settings, analytics, and integrity tests remain.
- Clean simulator launch and all five root tabs were visually inspected. Default/light screenshots are in `.qa/admissions-screens/02-today-default.png` through `06-settings.png`; large-text Dark Mode evidence is `.qa/admissions-screens/01-today.png`.
- Release archive: `.derived/admissions-release-final/Revisr.xcarchive`; signed with team `JLX428R3Y7` and passed Xcode archive/product validation.
- Archive resource audit: no PDF, workbook, ZIP, or development-only import report is present. Only the required deterministic runtime manifest is bundled; the app bundle is approximately 3.5 MB.
- No third-party framework, Swift package, account, analytics, advertising, tracking, API, web view, CloudKit, or runtime network request exists. No permission usage-description or background-mode capability was introduced.

## Physical iPhone migration and smoke test

- Device: paired iPhone 15 (`iPhone15,4`), destination `00008120-0008195E0285A01E`.
- The existing app container was backed up before installation at `.qa/admissions-physical/pre-upgrade-appdata`.
- Pre-upgrade store: 3 subjects, 9 modules, 33 topics, 18 planned blocks, 3 historical sessions, 0 results, 4 weekly-focus records, and 1 timer state.
- Signed Debug arm64 device build, in-place installation, and launch: passed.
- Lightweight persistent-store migration and seed/import version 4: passed.
- Historical counts after migration are unchanged. The three session snapshots still identify Mathematics/Pure, Further Mathematics/FS1, and TMUA/Paper 2 with their original durations.
- Migrated subject state: TMUA active; Mathematics and Further Mathematics inactive.
- Admissions store after migration: 2 profiles, 1 programme, 30 days, 530 assignments, 1,573 questions, 80 sources, 21 topic states, 1 import-state record, and 0 fabricated attempts.
- Force-terminate/relaunch idempotence: passed; all legacy and admissions counts remained identical.
- Signed Release archive in-place installation and launch: passed. CoreDevice confirmed the Release process remained running and the installed app is labelled `Revisr` 1.0 (1).
- Post-Release container audit remained identical. No Revisr crash report was present in the device system crash-log domain.
- Post-upgrade evidence is preserved under `.qa/admissions-physical/post-upgrade-appdata`, `.qa/admissions-physical/post-relaunch-appdata`, `.qa/admissions-physical/post-release-appdata`, and `.qa/admissions-physical/post-release-crash-logs`.
- User-confirmed hands-on checks: VoiceOver, physical touch/tactile interaction, timer lock/background lifecycle, and Airplane Mode/offline use all passed on the physical iPhone.

## Remaining issues at the admissions-migration gate

- Historical note: the original supplied archive omitted `TMUA_Content_Specification(1).pdf`. The later complete-library build resolved this with the official UAT-UK document; it is no longer a current issue.

---

# TestFlight — Cancelled by product decision

Date started: 21 August 2026

## Candidate verification

- Candidate metadata remains Version 1.0, Build 1, bundle identifier `com.kushagra.revisr`, team `JLX428R3Y7`. App Store Connect contained no app records, so build 1 is unused and was preserved.
- Final pre-upload regression after the resource fix: 93 tests passed, 0 failed. Result: `.derived/testflight-final-tests/Logs/Test/Test-revisr-2026.08.21_23-44-07-+0100.xcresult`.
- No production feature code was modified during TestFlight preparation. The release report was updated to record the user's successful VoiceOver, tactile, timer lock/background, and Airplane Mode checks.
- One upload-audit build-setting fix excluded the development-only `AdmissionsImportReport.json` from application resources. The required runtime `AdmissionsManifest.json` remains bundled.
- Git exists but currently tracks zero files; the entire project is untracked. `.derived`, `.deriveddata`, `.qa`, user workspace state, and `.DS_Store` are ignored. No repository push or publication was performed.
- No workbook, source-paper PDF/ZIP, device store, screenshot, log, or xcresult exists in the production source/resource tree outside ignored QA/build locations.

## Cancelled status

- **Cancelled by product decision — private local use only.** App Store Connect contained no existing apps, and no app record was created.
- The updated Apple Developer Program License Agreement was relevant only to the abandoned Apple distribution workflow. Acceptance is not required for Revisr's private Xcode installation and is not a release blocker.
- Fresh final archive: `.derived/testflight-build-1-final/Revisr.xcarchive`. Archive creation and local product validation passed.
- Archive metadata: Revisr, `com.kushagra.revisr`, Version 1.0, Build 1, team `JLX428R3Y7`, arm64, iPhone-only, iOS 17 minimum.
- Final archive content audit passed: no workbook, PDF/ZIP source collection, import report, private device data, QA data, databases, screenshots, xcresult, logs, credentials, or permission/background-mode additions. Only the runtime admissions manifest is present.
- Upload, processing, tester configuration, and TestFlight installation were not started and will not be pursued under the private-use distribution decision.
- No upload, App Review submission, external testing, pricing, paid distribution, or public release action has occurred.
