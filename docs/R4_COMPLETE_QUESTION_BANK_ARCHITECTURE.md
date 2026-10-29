# R4 complete question bank architecture

29 October 2026. R4 joins Revisr's two content sources into one catalogue that every question-facing feature reads:
- the owner's Google Drive TMUA collection;
- the original Revisr questions.

R4 replaces no model. The SwiftData stores, the content bank format, `tmua-selector-v3`, the approval pipeline and the planner engine are unchanged in shape. Saved diagnostics and attempts keep their pinned versions.

## Sources to catalogue

```
Google Drive TMUA folder ──(connector, read-only)──► revisr-content-private/drive/
   snapshots/drive-*.json, tmua-drive-inventory.json      (file identity, sync state)
        │
        │ indexed papers                                    revisr-content-private/catalogue/
        ├──────────────► revisr/Resources/AdmissionsManifest.json      supplement-index-*.json
        │                (library index: 136 documents,    duplicate-review-*.json
        │                 133 with questions, 2,600         topic-map.json
        │                 questions; unchanged)
        │                revisr/Resources/AdmissionsSolutionsManifest.json      │
        │                (120 solution documents, 2,364 question links)         │
        │                                                                       ▼
        │                          tools/build_reconciliation.py ──► revisr/Resources/
        │                                                              TMUACatalogueReconciliation.json
        │                                                              (topic map, 29 duplicate links,
        │                                                               10 supplement papers; metadata only)
        ▼
revisr-content-private/bank/*.json ──► Scripts/assemble_tmua_content.py ──► RevisrContentBank.json
   (126 original versions, 259 official study copies;     (build phase; public builds:
    corrections as new versions)                          approved manifest only)
                                                                        │
TMUAResourceProviders.json (credit, links, public access) ──────────────┤
                                                                        ▼
                    TMUAResourceCatalogue.sources(...)   papers this build may show, plus supplement papers
                    TMUAQuestionCatalogue.build(...)     one entry per canonical question
                                                                        │
          ┌──────────────────────┬─────────────────────┬────────────────┼──────────────────┐
          ▼                      ▼                     ▼                ▼                  ▼
   Questions tab          Topics tab counts      Diagnostic pool    Planner: worksheets,  Progress / Saved
   (Practice, Papers,                            (= automatic       paper sessions        (attempts, self-
    Sources, Saved)                               entries)                                 recorded results)
```

## Where each fact lives

| Fact | Owner | Notes |
|---|---|---|
| Question identity, paper, number, page, library topic, estimated difficulty | `AdmissionsManifest.json` (library index) or the supplement in `TMUACatalogueReconciliation.json` | Unchanged R1 file; its importer and SwiftData records are untouched |
| Solution documents and question-to-page links | `AdmissionsSolutionsManifest.json` | Unchanged |
| Duplicate and variant links, syllabus mapping of library topics, papers the library lacks | `TMUACatalogueReconciliation.json` | New in R4. Metadata only; the release gate rejects answer keys, Drive IDs and notes in it |
| Question content, keys, versions, review and rights | Private bank, assembled into `RevisrContentBank.json` | Public builds bundle only approved versions |
| Provider credit, links, public access | `TMUAResourceProviders.json` | |
| Drive file identity and sync state | `revisr-content-private/drive/` | Never bundled, never in public Git |

## The canonical catalogue (`revisr/Services/TMUA/TMUAQuestionCatalogue.swift`)

`TMUAQuestionCatalogue.build` is pure and testable without bundle files. `TMUACatalogueStore` caches one catalogue per launch and content context. It works in four steps:
1. Takes the papers this build may show (`TMUAResourceCatalogue`), including the R4 supplement papers.
2. Merges each reprint into its canonical question, provided the canonical question is in the same build. Otherwise the reprint stays available rather than disappearing.
3. Joins each indexed question to the bank item that marks it, so the item's stable ID becomes an alias.
4. Adds every eligible bank item whose paper is not in the library: the originals, and any future licensed questions.

The requested fields map onto existing or new properties:

| Requested | Catalogue entry |
|---|---|
| `questionID` | `id` (library ID such as `TMUA-2019-P1-Q11`, or the original's stable ID) |
| `versionID` | `item.versionKey`; `versionKeys` lists every version |
| `sourceID`, `sourceDocumentID` | `sourceID` (library or supplement paper); the Drive file mapping stays private |
| `questionNumber`, `paper` | `label`, `paperFit` (Paper 1, Paper 2, both, unclassified) |
| `examFamily` | `provider` and `sourceTitle` |
| `topicIDs`, `syllabusStrandIDs` | `topicKey` (syllabus topic); strand from the item for native questions |
| `difficultyEstimate`, `difficultyProvenance` | `difficulty`, `difficultyProvenance` (always an estimate) |
| `presentationMode` | `presentation`: native, document or external |
| `answerMode` | `answerMode`: automatic, self-marked, manual result, external viewing |
| `solutionReference` | `solutionResource` and `solutionPage`, or the item's own worked solution |
| `contentOrigin` | `origin`: Revisr original or Drive collection |
| `rightsStatus` | `rights`: Revisr's own, personal study copy, licensed, linked only |
| `publicationStatus`, `reviewStatus` | `publication`, `reviewStatus` |
| `sourceURL`, `displayAttribution` | `sourceURL`, `attribution` |
| `contentFingerprint` | `fingerprint`: the version key, or the paper's SHA-256 with page and question |
| `isSuperseded` | Superseded versions are not entries. They remain in `versionKeys`, and the bank resolves them for pinned diagnostics |

**"No marking" as an answer mode.** Reference documents (the handbook and the cheat sheet) contain no questions, so no catalogue entry has "no marking".

## Invariants (tested in `TMUACatalogueTests`)

- No question is listed twice, and an alias is never also a separate entry.
- The diagnostic's candidates are exactly the catalogue's automatically marked entries, in both builds.
- No entry without a bank item is marked automatically: no key is invented.
- New work uses the latest version; earlier versions stay resolvable.
- Topics map only to syllabus topics. Official papers keep their paper.
- A public build presents nothing itself, offers no restricted solution, and lists only providers whose own pages offer the papers.
