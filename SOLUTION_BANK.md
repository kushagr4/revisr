# Revisr Local Solution Bank

The Solution Bank is an additive, local-only resource layer. It does not download, scrape, search for, or generate solutions. The current bank was built exclusively from `solutions-20260822T112702Z-1-001.zip` and the Maclaurin/Senior Kangaroo combined books already present in the validated question-paper library.

## Deterministic import

Run with the bundled workspace Python runtime (or Python with `pypdf`):

```sh
python3 Scripts/import_admissions_solutions.py \
  --admissions-manifest revisr/Resources/AdmissionsManifest.json \
  --solutions /path/to/solutions.zip \
  --output-directory revisr/Resources/AdmissionsSolutions \
  --manifest-output revisr/Resources/AdmissionsSolutionsManifest.json \
  --report-output ADMISSIONS_SOLUTIONS_REPORT.json
```

The importer validates PDF readability, semantically deduplicates equivalent copies, matches only unambiguous source identities, creates stable document/link IDs, maps reliable PDF pages, removes obsolete files only inside a private staging directory, and produces an auditable development report. The staged directory, manifest, and report replace prior outputs only after successful validation. Unmatched supplied PDFs remain bundled and catalogued without invented question links. Importing the same manifest repeatedly updates import-owned records in place and does not modify attempts, notes, review state, programme progress, topics, sessions, results, or settings.

## Current inventory and coverage

- Supplied PDFs processed: 69
- Unique supplied PDFs after three duplicate copies were reconciled: 66
- Existing combined question/solution books referenced without duplicating binaries: 2
- Total `SolutionDocument` records: 68
- Question links: 1,358
- Verified direct-page links: 1,328
- Source-section links: 30 Maclaurin questions
- Source papers with full direct mapping: 55
- Partial source papers: 3 (Maclaurin, MAT 2010, MAT 2011)
- Pending local solution sources: 21 papers / 213 questions across BMO, Yotta, and CSAT
- Supplied but currently unmatched solution documents: 10; these are visible in the Solution Bank with no fabricated source relationship
- Known no-direct-mapping questions: `MAT-2010-Q06` and `MAT-2011-Q07`, which are omitted from their supplied mark-scheme PDFs
- New solution PDF payload: 29,027,274 bytes

`ADMISSIONS_SOLUTIONS_REPORT.json` contains the complete duplicate list, matched/unmatched filenames, family breakdown, coverage, warnings, and exact byte totals. It is development evidence and is excluded from the app bundle.

## Runtime behavior and safety

PDF binaries are app resources named by stable solution ID; SwiftData stores identity, type, provenance, availability, source relationship, and page mappings only. Question pages are one-based and converted to PDFKit's zero-based index at display time. PDFKit provides native vertical scrolling and zoom.

The additive V2 runtime is also ready for local MP4 solution resources and documents shared by multiple source papers. Video links do not require page numbers or timestamps, and playback uses AVKit without recording an attempt. No videos were added to the current bundle in this infrastructure-only change.

Unattempted questions require confirmation before revealing a solution. Protected/future benchmark questions always require the stronger deliberate confirmation, even if an earlier attempt exists. Opening a solution never creates an attempt, changes Needs Review, or mutates programme state. Revision Snapshot and Full Data Export may include solution metadata but always exclude solution PDF binaries and full solution text.
