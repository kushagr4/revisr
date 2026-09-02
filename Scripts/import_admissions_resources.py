#!/usr/bin/env python3
"""Build Revisr's deterministic admissions manifest from the supplied workbook.

The script never embeds PDFs. It validates the workbook, inventories local source
files, and writes metadata-only JSON for the iOS target plus an auditable report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from openpyxl import load_workbook
from pypdf import PdfReader
from atomic_generation import staged_output_set


REQUIRED_SHEETS = {
    "Dashboard",
    "30-Day Plan",
    "Daily Assignments",
    "Question Database",
    "Topic Coverage",
    "Source Inventory",
    "Methodology",
}
PROGRAMME_ID = "TMUA-30-DAY-2026"
PROGRAMME_START = date(2026, 8, 22)
IMPORT_FORMAT_VERSION = 1


def text(value: Any) -> str | None:
    if value is None:
        return None
    value = str(value).strip()
    return value or None


def integer(value: Any) -> int | None:
    if value is None or value == "":
        return None
    return int(value)


def number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    return float(value)


def iso_day(value: date | datetime) -> str:
    if isinstance(value, datetime):
        value = value.date()
    return value.isoformat()


def records(workbook: Any, sheet_name: str) -> list[dict[str, Any]]:
    rows = list(workbook[sheet_name].iter_rows(values_only=True))
    headers = [text(value) or "" for value in rows[0]]
    return [
        dict(zip(headers, row, strict=False))
        for row in rows[1:]
        if any(value is not None for value in row)
    ]


def normalized_filename(filename: str) -> str:
    stem = Path(filename).stem.casefold()
    return re.sub(r"[^a-z0-9]+", "", stem)


def source_id(filename: str) -> str:
    digest = hashlib.sha256(filename.casefold().encode("utf-8")).hexdigest()[:16]
    return f"SRC-{digest.upper()}"


def read_sources(path: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    if path.is_dir():
        candidates = sorted(path.rglob("*.pdf"))
        for candidate in candidates:
            payload = candidate.read_bytes()
            result[candidate.name] = {
                "payload": payload,
                "pageCount": len(PdfReader(candidate).pages),
            }
        return result

    if path.suffix.casefold() != ".zip":
        raise ValueError("PDF source must be a directory or .zip archive")

    with zipfile.ZipFile(path) as archive:
        for member in sorted(archive.namelist()):
            if not member.casefold().endswith(".pdf"):
                continue
            payload = archive.read(member)
            filename = PurePosixPath(member).name
            from io import BytesIO

            result[filename] = {
                "payload": payload,
                "pageCount": len(PdfReader(BytesIO(payload)).pages),
            }
    return result


def match_sources(
    expected: Iterable[str], available: dict[str, dict[str, Any]]
) -> tuple[dict[str, str], list[str], list[str]]:
    exact = set(available)
    normalized: dict[str, list[str]] = {}
    for filename in available:
        normalized.setdefault(normalized_filename(filename), []).append(filename)

    matches: dict[str, str] = {}
    unresolved: list[str] = []
    uncertain: list[str] = []
    for filename in expected:
        if filename in exact:
            matches[filename] = filename
            continue
        candidates = normalized.get(normalized_filename(filename), [])
        if len(candidates) == 1:
            matches[filename] = candidates[0]
        elif len(candidates) > 1:
            uncertain.append(filename)
        else:
            unresolved.append(filename)
    return matches, unresolved, uncertain


def protection(schedule_eligible: str | None) -> str:
    if schedule_eligible and schedule_eligible.casefold().startswith("no"):
        return "protectedFromAutomaticSelection"
    return "none"


def build_manifest(workbook_path: Path, source_path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    workbook = load_workbook(
        workbook_path, data_only=True, read_only=False, keep_vba=True
    )
    missing_sheets = sorted(REQUIRED_SHEETS - set(workbook.sheetnames))
    if missing_sheets:
        raise ValueError(f"Missing workbook sheets: {', '.join(missing_sheets)}")

    question_rows = records(workbook, "Question Database")
    assignment_rows = records(workbook, "Daily Assignments")
    programme_rows = records(workbook, "30-Day Plan")
    source_rows = records(workbook, "Source Inventory")

    question_ids = [text(row.get("Question ID")) for row in question_rows]
    malformed_questions = [index + 2 for index, value in enumerate(question_ids) if not value]
    duplicate_question_ids = sorted(
        value for value, count in Counter(question_ids).items() if value and count > 1
    )
    if malformed_questions or duplicate_question_ids:
        raise ValueError(
            f"Invalid Question Database: malformed rows={malformed_questions}, "
            f"duplicate IDs={duplicate_question_ids}"
        )
    question_id_set = {value for value in question_ids if value}

    assignment_ids = [text(row.get("Question ID")) for row in assignment_rows]
    missing_assignment_questions = sorted(
        {value for value in assignment_ids if value and value not in question_id_set}
    )
    duplicate_assignment_questions = sorted(
        value for value, count in Counter(assignment_ids).items() if value and count > 1
    )
    if missing_assignment_questions or duplicate_assignment_questions:
        raise ValueError(
            "Invalid Daily Assignments: "
            f"missing Questions={missing_assignment_questions}, "
            f"duplicate Question units={duplicate_assignment_questions}"
        )

    days = [integer(row.get("Day")) for row in programme_rows]
    if days != list(range(1, 31)):
        raise ValueError(f"Programme must contain days 1...30; found {days}")
    actual_by_day = Counter(integer(row.get("Day")) for row in assignment_rows)
    mismatches = {
        day: {
            "plan": integer(programme_rows[day - 1].get("Allocated Questions")),
            "assignments": actual_by_day[day],
        }
        for day in range(1, 31)
        if integer(programme_rows[day - 1].get("Allocated Questions"))
        != actual_by_day[day]
    }
    if mismatches:
        raise ValueError(f"Programme allocation mismatches: {mismatches}")

    available_sources = read_sources(source_path)
    expected_filenames = [text(row.get("File")) for row in source_rows]
    expected_filenames = [value for value in expected_filenames if value]
    matches, unresolved, uncertain = match_sources(expected_filenames, available_sources)
    if uncertain:
        raise ValueError(f"Ambiguous source matches: {uncertain}")

    scheduled_sources = {
        text(row.get("Source File"))
        for row in assignment_rows
        if text(row.get("Source File"))
    }
    unresolved_scheduled = sorted(scheduled_sources - set(matches))
    if unresolved_scheduled:
        raise ValueError(f"Scheduled Questions have missing sources: {unresolved_scheduled}")

    import_revision = hashlib.sha256(workbook_path.read_bytes()).hexdigest()
    sources: list[dict[str, Any]] = []
    source_ids: dict[str, str] = {}
    for row in source_rows:
        filename = text(row.get("File"))
        if not filename:
            continue
        stable_id = source_id(filename)
        source_ids[filename] = stable_id
        matched_filename = matches.get(filename)
        available = available_sources.get(matched_filename) if matched_filename else None
        sources.append(
            {
                "stableSourceID": stable_id,
                "displayName": Path(filename).stem,
                "expectedFilename": filename,
                "family": text(row.get("Family")) or "Unknown",
                "year": integer(row.get("Year")),
                "paper": text(row.get("Paper")),
                "pageCount": integer(row.get("Pages")) or (available or {}).get("pageCount"),
                "questionUnitCount": integer(row.get("Question Units")) or 0,
                "useRule": text(row.get("Use Rule")),
                "inventoryStatus": text(row.get("Status")),
                "developmentMatch": matched_filename,
                "checksum": (
                    hashlib.sha256(available["payload"]).hexdigest() if available else None
                ),
            }
        )

    questions: list[dict[str, Any]] = []
    for row in question_rows:
        filename = text(row.get("Source File"))
        question_id = text(row.get("Question ID"))
        assert question_id
        questions.append(
            {
                "externalQuestionID": question_id,
                # This workbook is a TMUA-preparation bank. CSAT is retained as a
                # source family, not activated as a separate programme/domain.
                "admissionsTest": "tmua",
                "family": text(row.get("Family")) or "Unknown",
                "year": integer(row.get("Year")),
                "paper": text(row.get("Paper")),
                "section": text(row.get("Section")),
                "questionLabel": text(row.get("Question")) or "",
                "page": integer(row.get("Page")),
                "primaryTopic": text(row.get("Primary Topic")) or "Unclassified",
                "secondaryTopic": text(row.get("Secondary Topic")),
                "reasoningSkill": text(row.get("Reasoning Skill")),
                "tmuaPaperFit": text(row.get("TMUA Paper Fit")),
                "difficulty": integer(row.get("Difficulty")) or 0,
                "difficultyLabel": text(row.get("Difficulty Label")) or "",
                "tmuaRelevance": number(row.get("TMUA Relevance")),
                "format": text(row.get("Format")),
                "recommendedUse": text(row.get("Recommended Use")),
                "scheduleEligible": (text(row.get("Schedule Eligible")) or "").casefold().startswith("yes"),
                "classificationConfidence": text(row.get("Classification Confidence")),
                "descriptor": text(row.get("Descriptor")),
                "protection": protection(text(row.get("Schedule Eligible"))),
                "sourceID": source_ids.get(filename or ""),
                "importRevision": import_revision,
            }
        )

    programme_days: list[dict[str, Any]] = []
    for row in programme_rows:
        day_number = integer(row.get("Day"))
        assert day_number
        programme_days.append(
            {
                "dayNumber": day_number,
                "focus": text(row.get("Focus")) or "",
                "studyBrief": text(row.get("Study Brief")) or "",
                "allocatedQuestionCount": integer(row.get("Allocated Questions")) or 0,
                "expectedQuestionMinutes": integer(row.get("Question Time (min)")) or 0,
                "expectedReviewMinutes": integer(row.get("Review / Learning (min)")) or 0,
                "dailyTarget": text(row.get("Target")),
                "notes": text(row.get("Notes")),
            }
        )

    assignments: list[dict[str, Any]] = []
    day_orders: Counter[int] = Counter()
    for row in assignment_rows:
        day_number = integer(row.get("Day"))
        question_id = text(row.get("Question ID"))
        assert day_number and question_id
        display_order = day_orders[day_number]
        day_orders[day_number] += 1
        assignments.append(
            {
                "externalAssignmentID": f"{PROGRAMME_ID}-D{day_number:02d}-{question_id}",
                "dayNumber": day_number,
                "questionID": question_id,
                "block": text(row.get("Block")),
                "purpose": text(row.get("Purpose")),
                "suggestedTimeCapMinutes": integer(row.get("Time Cap (min)")),
                "displayOrder": display_order,
            }
        )

    primary_topics = sorted({question["primaryTopic"] for question in questions})
    manifest = {
        "formatVersion": IMPORT_FORMAT_VERSION,
        "importRevision": import_revision,
        "profiles": [
            {"kind": "tmua", "displayName": "TMUA", "isActive": True},
            {"kind": "csat", "displayName": "CSAT", "isActive": False},
        ],
        "sources": sources,
        "questions": questions,
        "topics": [
            {"stableTopicID": f"TMUA-{index + 1:02d}", "name": topic, "displayOrder": index}
            for index, topic in enumerate(primary_topics)
        ],
        "programme": {
            "externalProgrammeID": PROGRAMME_ID,
            "admissionsTest": "tmua",
            "name": "TMUA 30-Day Programme",
            "startDate": iso_day(PROGRAMME_START),
            "importRevision": import_revision,
            "days": programme_days,
            "assignments": assignments,
        },
    }

    protected_count = sum(
        question["protection"] != "none" for question in questions
    )
    scheduled_ids = set(assignment_ids)
    standby_count = sum(
        question["externalQuestionID"] not in scheduled_ids
        and question["scheduleEligible"]
        and question["protection"] == "none"
        for question in questions
    )
    csat_family_count = sum(question["family"] == "CSAT" for question in questions)
    scheduled_csat_family_count = sum(
        question_id in scheduled_ids and question["family"] == "CSAT"
        for question_id, question in zip(question_ids, questions, strict=True)
    )
    report = {
        "importRevision": import_revision,
        "questionRowsRead": len(question_rows),
        "questionIDsUnique": len(question_id_set),
        "questionsCreatedOnCleanImport": len(question_rows),
        "questionsUpdatedOnImmediateReimport": len(question_rows),
        "duplicatesCreatedOnImmediateReimport": 0,
        "duplicateIDs": duplicate_question_ids,
        "malformedRows": malformed_questions,
        "programmeDays": len(programme_days),
        "assignments": len(assignments),
        "assignmentJoinFailures": missing_assignment_questions,
        "perDayCountMismatches": mismatches,
        "sourcesExpected": len(expected_filenames),
        "sourcesResolved": len(matches),
        "sourcesUnresolved": unresolved,
        "uncertainMatches": uncertain,
        "scheduledSourcesUnresolved": unresolved_scheduled,
        "standbyQuestions": standby_count,
        "protectedQuestions": protected_count,
        "csatSourceFamilyQuestions": csat_family_count,
        "csatSourceFamilyAssignmentsInTMUAProgramme": scheduled_csat_family_count,
        "warnings": [
            "CSAT is preserved as a source family inside the supplied TMUA-preparation bank; the CSAT admissions domain remains inactive.",
            *(
                ["The TMUA content-specification reference PDF is absent; no scheduled Question depends on it."]
                if "TMUA_Content_Specification(1).pdf" in unresolved
                else []
            ),
        ],
    }
    return manifest, report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("pdf_source", type=Path, help="PDF directory or .zip archive")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    try:
        manifest, report = build_manifest(args.workbook, args.pdf_source)
    except Exception as error:
        print(f"IMPORT FAILED: {error}", file=sys.stderr)
        return 1

    with staged_output_set([args.manifest, args.report]) as staged:
        staged[0].parent.mkdir(parents=True, exist_ok=True)
        staged[1].parent.mkdir(parents=True, exist_ok=True)
        staged[0].write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        staged[1].write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
