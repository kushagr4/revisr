#!/usr/bin/env python3
"""Validate and stage Revisr admissions PDFs as stable app resources.

The source directory or ZIP keeps human filenames used by the workbook. The app
bundle receives one `<stableSourceID>.pdf` per manifest SourceDocument plus a
deterministic index/report. No developer-machine paths are written to outputs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from collections import Counter
from io import BytesIO
from pathlib import Path, PurePosixPath
from typing import Any

from pypdf import PdfReader
from atomic_generation import staged_output_set


def normalized_filename(filename: str) -> str:
    stem = Path(filename).stem.casefold()
    return re.sub(r"[^a-z0-9]+", "", stem)


def read_sources(path: Path) -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    if path.is_dir():
        candidates = sorted(path.rglob("*.pdf"))
        for candidate in candidates:
            if candidate.name in result:
                raise ValueError(f"Duplicate source filename: {candidate.name}")
            result[candidate.name] = candidate.read_bytes()
        return result

    if path.suffix.casefold() != ".zip":
        raise ValueError("PDF source must be a directory or .zip archive")

    with zipfile.ZipFile(path) as archive:
        for member in sorted(archive.namelist()):
            if not member.casefold().endswith(".pdf"):
                continue
            filename = PurePosixPath(member).name
            if filename in result:
                raise ValueError(f"Duplicate source filename: {filename}")
            result[filename] = archive.read(member)
    return result


def match_sources(
    expected: list[str], available: dict[str, bytes]
) -> tuple[dict[str, str], list[str], list[str]]:
    normalized: dict[str, list[str]] = {}
    for filename in available:
        normalized.setdefault(normalized_filename(filename), []).append(filename)

    matches: dict[str, str] = {}
    missing: list[str] = []
    ambiguous: list[str] = []
    for filename in expected:
        if filename in available:
            matches[filename] = filename
            continue
        candidates = normalized.get(normalized_filename(filename), [])
        if len(candidates) == 1:
            matches[filename] = candidates[0]
        elif len(candidates) > 1:
            ambiguous.append(filename)
        else:
            missing.append(filename)
    return matches, missing, ambiguous


def build_bundle(
    manifest_path: Path,
    source_path: Path,
    output_directory: Path,
    index_path: Path,
    report_path: Path,
) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text())
    sources = manifest["sources"]
    expected = [source["expectedFilename"] for source in sources]
    available = read_sources(source_path)
    matches, missing, ambiguous = match_sources(expected, available)

    matched_names = list(matches.values())
    duplicate_source_files = sorted(
        filename for filename, count in Counter(matched_names).items() if count > 1
    )
    stable_ids = [source["stableSourceID"] for source in sources]
    duplicate_resource_names = sorted(
        stable_id for stable_id, count in Counter(stable_ids).items() if count > 1
    )
    if missing or ambiguous or duplicate_source_files or duplicate_resource_names:
        raise ValueError(
            "Incomplete or ambiguous bundle mapping: "
            f"missing={missing}, ambiguous={ambiguous}, "
            f"duplicate mappings={duplicate_source_files}, "
            f"duplicate resource IDs={duplicate_resource_names}"
        )

    entries: list[dict[str, Any]] = []
    output_directory.mkdir(parents=True, exist_ok=True)
    expected_resource_names: set[str] = set()
    for source in sources:
        expected_filename = source["expectedFilename"]
        matched_filename = matches[expected_filename]
        payload = available[matched_filename]
        if not payload.startswith(b"%PDF"):
            raise ValueError(f"Not a PDF: {matched_filename}")
        page_count = len(PdfReader(BytesIO(payload)).pages)
        stable_id = source["stableSourceID"]
        resource_name = f"{stable_id}.pdf"
        expected_resource_names.add(resource_name)
        (output_directory / resource_name).write_bytes(payload)
        entries.append(
            {
                "sourceID": stable_id,
                "resourceName": stable_id,
                "resourceExtension": "pdf",
                "expectedFilename": expected_filename,
                "family": source["family"],
                "pageCount": page_count,
                "byteCount": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }
        )

    for existing in output_directory.glob("*.pdf"):
        if existing.name not in expected_resource_names:
            existing.unlink()

    entries.sort(key=lambda item: item["sourceID"])
    index = {
        "formatIdentifier": "revisr.bundled-admissions-papers.v1",
        "schemaVersion": 1,
        "sourceCount": len(entries),
        "totalBytes": sum(entry["byteCount"] for entry in entries),
        "sources": entries,
    }
    report = {
        "sourceDocumentsExpected": len(sources),
        "pdfFilesFound": len(available),
        "successfullyMatched": len(matches),
        "bundledResourcesWritten": len(entries),
        "bundledResourcesResolved": len(entries),
        "missing": missing,
        "ambiguous": ambiguous,
        "duplicateMappings": duplicate_source_files,
        "duplicateResourceIDs": duplicate_resource_names,
        "totalPDFBytes": index["totalBytes"],
    }

    index_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n")
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("pdf_source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    try:
        with staged_output_set([args.output, args.index, args.report]) as staged:
            report = build_bundle(
                args.manifest,
                args.pdf_source,
                staged[0],
                staged[1],
                staged[2],
            )
    except Exception as error:
        print(f"BUNDLE FAILED: {error}", file=sys.stderr)
        return 1

    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
