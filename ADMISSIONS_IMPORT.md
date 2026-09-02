# Admissions metadata and paper library

Revisr converts the supplied workbook into deterministic JSON during development, then validates and stages the complete PDF inventory as stable app resources. The app never parses Excel files or scans developer folders at launch. All 80 papers are part of this private build and open locally through PDFKit without setup or network access.

## Regenerate

Run with the bundled workspace Python runtime (or another Python with `openpyxl` and `pypdf`):

```sh
python3 Scripts/import_admissions_resources.py \
  /path/to/TMUA_Question_Bank_and_30_Day_Plan.xlsm \
  /path/to/papers.zip \
  --manifest revisr/Resources/AdmissionsManifest.json \
  --report revisr/Resources/AdmissionsImportReport.json
```

The metadata importer validates unique question IDs, assignment joins, programme days 1–30, per-day counts, source-name ambiguity, and availability of every scheduled source. Generated manifests and reports are staged privately and replace the prior output set only after successful validation. Question and source IDs are stable, and identical inputs produce byte-identical output. `AdmissionsImportReport.json` is explicitly excluded from the application bundle.

After preparing a directory or ZIP containing exactly one PDF for every manifest source, stage the runtime paper library with the workspace Python runtime (which includes `pypdf`):

```sh
python3 Scripts/bundle_admissions_papers.py \
  revisr/Resources/AdmissionsManifest.json \
  /path/to/complete-papers-directory-or.zip \
  --output revisr/Resources/AdmissionsPapers \
  --index revisr/Resources/BundledAdmissionsPapers.json \
  --report ADMISSIONS_BUNDLE_REPORT.json
```

The bundler fails on a missing, ambiguous, duplicated, invalid, or unreadable PDF. It writes each resource as `<stableSourceID>.pdf`, records its page count, byte count, and SHA-256 digest in a deterministic runtime index, and removes obsolete PDFs from the isolated staging directory. The resource directory, index, and report are committed as one rollback-capable output set; a failed run leaves the prior bundle untouched. Keep the development-only report at the repository root so it is not copied into the app.

The runtime decoder accepts the current V1 manifest and additive V2 manifests. V2 can carry canonical preparation streams, duplicate/validity metadata, media identity, and non-consecutive programme offsets without requiring those fields on legacy records.

## Current import

- Workbook revision: `b2e00ccf01cd5cb4ce03a030bf5926fce8dfa4f0d46059b1340e3998f6b7b9e6`
- Questions: 1,573 unique rows; 0 duplicates; 0 malformed rows
- Programme: 30 days; 530 assignments; 0 join/count failures
- Standby questions: 1,003
- Protected questions: 40 (official TMUA 2022)
- Sources: 80 expected; 80 uniquely matched and bundled
- Bundled PDF payload: 24,281,111 bytes
- Missing, ambiguous, or duplicate mappings: 0
- The supplied archive contained 79 PDFs. Its missing `TMUA_Content_Specification(1).pdf` was completed with the current official UAT-UK TMUA content specification before staging: <https://uat-wp.s3.eu-west-2.amazonaws.com/wp-content/uploads/2024/05/03165619/TMUA_Content_Specification.pdf>.

All workbook questions are part of the supplied TMUA-preparation bank. The 80 `CSAT`-family entries retain `CSAT` as source provenance—including 13 assignments explicitly selected by the workbook—but do not activate or populate a separate CSAT preparation programme.

## Ownership, upgrade, and reimport

Import-owned fields include question/source metadata, programme definitions, day definitions, assignment membership, and imported topic labels. User-owned state includes attempts, notes, independent Needs Review/Redo state, manual topic status, and the programme start date after first import. Reimport updates import-owned fields in place, marks obsolete imported records inactive, creates no duplicate questions, and never deletes user history.

The bundle is the authoritative paper source. Existing app-managed source links remain readable only as a migration fallback; no user import, relink, or remove workflow is required or exposed. Revision Snapshot and Full Data Export continue to include source inventory metadata but deliberately exclude PDF binaries.

The additive solution-resource workflow is documented separately in `SOLUTION_BANK.md`. It runs only after the question/source import so every solution link resolves through stable source and question IDs.
