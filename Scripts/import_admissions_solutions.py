#!/usr/bin/env python3
"""Build Revisr's deterministic, local-only admissions solution bank.

Only PDFs present in the supplied archive (plus the two already-bundled combined
question/solution books) are indexed. The script deliberately does not download,
scrape, infer, or generate missing solutions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import zipfile
from collections import Counter, defaultdict
from io import BytesIO
from pathlib import Path, PurePosixPath
from typing import Any

from pypdf import PdfReader
from atomic_generation import staged_output_set


FORMAT_VERSION = 1
COMBINED_SOURCES = {
    "SRC-5158E147F9C37DAC": {
        "type": "combinedQuestionsAndSolutions",
        "provenance": "UK Mathematics Trust",
        "title": "Maclaurin Olympiad Past Papers & Solutions 2010–2014",
    },
    "SRC-742C39AEBEC39B0B": {
        "type": "combinedQuestionsAndSolutions",
        "provenance": "UK Mathematics Trust",
        "title": "Senior Kangaroo Past Papers & Solutions 2011–2014",
    },
}
KNOWN_UNMAPPED_QUESTION_IDS = {"MAT-2010-Q06", "MAT-2011-Q07"}


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def stable_id(prefix: str, value: str) -> str:
    return f"{prefix}-{digest(value)[:16].upper()}"


def normalized_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def pdf_record(filename: str, payload: bytes) -> dict[str, Any]:
    reader = PdfReader(BytesIO(payload))
    pages = [page.extract_text() or "" for page in reader.pages]
    if not pages:
        raise ValueError(f"PDF has no pages: {filename}")
    return {
        "filename": filename,
        "payload": payload,
        "pageCount": len(pages),
        "pages": pages,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "textSha256": digest(normalized_text("\n".join(pages))),
    }


def read_archive(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if path.is_dir():
        for candidate in sorted(path.rglob("*.pdf")):
            records.append(pdf_record(candidate.name, candidate.read_bytes()))
        return records
    if path.suffix.casefold() != ".zip":
        raise ValueError("Solution source must be a directory or .zip archive")
    with zipfile.ZipFile(path) as archive:
        for member in sorted(archive.namelist()):
            if member.casefold().endswith(".pdf"):
                records.append(
                    pdf_record(PurePosixPath(member).name, archive.read(member))
                )
    return records


def canonical_records(
    records: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        groups[record["textSha256"]].append(record)
    canonical: list[dict[str, Any]] = []
    duplicates: list[dict[str, str]] = []
    for group in groups.values():
        # Prefer the plainly named specimen files and the first numbered copy.
        group.sort(
            key=lambda item: (
                "early-specimen" in item["filename"].casefold(),
                "(2)" in item["filename"],
                len(item["filename"]),
                item["filename"].casefold(),
            )
        )
        winner = group[0]
        canonical.append(winner)
        for duplicate in group[1:]:
            duplicates.append(
                {
                    "duplicateFilename": duplicate["filename"],
                    "canonicalFilename": winner["filename"],
                    "reason": "identical extracted PDF content",
                }
            )
    canonical.sort(key=lambda item: item["filename"].casefold())
    duplicates.sort(key=lambda item: item["duplicateFilename"].casefold())
    return canonical, duplicates


def source_year(source: dict[str, Any]) -> int | None:
    if source.get("year") is not None:
        return int(source["year"])
    name = source["displayName"].casefold()
    match = re.search(r"(?:smc|qp)[-_ ]?(20\d{2}|\d{2})", name)
    if match:
        value = int(match.group(1))
        return value if value >= 2000 else 2000 + value
    if name == "a4smc_qp16":
        return 2016
    return None


def describe(filename: str) -> dict[str, Any]:
    lower = filename.casefold()
    match = re.search(r"\bimc[-_ ]?(20\d{2})", lower)
    if match:
        year = int(match.group(1))
        return {
            "family": "IMC",
            "year": year,
            "paper": None,
            "type": "workedSolution",
            "provenance": "UK Mathematics Trust",
            "title": f"Intermediate Mathematical Challenge {year} Solutions",
        }
    match = re.search(r"\bsmc[-_ ]?(20\d{2})", lower)
    if match:
        year = int(match.group(1))
        return {
            "family": "SMC",
            "year": year,
            "paper": None,
            "type": (
                "solutionsAndInvestigations"
                if year == 2013 and "extended" in lower
                else "workedSolution"
            ),
            "provenance": "UK Mathematics Trust",
            "title": f"Senior Mathematical Challenge {year} Solutions",
        }
    if lower.startswith("matsolutionsa") or lower.startswith("matsolutionsb"):
        paper = "Specimen 1" if lower.startswith("matsolutionsa") else "Specimen 2"
        return {
            "family": "MAT",
            "year": None,
            "paper": paper,
            "type": "markScheme",
            "provenance": "University of Oxford",
            "title": f"MAT {paper} Solutions",
        }
    match = re.search(r"matwebsolutions(\d{2})", lower)
    if match:
        year = 2000 + int(match.group(1))
        return {
            "family": "MAT",
            "year": year,
            "paper": None,
            "type": "markScheme",
            "provenance": "University of Oxford",
            "title": f"MAT {year} Mark Scheme",
        }
    match = re.search(r"tmua-(20\d{2})-paper-([12])", lower)
    if match:
        year, paper_number = int(match.group(1)), int(match.group(2))
        return {
            "family": "TMUA Practice" if year == 2016 else "TMUA Actual",
            "year": None if year == 2016 else year,
            "paper": f"Paper {paper_number}",
            "type": "workedSolution",
            "provenance": "UCLES",
            "title": f"TMUA {year} Paper {paper_number} Worked Answers",
        }
    if "specimen" in lower and "tmua" in lower:
        paper_number = int(re.search(r"paper[-_ ]?([12])", lower).group(1))
        return {
            "family": "TMUA Specimen",
            "year": None,
            "paper": f"Paper {paper_number}",
            "type": "workedSolution",
            "provenance": "UCLES",
            "title": f"TMUA Specimen Paper {paper_number} Worked Answers",
        }
    match = re.search(r"tmua mock (?:set )?([abcd]) answers", lower)
    if match:
        letter = match.group(1).upper()
        return {
            "family": "TMUA Mock",
            "year": 2026,
            "paper": "Set A",
            "mockLetter": letter,
            "type": "combinedQuestionsAndSolutions",
            "provenance": "Tyler Tutoring",
            "title": f"TMUA Mock {letter} Answers",
        }
    raise ValueError(f"Unrecognized supplied solution filename: {filename}")


def find_source(
    description: dict[str, Any], sources: list[dict[str, Any]]
) -> dict[str, Any] | None:
    if description.get("mockLetter"):
        wanted = f"tmua mock {'set ' if description['mockLetter'] in 'CD' else ''}{description['mockLetter']}"
        return next(
            (s for s in sources if s["displayName"].casefold() == wanted.casefold()),
            None,
        )
    candidates = [
        source
        for source in sources
        if source["family"] == description["family"]
        and source_year(source) == description.get("year")
        and source.get("paper") == description.get("paper")
    ]
    if len(candidates) > 1:
        raise ValueError(
            f"Ambiguous source match for {description['title']}: "
            + ", ".join(item["stableSourceID"] for item in candidates)
        )
    return candidates[0] if candidates else None


def line_page(pages: list[str], pattern: str, choose_last: bool = True) -> int | None:
    matches = [
        index
        for index, page in enumerate(pages, start=1)
        if re.search(pattern, page, flags=re.IGNORECASE | re.MULTILINE)
    ]
    if not matches:
        return None
    return matches[-1] if choose_last else matches[0]


def mapped_page(
    description: dict[str, Any], record: dict[str, Any], question: dict[str, Any]
) -> int | None:
    label = question["questionLabel"].strip()
    family = description["family"]
    pages = record["pages"]
    if description["type"] == "combinedQuestionsAndSolutions":
        return question.get("page")
    if family.startswith("TMUA"):
        return line_page(pages, rf"^\s*Question\s+{int(label)}\b")
    if family == "MAT":
        compact = label.replace(" ", "").upper()
        if compact.startswith("1") and len(compact) == 2:
            letter = re.escape(compact[1])
            return line_page(
                pages, rf"^\s*{letter}(?:\.|:|\s)", choose_last=False
            )
        number = int(compact)
        explicit = line_page(
            pages, rf"^\s*QUESTION\s+{number}\b", choose_last=False
        )
        if explicit is not None:
            return explicit
        # Long-form MAT questions begin their own section/page. Anchoring at the
        # page start avoids mistaking displayed formulae for a question heading.
        for index, page in enumerate(pages, start=1):
            if re.match(
                rf"^\s*(?:QUESTION\s+)?{number}(?:\s*$|\s*[:.]\s*)",
                page,
                flags=re.IGNORECASE | re.MULTILINE,
            ):
                return index
        return None
    if family in {"IMC", "SMC"}:
        number = int(label)
        if family == "SMC" and description.get("year") == 2018:
            if number <= 8:
                return 1
            if number <= 15:
                return 2
            if number <= 21:
                return 3
            return 4
        return line_page(pages, rf"^\s*{number}\.\s")
    return None


def combined_links(
    source: dict[str, Any], questions: list[dict[str, Any]], solution_id: str
) -> list[dict[str, Any]]:
    links: list[dict[str, Any]] = []
    is_maclaurin = source["family"] == "Maclaurin"
    maclaurin_pages = {2010: 12, 2011: 21, 2012: 25, 2013: 29, 2014: 34}
    senior_offsets = {2011: 15, 2012: 16, 2013: 16, 2014: 16}
    for question in questions:
        if is_maclaurin:
            page = maclaurin_pages[int(question["year"])]
            confidence = "sourceSection"
        else:
            page = int(question["page"]) + senior_offsets[int(question["year"])]
            confidence = "verifiedPage"
        links.append(make_link(solution_id, question, page, confidence))
    return links


def make_link(
    solution_id: str, question: dict[str, Any], page: int, confidence: str
) -> dict[str, Any]:
    question_id = question["externalQuestionID"]
    return {
        "stableLinkID": stable_id("SLK", f"{solution_id}|{question_id}"),
        "solutionID": solution_id,
        "questionID": question_id,
        "startPage": page,
        "endPage": page,
        "problemLabel": question["questionLabel"],
        "mappingConfidence": confidence,
    }


def build(
    admissions_path: Path, solution_source: Path, output_directory: Path
) -> tuple[dict[str, Any], dict[str, Any]]:
    admissions = json.loads(admissions_path.read_text())
    sources = admissions["sources"]
    questions = admissions["questions"]
    questions_by_source: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for question in questions:
        if question.get("sourceID"):
            questions_by_source[question["sourceID"]].append(question)

    supplied = read_archive(solution_source)
    canonical, duplicates = canonical_records(supplied)
    output_directory.mkdir(parents=True, exist_ok=True)
    for old in output_directory.glob("*.pdf"):
        old.unlink()

    documents: list[dict[str, Any]] = []
    links: list[dict[str, Any]] = []
    matched_files: list[str] = []
    unmatched_files: list[str] = []
    mapping_failures: list[dict[str, Any]] = []

    for record in canonical:
        description = describe(record["filename"])
        source = find_source(description, sources)
        semantic_key = (
            f"{source['stableSourceID']}|{description['type']}|{description['title']}"
            if source
            else f"unmatched|{description['family']}|{description.get('year')}|"
            f"{description.get('paper')}|{description['title']}"
        )
        solution_id = stable_id("SOL", semantic_key.casefold())
        target = output_directory / f"{solution_id}.pdf"
        target.write_bytes(record["payload"])
        document = {
            "stableSolutionID": solution_id,
            "displayName": description["title"],
            "solutionType": description["type"],
            "resourceName": solution_id,
            "resourceExtension": "pdf",
            "resourceContainer": "solutionBundle",
            "family": description["family"],
            "year": description.get("year"),
            "paper": description.get("paper"),
            "provenanceOrganization": description["provenance"],
            "provenanceTitle": description["title"],
            "originalFilename": record["filename"],
            "pageCount": record["pageCount"],
            "byteCount": len(record["payload"]),
            "sha256": record["sha256"],
            # The PDF itself is available even when this version of the Question
            # Bank has no matching SourceDocument. No question link is invented.
            "availability": "available",
            "isVerified": source is not None,
            "sourceID": source["stableSourceID"] if source else None,
        }
        documents.append(document)
        if not source:
            unmatched_files.append(record["filename"])
            continue
        matched_files.append(record["filename"])
        for question in questions_by_source[source["stableSourceID"]]:
            page = mapped_page(description, record, question)
            if page is None:
                mapping_failures.append(
                    {
                        "filename": record["filename"],
                        "questionID": question["externalQuestionID"],
                    }
                )
            else:
                links.append(make_link(solution_id, question, page, "verifiedPage"))

    for source_id, metadata in COMBINED_SOURCES.items():
        source = next(item for item in sources if item["stableSourceID"] == source_id)
        solution_id = stable_id(
            "SOL", f"{source_id}|{metadata['type']}|{metadata['title']}".casefold()
        )
        source_links = combined_links(
            source, questions_by_source[source_id], solution_id
        )
        links.extend(source_links)
        documents.append(
            {
                "stableSolutionID": solution_id,
                "displayName": metadata["title"],
                "solutionType": metadata["type"],
                "resourceName": source_id,
                "resourceExtension": "pdf",
                "resourceContainer": "sourcePaperBundle",
                "family": source["family"],
                "year": source.get("year"),
                "paper": source.get("paper"),
                "provenanceOrganization": metadata["provenance"],
                "provenanceTitle": metadata["title"],
                "originalFilename": source["expectedFilename"],
                "pageCount": source.get("pageCount"),
                "byteCount": None,
                "sha256": source.get("checksum"),
                "availability": (
                    "partial" if source["family"] == "Maclaurin" else "available"
                ),
                "isVerified": True,
                "sourceID": source_id,
            }
        )

    unexpected_mapping_failures = [
        failure
        for failure in mapping_failures
        if failure["questionID"] not in KNOWN_UNMAPPED_QUESTION_IDS
    ]
    if unexpected_mapping_failures:
        raise ValueError(
            f"Unable to map {len(unexpected_mapping_failures)} question pages; first failures: "
            f"{unexpected_mapping_failures[:10]}"
        )

    documents.sort(key=lambda item: item["stableSolutionID"])
    links.sort(key=lambda item: item["stableLinkID"])
    revision_payload = json.dumps(
        {"documents": documents, "links": links}, sort_keys=True, separators=(",", ":")
    )
    revision = digest(revision_payload)
    for document in documents:
        document["importRevision"] = revision
    for link in links:
        link["importRevision"] = revision
    manifest = {
        "formatVersion": FORMAT_VERSION,
        "importRevision": revision,
        "documents": documents,
        "links": links,
    }

    linked_by_source = Counter(
        document["sourceID"] for document in documents if document.get("sourceID")
    )
    direct_by_source = Counter()
    source_level_by_source = Counter()
    question_to_source = {
        question["externalQuestionID"]: question.get("sourceID") for question in questions
    }
    for link in links:
        source_id = question_to_source[link["questionID"]]
        if link["mappingConfidence"] == "verifiedPage":
            direct_by_source[source_id] += 1
        else:
            source_level_by_source[source_id] += 1
    source_statuses: dict[str, str] = {}
    for source in sources:
        count = source["questionUnitCount"]
        if count == 0:
            continue
        source_id = source["stableSourceID"]
        if direct_by_source[source_id] == count:
            source_statuses[source_id] = "available"
        elif linked_by_source[source_id] or source_level_by_source[source_id]:
            source_statuses[source_id] = "partial"
        else:
            source_statuses[source_id] = "pendingSource"
    family_breakdown: dict[str, dict[str, int]] = {}
    for family in sorted({source["family"] for source in sources if source["questionUnitCount"]}):
        family_sources = [
            source
            for source in sources
            if source["family"] == family and source["questionUnitCount"]
        ]
        family_breakdown[family] = {
            "sourceDocuments": len(family_sources),
            "questions": sum(source["questionUnitCount"] for source in family_sources),
            "availableSources": sum(
                source_statuses[source["stableSourceID"]] == "available"
                for source in family_sources
            ),
            "partialSources": sum(
                source_statuses[source["stableSourceID"]] == "partial"
                for source in family_sources
            ),
            "pendingSources": sum(
                source_statuses[source["stableSourceID"]] == "pendingSource"
                for source in family_sources
            ),
            "directQuestionMappings": sum(
                direct_by_source[source["stableSourceID"]] for source in family_sources
            ),
            "sourceLevelMappings": sum(
                source_level_by_source[source["stableSourceID"]]
                for source in family_sources
            ),
        }
    report = {
        "suppliedPDFFiles": len(supplied),
        "processedPDFFiles": len(supplied),
        "canonicalUniquePDFFiles": len(canonical),
        "duplicateCopies": duplicates,
        "matchedCanonicalFiles": matched_files,
        "unmatchedCanonicalFiles": unmatched_files,
        "ambiguousMatches": [],
        "newBundledSolutionDocuments": sum(
            document["resourceContainer"] == "solutionBundle" for document in documents
        ),
        "existingCombinedDocumentsReferenced": 2,
        "totalSolutionDocuments": len(documents),
        "newBundledPDFBytes": sum(len(record["payload"]) for record in canonical),
        "questionLinks": len(links),
        "directQuestionMappings": sum(direct_by_source.values()),
        "sourceLevelMappings": sum(source_level_by_source.values()),
        "noDirectMappingQuestions": sorted(
            failure["questionID"] for failure in mapping_failures
        ),
        "sourceCoverage": dict(sorted(Counter(source_statuses.values()).items())),
        "pendingQuestionCount": sum(
            source["questionUnitCount"]
            for source in sources
            if source_statuses.get(source["stableSourceID"]) == "pendingSource"
        ),
        "pendingFamilies": sorted(
            {
                (
                    "Yotta"
                    if source["family"] == "TMUA Mock"
                    and (source.get("paper") or "").startswith("Yotta")
                    else source["family"]
                )
                for source in sources
                if source_statuses.get(source["stableSourceID"]) == "pendingSource"
            }
        ),
        "familyBreakdown": family_breakdown,
        "warnings": [
            "No network sources were used.",
            "Unmatched supplied documents are bundled and catalogued without invented source links.",
            "Maclaurin links are source-section mappings because reliable per-question PDF pages are unavailable.",
        ],
    }
    return manifest, report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--admissions-manifest", type=Path, required=True)
    parser.add_argument("--solutions", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--manifest-output", type=Path, required=True)
    parser.add_argument("--report-output", type=Path, required=True)
    args = parser.parse_args()
    try:
        with staged_output_set(
            [args.output_directory, args.manifest_output, args.report_output]
        ) as staged:
            manifest, report = build(
                args.admissions_manifest, args.solutions, staged[0]
            )
            staged[1].parent.mkdir(parents=True, exist_ok=True)
            staged[2].parent.mkdir(parents=True, exist_ok=True)
            staged[1].write_text(json.dumps(manifest, indent=2) + "\n")
            staged[2].write_text(json.dumps(report, indent=2) + "\n")
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    import sys

    raise SystemExit(main())
