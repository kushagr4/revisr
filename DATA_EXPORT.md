# Revisr Revision Data Export

Revisr can create local export files from **Settings → Data → Export Revision Data**. Exporting is read-only: it queries the current SwiftData state, writes a temporary file, and opens the native iOS Share Sheet. Revisr does not upload the file or contact ChatGPT or another external service.

## Revision Snapshot

Suggested filename: `Revisr-Revision-Snapshot-YYYY-MM-DD.json`

- Format identifier: `revisr.export.revision.v2`
- Schema version: `2`
- Encoding: UTF-8, pretty-printed JSON with sorted keys
- Dates: `YYYY-MM-DD`
- Timestamps: ISO 8601 with an explicit timezone offset
- Durations: integer seconds
- Percentages and accuracy: decimals from `0` to `1`

The stable top-level object contains:

| Key | Contents |
| --- | --- |
| `export` | Format, schema, export timestamp, and app version/build metadata |
| `profile` | Active admissions test, programme dates/day, TMUA exam date, and CSAT state |
| `tmua` | Targets, protection policy, and protected-question metadata |
| `programme` | Completion totals, current day, and overdue incomplete assignments |
| `performance` | Latest-result and attempt-level accuracy, timing, paper/difficulty/topic breakdowns, and error counts |
| `needsReview` | Question and topic review backlogs, including notes and latest attempt state |
| `specificationCoverage` | Coverage totals and stable per-item identifiers/states |
| `results` | TMUA test/mock result records |
| `standby` | Counts, breakdowns, and metadata for the standby question pool |
| `recentActivity` | The latest 50 attempts, newest first |
| `upcoming` | The current programme day plus the next seven days, or the first seven days before programme start |
| `questionCatalog` | Metadata for non-standby questions referenced elsewhere in the snapshot |
| `attemptHistory` | Every attempt for each attempted question, oldest first and explicitly numbered |

Attempt outcomes are `correct`, `incorrect`, `partial`, or `skipped`. Accuracy is `correct / (correct + incorrect + partial)`; skipped attempts are excluded. Latest-result metrics use the most recent non-skipped attempt for each unique question.

## Full Data Export

Suggested filename: `Revisr-Full-Export-YYYY-MM-DD.zip`

The archive format identifier is `revisr.export.full.v2`, schema version `2`. JSON is authoritative; CSV and Markdown files are convenience views. Empty optional categories such as attempts or results are omitted when there are no records. V2 adds optional canonical/effective preparation-stream provenance, validity/duplicate-review metadata, programme schedule offsets, solution media type, multi-source IDs, and video availability; the additive fields remain absent when decoding older V1 payloads.

- `README.md`
- `manifest.json`
- `revision-summary.md`
- `revision-snapshot.json`
- `questions.json` and `questions.csv`
- `attempts.json` and `attempts.csv`, when attempts exist
- `programme.json` and `programme-assignments.csv`, when a programme exists
- `specification-coverage.json` and `specification-coverage.csv`
- `results.json` and `results.csv`, when results exist
- `topics.json`
- `settings.json`
- `sources.json`
- `solutions.json` (document identity, type, provenance, availability, and mapping counts only)

`manifest.json` lists the exact files present in that archive. ZIP entries use UTF-8 names and the standards-compatible STORE method so the package opens in Files and conventional ZIP tools without an additional runtime dependency.

## Relationships and protection

Question IDs, programme assignment IDs, programme day IDs, topic/specification IDs, source IDs, result IDs, and attempt IDs are stable exported identifiers. Every attempt and assignment must resolve to an exported question before generation succeeds, question/specification IDs must be unique, and the generated archive is reopened by Revisr's validator to verify its entries.

Official TMUA 2022 questions remain marked as protected. Scheduled future official benchmark questions are marked `futureProtectedBenchmark` with their future programme day. Protected questions remain manually selectable but are excluded from automatic extra practice.

## Deliberate exclusions

Both export formats omit:

- Question-paper and solution PDF binaries
- Full solution text
- Full copyrighted question wording
- Absolute app-container or development-machine paths
- Debug logs and migration diagnostics
- Inactive legacy Mathematics and Further Mathematics study data from the Revision Snapshot

Question and source records include computed solution availability/type/status and stable solution IDs. Solution records contain human-readable inventory, provenance, verification, media type, additional stable source IDs, and direct/source-level mapping counts only. PDF/video contents and private local locations are never included.

## Suggested ChatGPT workflow

Use **Copy Suggested Prompt**, create either export, save or share it manually, and attach it to a ChatGPT conversation if desired. Revisr never invokes ChatGPT automatically and contains no AI planning engine or API integration.
