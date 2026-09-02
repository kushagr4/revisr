#!/usr/bin/env python3
"""Read-only Chunk 5 release-candidate audit for Revisr."""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from collections import Counter, defaultdict
from datetime import date, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "revisr" / "Resources"
EXPECTED_D1_D3_FINGERPRINT = "326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def connect_read_only(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    return connection


def logical_store_digest(connection: sqlite3.Connection) -> dict:
    tables = [row[0] for row in connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' ORDER BY name"
    ) if row[0] not in {"Z_METADATA", "Z_MODELCACHE", "Z_PRIMARYKEY"}]
    table_hashes: dict[str, str] = {}
    row_counts: dict[str, int] = {}
    for table in tables:
        # Z_OPT is Core Data's optimistic-lock revision counter. SwiftData may
        # increment it when a seed pass reassigns an unchanged value, so it is
        # transaction metadata rather than part of the logical user state.
        columns = [
            row[1]
            for row in connection.execute(f'PRAGMA table_info("{table}")')
            if row[1] != "Z_OPT"
        ]
        selected_columns = ",".join(f'"{column}"' for column in columns)
        records = list(connection.execute(f'SELECT {selected_columns} FROM "{table}" ORDER BY Z_PK'))
        digest = hashlib.sha256()
        for record in records:
            for column, value in zip(columns, record):
                digest.update(column.encode())
                digest.update(value if isinstance(value, bytes) else repr(value).encode())
                digest.update(b"\x00")
        table_hashes[table] = digest.hexdigest()
        row_counts[table] = len(records)
    return {
        "overallSHA256": hashlib.sha256(json.dumps(table_hashes, sort_keys=True).encode()).hexdigest(),
        "tableSHA256": table_hashes,
        "rowCounts": row_counts,
    }


def duplicate_values(connection: sqlite3.Connection, table: str, column: str, where: str = "1") -> list[str]:
    return [row[0] for row in connection.execute(
        f'SELECT "{column}" FROM "{table}" WHERE {where} GROUP BY "{column}" HAVING COUNT(*) > 1'
    )]


def historical_signature(connection: sqlite3.Connection) -> dict:
    attempts = [dict(row) for row in connection.execute(
        "SELECT hex(a.ZID) id,a.ZATTEMPTEDAT attemptedAt,a.ZOUTCOMERAWVALUE outcome,a.ZERRORTYPERAWVALUE errorType,a.ZNOTES notes,a.ZTIMETAKENSECONDS timeTakenSeconds,a.ZORIGINRAWVALUE origin,q.ZEXTERNALQUESTIONID questionID,p.ZEXTERNALASSIGNMENTID assignmentID FROM ZQUESTIONATTEMPT a LEFT JOIN ZADMISSIONSQUESTION q ON q.Z_PK=a.ZQUESTION LEFT JOIN ZPROGRAMMEASSIGNMENT p ON p.Z_PK=a.ZPROGRAMMEASSIGNMENT ORDER BY id"
    )]
    sessions = [dict(row) for row in connection.execute(
        "SELECT hex(ZID) id,ZDATE date,ZDURATION duration,ZACTIVITYRAWVALUE activity,ZACTUALSTARTDATE actualStart,ZENDDATE endDate,ZNOTES notes,ZSUBJECTNAMESNAPSHOT subjectName,ZMODULENAMESNAPSHOT moduleName,ZTOPICNAMESNAPSHOT topicName FROM ZSTUDYSESSION ORDER BY id"
    )]
    results = [dict(row) for row in connection.execute("SELECT * FROM ZSTUDYRESULT ORDER BY Z_PK")]
    review = [dict(row) for row in connection.execute(
        "SELECT ZEXTERNALQUESTIONID questionID,ZREVIEWSTATERAWVALUE reviewState,ZUSERNOTES notes FROM ZADMISSIONSQUESTION WHERE ZREVIEWSTATERAWVALUE<>'none' ORDER BY questionID"
    )]
    topic_state = [dict(row) for row in connection.execute(
        "SELECT ZSTABLETOPICID topicID,ZMANUALSTATUSRAWVALUE manualStatus,ZNEEDSREVIEW needsReview,ZNOTES notes FROM ZADMISSIONSTOPICSTATE ORDER BY topicID"
    )]
    d1_d3 = [dict(row) for row in connection.execute(
        "SELECT d.ZDAYNUMBER dayNumber,a.ZEXTERNALASSIGNMENTID assignmentID,a.ZISIMPORTEDACTIVE active,CASE WHEN EXISTS(SELECT 1 FROM ZQUESTIONATTEMPT t WHERE t.ZPROGRAMMEASSIGNMENT=a.Z_PK AND t.ZOUTCOMERAWVALUE<>'skipped') THEN 1 ELSE 0 END completed FROM ZPROGRAMMEASSIGNMENT a JOIN ZPROGRAMMEDAY d ON d.Z_PK=a.ZPROGRAMMEDAY WHERE d.ZDAYNUMBER<=3 ORDER BY dayNumber,a.ZDISPLAYORDER,assignmentID"
    )]
    return {"attempts": attempts, "sessions": sessions, "results": results, "review": review, "topicState": topic_state, "d1D3": d1_d3}


def canonical_json_hash(value: object) -> str:
    payload = json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def resource_path_for_solution(document: dict) -> Path:
    extension = document["resourceExtension"]
    if document["resourceContainer"] == "sourcePaperBundle":
        folder = "AdmissionsPapers"
    elif extension == "mp4":
        folder = "AdmissionsVideos"
    else:
        folder = "AdmissionsSolutions"
    return RESOURCES / folder / f'{document["resourceName"]}.{extension}'


def source_manifest() -> dict:
    roots = [ROOT / "revisr", ROOT / "revisrTests", ROOT / "Scripts", ROOT / "revisr.xcodeproj"]
    suffixes = {".swift", ".py", ".pbxproj", ".xcscheme", ".plist", ".json"}
    rows = []
    for source_root in roots:
        for path in sorted(source_root.rglob("*")):
            if not path.is_file() or path.suffix not in suffixes:
                continue
            if "xcuserdata" in path.parts or path.is_relative_to(RESOURCES / "AdmissionsPapers"):
                continue
            if path.is_relative_to(RESOURCES / "AdmissionsSolutions") or path.is_relative_to(RESOURCES / "AdmissionsVideos"):
                continue
            rows.append({"path": str(path.relative_to(ROOT)), "sha256": sha256_file(path), "bytes": path.stat().st_size})
    return {
        "fileCount": len(rows),
        "overallSHA256": hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest(),
        "files": rows,
    }


def run_audit(store_path: Path, baseline_store_path: Path | None = None) -> dict:
    admissions_path = RESOURCES / "AdmissionsManifest.json"
    solutions_path = RESOURCES / "AdmissionsSolutionsManifest.json"
    programme_path = RESOURCES / "AdmissionsProgrammeMigration.json"
    admissions = load_json(admissions_path)
    solutions = load_json(solutions_path)
    programme = load_json(programme_path)
    questions = admissions["questions"]
    sources = admissions["sources"]
    documents = solutions["documents"]
    links = solutions["links"]
    question_ids = {item["externalQuestionID"] for item in questions}
    source_ids = {item["stableSourceID"] for item in sources}
    solution_ids = {item["stableSolutionID"] for item in documents}

    resource_records = []
    missing_resources = []
    checksum_mismatches = []
    for source in sources:
        path = RESOURCES / "AdmissionsPapers" / f'{source["stableSourceID"]}.pdf'
        record = {"kind": "source", "id": source["stableSourceID"], "path": str(path.relative_to(ROOT)), "exists": path.is_file()}
        if path.is_file():
            record.update({"bytes": path.stat().st_size, "sha256": sha256_file(path)})
            expected_checksum = (source.get("checksum") or "").removeprefix("sha256:")
            if expected_checksum and record["sha256"] != expected_checksum:
                checksum_mismatches.append(source["stableSourceID"])
        else:
            missing_resources.append(source["stableSourceID"])
        resource_records.append(record)
    for document in documents:
        path = resource_path_for_solution(document)
        record = {"kind": document.get("mediaKind") or document["resourceExtension"], "id": document["stableSolutionID"], "path": str(path.relative_to(ROOT)), "exists": path.is_file()}
        if path.is_file():
            record.update({"bytes": path.stat().st_size, "sha256": sha256_file(path)})
            expected_checksum = (document.get("sha256") or "").removeprefix("sha256:")
            if expected_checksum and record["sha256"] != expected_checksum:
                checksum_mismatches.append(document["stableSolutionID"])
        else:
            missing_resources.append(document["stableSolutionID"])
        resource_records.append(record)

    pdf_files = sorted(RESOURCES.rglob("*.pdf"))
    video_files = sorted(RESOURCES.rglob("*.mp4"))
    resource_files = pdf_files + video_files
    bundle_inventory = {
        "pdfCount": len(pdf_files),
        "videoCount": len(video_files),
        "payloadBytes": sum(path.stat().st_size for path in resource_files),
        "resourceDirectoryBytes": sum(path.stat().st_size for path in RESOURCES.rglob("*") if path.is_file()),
        "duplicateBinaryGroups": [values for values in defaultdict(list).values()],
        "resources": resource_records,
    }
    binary_groups: dict[str, list[str]] = defaultdict(list)
    for path in resource_files:
        binary_groups[sha256_file(path)].append(str(path.relative_to(ROOT)))
    bundle_inventory["duplicateBinaryGroups"] = [paths for paths in binary_groups.values() if len(paths) > 1]

    start = date(2026, 8, 22)
    dates = {item["dayNumber"]: (start + timedelta(days=item["scheduleOffsetDays"])).isoformat() for item in programme["days"]}
    assignments_by_day: dict[int, list[dict]] = defaultdict(list)
    days_by_question: dict[str, set[int]] = defaultdict(set)
    for assignment in programme["assignments"]:
        assignments_by_day[assignment["dayNumber"]].append(assignment)
        days_by_question[assignment["questionID"]].add(assignment["dayNumber"])
    same_day_duplicates = [
        {"day": day, "questionID": question_id}
        for day, assignments in assignments_by_day.items()
        for question_id, count in Counter(item["questionID"] for item in assignments).items() if count > 1
    ]
    cross_day_repeats = {question_id: sorted(days) for question_id, days in days_by_question.items() if len(days) > 1}

    primary_counts = Counter(item.get("primaryPreparationStream") or "nil" for item in questions)
    intended_counts = Counter(use for item in questions for use in item.get("intendedUses", []))
    tmua_2022 = [item for item in questions if item["family"] == "TMUA Actual" and item.get("year") == 2022]
    scheduled_ids = {item["questionID"] for item in programme["assignments"]}
    d1_d3_manifest = {
        "days": [item for item in admissions["programme"]["days"] if item["dayNumber"] <= 3],
        "assignments": [item for item in admissions["programme"]["assignments"] if item["dayNumber"] <= 3],
    }
    d1_d3_fingerprint = canonical_json_hash(d1_d3_manifest)

    connection = connect_read_only(store_path)
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        digest = logical_store_digest(connection)
        counts = {
            "questions": connection.execute("SELECT COUNT(*) FROM ZADMISSIONSQUESTION").fetchone()[0],
            "sources": connection.execute("SELECT COUNT(*) FROM ZSOURCEDOCUMENT").fetchone()[0],
            "solutions": connection.execute("SELECT COUNT(*) FROM ZSOLUTIONDOCUMENT").fetchone()[0],
            "links": connection.execute("SELECT COUNT(*) FROM ZQUESTIONSOLUTIONLINK").fetchone()[0],
            "attempts": connection.execute("SELECT COUNT(*) FROM ZQUESTIONATTEMPT").fetchone()[0],
            "sessions": connection.execute("SELECT COUNT(*) FROM ZSTUDYSESSION").fetchone()[0],
            "results": connection.execute("SELECT COUNT(*) FROM ZSTUDYRESULT").fetchone()[0],
            "storedAssignments": connection.execute("SELECT COUNT(*) FROM ZPROGRAMMEASSIGNMENT").fetchone()[0],
            "activeAssignments": connection.execute("SELECT COUNT(*) FROM ZPROGRAMMEASSIGNMENT WHERE ZISIMPORTEDACTIVE=1").fetchone()[0],
            "completedAssignments": connection.execute("SELECT COUNT(DISTINCT ZPROGRAMMEASSIGNMENT) FROM ZQUESTIONATTEMPT WHERE ZOUTCOMERAWVALUE <> 'skipped'").fetchone()[0],
            "programmeDays": connection.execute("SELECT COUNT(*) FROM ZPROGRAMMEDAY WHERE ZISIMPORTEDACTIVE=1").fetchone()[0],
            "needsReview": connection.execute("SELECT COUNT(*) FROM ZADMISSIONSQUESTION WHERE ZREVIEWSTATERAWVALUE='needsReview'").fetchone()[0],
            "redo": connection.execute("SELECT COUNT(*) FROM ZADMISSIONSQUESTION WHERE ZREVIEWSTATERAWVALUE='redo'").fetchone()[0],
        }
        dangling = {
            "questionSource": connection.execute("SELECT COUNT(*) FROM ZADMISSIONSQUESTION q LEFT JOIN ZSOURCEDOCUMENT s ON s.Z_PK=q.ZSOURCEDOCUMENT WHERE q.ZSOURCEDOCUMENT IS NOT NULL AND s.Z_PK IS NULL").fetchone()[0],
            "linkQuestion": connection.execute("SELECT COUNT(*) FROM ZQUESTIONSOLUTIONLINK l LEFT JOIN ZADMISSIONSQUESTION q ON q.Z_PK=l.ZQUESTION WHERE q.Z_PK IS NULL").fetchone()[0],
            "linkSolution": connection.execute("SELECT COUNT(*) FROM ZQUESTIONSOLUTIONLINK l LEFT JOIN ZSOLUTIONDOCUMENT s ON s.Z_PK=l.ZSOLUTIONDOCUMENT WHERE s.Z_PK IS NULL").fetchone()[0],
            "assignmentQuestion": connection.execute("SELECT COUNT(*) FROM ZPROGRAMMEASSIGNMENT a LEFT JOIN ZADMISSIONSQUESTION q ON q.Z_PK=a.ZQUESTION WHERE a.ZISIMPORTEDACTIVE=1 AND q.Z_PK IS NULL").fetchone()[0],
            "attemptQuestion": connection.execute("SELECT COUNT(*) FROM ZQUESTIONATTEMPT a LEFT JOIN ZADMISSIONSQUESTION q ON q.Z_PK=a.ZQUESTION WHERE q.Z_PK IS NULL").fetchone()[0],
            "attemptAssignment": connection.execute("SELECT COUNT(*) FROM ZQUESTIONATTEMPT a LEFT JOIN ZPROGRAMMEASSIGNMENT p ON p.Z_PK=a.ZPROGRAMMEASSIGNMENT WHERE a.ZPROGRAMMEASSIGNMENT IS NOT NULL AND p.Z_PK IS NULL").fetchone()[0],
        }
        duplicates = {
            "questionIDs": duplicate_values(connection, "ZADMISSIONSQUESTION", "ZEXTERNALQUESTIONID"),
            "sourceIDs": duplicate_values(connection, "ZSOURCEDOCUMENT", "ZSTABLESOURCEID"),
            "solutionIDs": duplicate_values(connection, "ZSOLUTIONDOCUMENT", "ZSTABLESOLUTIONID"),
            "programmeDayIDs": duplicate_values(connection, "ZPROGRAMMEDAY", "ZEXTERNALDAYID"),
            "activeAssignmentIDs": duplicate_values(connection, "ZPROGRAMMEASSIGNMENT", "ZEXTERNALASSIGNMENTID", "ZISIMPORTEDACTIVE=1"),
        }
        subjects = dict(connection.execute("SELECT ZNAME,ZISACTIVEFORSTUDY FROM ZSUBJECT"))
        active_d4_ids = [row[0] for row in connection.execute(
            "SELECT a.ZEXTERNALASSIGNMENTID FROM ZPROGRAMMEASSIGNMENT a JOIN ZPROGRAMMEDAY d ON d.Z_PK=a.ZPROGRAMMEDAY WHERE a.ZISIMPORTEDACTIVE=1 AND d.ZDAYNUMBER>=4 ORDER BY a.ZEXTERNALASSIGNMENTID"
        )]
        d1_d3 = [dict(row) for row in connection.execute(
            "SELECT d.ZDAYNUMBER,a.ZEXTERNALASSIGNMENTID,a.ZISIMPORTEDACTIVE,CASE WHEN EXISTS(SELECT 1 FROM ZQUESTIONATTEMPT t WHERE t.ZPROGRAMMEASSIGNMENT=a.Z_PK AND t.ZOUTCOMERAWVALUE<>'skipped') THEN 1 ELSE 0 END AS completed FROM ZPROGRAMMEASSIGNMENT a JOIN ZPROGRAMMEDAY d ON d.Z_PK=a.ZPROGRAMMEDAY WHERE d.ZDAYNUMBER<=3 ORDER BY d.ZDAYNUMBER,a.ZDISPLAYORDER,a.ZEXTERNALASSIGNMENTID"
        )]
        release_history = historical_signature(connection)
    finally:
        connection.close()

    historical_comparison = None
    if baseline_store_path is not None:
        baseline_connection = connect_read_only(baseline_store_path)
        try:
            baseline_history = historical_signature(baseline_connection)
        finally:
            baseline_connection.close()
        historical_comparison = {
            key: {"unchanged": baseline_history[key] == release_history[key], "beforeCount": len(baseline_history[key]), "afterCount": len(release_history[key])}
            for key in baseline_history
        }

    invalid_page_links = []
    docs_by_id = {item["stableSolutionID"]: item for item in documents}
    for link in links:
        document = docs_by_id[link["solutionID"]]
        start_page, end_page = link.get("startPage"), link.get("endPage")
        if start_page is not None and (
            start_page < 1
            or (end_page is not None and end_page < start_page)
            or (document.get("pageCount") and start_page > document["pageCount"])
            or (document.get("pageCount") and end_page is not None and end_page > document["pageCount"])
        ):
            invalid_page_links.append(link["stableLinkID"])
        start_time, end_time = link.get("startTimeSeconds"), link.get("endTimeSeconds")
        if start_time is not None and (start_time < 0 or (end_time is not None and end_time < start_time)):
            invalid_page_links.append(link["stableLinkID"])

    manifest_relationship_errors = {
        "questionSources": sorted(item["externalQuestionID"] for item in questions if item.get("sourceID") not in source_ids),
        "solutionSources": sorted(item["stableSolutionID"] for item in documents if item.get("sourceID") and item["sourceID"] not in source_ids),
        "additionalSources": sorted(item["stableSolutionID"] for item in documents if any(value not in source_ids for value in item.get("additionalSourceIDs", []))),
        "linkQuestions": sorted(item["stableLinkID"] for item in links if item["questionID"] not in question_ids),
        "linkSolutions": sorted(item["stableLinkID"] for item in links if item["solutionID"] not in solution_ids),
        "assignmentQuestions": sorted(item["externalAssignmentID"] for item in programme["assignments"] if item["questionID"] not in question_ids),
    }

    expected_dates = {
        4: "2026-08-31", 5: "2026-09-01", 6: "2026-09-02", 7: "2026-09-04",
        8: "2026-09-07", 9: "2026-09-08", 10: "2026-09-09", 11: "2026-09-11",
        12: "2026-09-14", 13: "2026-09-15", 14: "2026-09-16", 15: "2026-09-18",
        16: "2026-09-19", 17: "2026-09-21", 18: "2026-09-22", 19: "2026-09-23",
        20: "2026-09-25", 21: "2026-09-28", 22: "2026-09-29", 23: "2026-09-30",
        24: "2026-10-02", 25: "2026-10-05", 26: "2026-10-06", 27: "2026-10-07",
        28: "2026-10-09", 29: "2026-10-12", 30: "2026-10-14",
    }
    validations = {
        "integrity": integrity == "ok",
        "databaseCounts": counts == {"questions": 2600, "sources": 136, "solutions": 120, "links": 2364, "attempts": 48, "sessions": 3, "results": 0, "storedAssignments": 894, "activeAssignments": 452, "completedAssignments": 47, "programmeDays": 30, "needsReview": 5, "redo": 2},
        "databaseNoDuplicates": not any(duplicates.values()),
        "databaseNoDanglingRelationships": not any(dangling.values()),
        "manifestCounts": (len(questions), len(sources), len(documents), len(links)) == (2600, 136, 120, 2364),
        "manifestRelationships": not any(manifest_relationship_errors.values()),
        "resourcesPresentAndChecksummed": not missing_resources and not checksum_mismatches,
        "resourceCounts": (len(pdf_files), len(video_files)) == (234, 8),
        "streamCounts": primary_counts == Counter({"tmua": 1364, "nil": 763, "smc": 300, "bmo": 93, "csat": 80}),
        "intendedUseCounts": intended_counts == Counter({"tmua": 1920, "csat": 348, "smc": 300, "cambridgeCSInterview": 268, "bmo": 93}),
        "programmeDates": all(dates.get(day) == expected for day, expected in expected_dates.items()),
        "programmeDayUniqueness": sorted(dates) == list(range(1, 31)),
        "tuesdayRestrictions": all(next(item for item in programme["days"] if item["dayNumber"] == day).get("earliestStartMinute") == 840 for day in (5, 9, 13, 18, 22, 26)),
        "noSameDayQuestionDuplicates": not same_day_duplicates,
        "tmua2022PermanentProtection": len(tmua_2022) == 40 and all(item["protection"] == "protectedFromAutomaticSelection" and not item["scheduleEligible"] for item in tmua_2022) and not scheduled_ids.intersection(item["externalQuestionID"] for item in tmua_2022),
        "subjects": subjects == {"TMUA": 1, "Mathematics": 0, "Further Mathematics": 0},
        "pageAndMediaRanges": not invalid_page_links,
        "d1D3CountsAndCompletion": Counter(item["ZDAYNUMBER"] for item in d1_d3) == Counter({1: 16, 2: 16, 3: 15}) and all(item["completed"] == 1 and item["ZISIMPORTEDACTIVE"] == 1 for item in d1_d3),
        "d1D3Fingerprint": d1_d3_fingerprint == EXPECTED_D1_D3_FINGERPRINT,
        "activeD4Count": len(active_d4_ids) == 405,
        "historicalUserData": historical_comparison is None or all(item["unchanged"] for item in historical_comparison.values()),
    }

    return {
        "formatIdentifier": "revisr.chunk5.release-candidate-audit.v1",
        "verdict": "PASS" if all(validations.values()) else "FAIL",
        "store": str(store_path.resolve()),
        "integrity": integrity,
        "logicalDigest": digest,
        "counts": counts,
        "duplicates": duplicates,
        "danglingRelationships": dangling,
        "manifestRelationshipErrors": manifest_relationship_errors,
        "invalidPageOrMediaLinks": sorted(set(invalid_page_links)),
        "missingResources": missing_resources,
        "checksumMismatches": checksum_mismatches,
        "manifestHashes": {path.name: sha256_file(path) for path in (admissions_path, solutions_path, programme_path)},
        "productionSourceManifest": source_manifest(),
        "resourceBundle": bundle_inventory,
        "canonicalStreamCounts": dict(sorted(primary_counts.items())),
        "intendedUseCounts": dict(sorted(intended_counts.items())),
        "programmeDates": dates,
        "flexDates": programme["flexDates"],
        "sameDayQuestionDuplicates": same_day_duplicates,
        "crossDayQuestionRepeats": cross_day_repeats,
        "d1D3ExpectedFingerprint": EXPECTED_D1_D3_FINGERPRINT,
        "d1D3Fingerprint": d1_d3_fingerprint,
        "d1D3Records": d1_d3,
        "activeD4D30AssignmentIDs": active_d4_ids,
        "subjects": subjects,
        "tmua2022ProtectedCount": len(tmua_2022),
        "validations": validations,
        "historicalComparison": historical_comparison,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("store", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--baseline-store", type=Path)
    arguments = parser.parse_args()
    audit = run_audit(arguments.store, arguments.baseline_store)
    payload = json.dumps(audit, indent=2, sort_keys=True) + "\n"
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(payload, encoding="utf-8")
    print(payload, end="")
    if audit["verdict"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
