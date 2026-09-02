#!/usr/bin/env python3
"""Read-only physical-device store audit and preservation comparison for Chunk 6."""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
EXPECTED_D1_D3_FINGERPRINT = "326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e"


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def encode(value: Any) -> Any:
    if isinstance(value, bytes):
        return {"hex": value.hex().upper(), "bytes": len(value)}
    return value


def apple_date(value: float | None) -> str | None:
    if value is None:
        return None
    return (APPLE_EPOCH + timedelta(seconds=value)).isoformat()


def connect(path: Path) -> sqlite3.Connection:
    database = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    database.row_factory = sqlite3.Row
    database.execute("PRAGMA query_only=ON")
    return database


def rows(database: sqlite3.Connection, query: str) -> list[dict[str, Any]]:
    return [{key: encode(value) for key, value in dict(row).items()} for row in database.execute(query)]


def table_digest(database: sqlite3.Connection) -> dict[str, Any]:
    names = [row[0] for row in database.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' ORDER BY name"
    ) if row[0] not in {"Z_METADATA", "Z_MODELCACHE", "Z_PRIMARYKEY"}]
    table_hashes: dict[str, str] = {}
    counts: dict[str, int] = {}
    for name in names:
        columns = [row[1] for row in database.execute(f'PRAGMA table_info("{name}")') if row[1] != "Z_OPT"]
        selected_columns = ",".join('"' + column + '"' for column in columns)
        records = rows(database, f'SELECT {selected_columns} FROM "{name}" ORDER BY Z_PK')
        table_hashes[name] = hashlib.sha256(canonical(records)).hexdigest()
        counts[name] = len(records)
    return {
        "overallSHA256": hashlib.sha256(canonical(table_hashes)).hexdigest(),
        "tableSHA256": table_hashes,
        "rowCounts": counts,
    }


def file_manifest(root: Path | None) -> list[dict[str, Any]]:
    if root is None:
        return []
    return [
        {
            "path": str(path.relative_to(root)),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        for path in sorted(root.rglob("*")) if path.is_file()
    ]


def history(database: sqlite3.Connection) -> dict[str, Any]:
    attempts = rows(database, """
        SELECT hex(a.ZID) id,a.ZATTEMPTEDAT attemptedAt,a.ZOUTCOMERAWVALUE outcome,
               a.ZERRORTYPERAWVALUE errorType,a.ZNOTES notes,a.ZTIMETAKENSECONDS timeTakenSeconds,
               a.ZORIGINRAWVALUE origin,q.ZEXTERNALQUESTIONID questionID,
               p.ZEXTERNALASSIGNMENTID assignmentID,d.ZDAYNUMBER dayNumber
        FROM ZQUESTIONATTEMPT a
        LEFT JOIN ZADMISSIONSQUESTION q ON q.Z_PK=a.ZQUESTION
        LEFT JOIN ZPROGRAMMEASSIGNMENT p ON p.Z_PK=a.ZPROGRAMMEASSIGNMENT
        LEFT JOIN ZPROGRAMMEDAY d ON d.Z_PK=p.ZPROGRAMMEDAY
        ORDER BY id
    """)
    for attempt in attempts:
        attempt["attemptedAtISO"] = apple_date(attempt["attemptedAt"])
    return {
        "attempts": attempts,
        "sessions": rows(database, """
            SELECT hex(ZID) id,ZDATE date,ZDURATION duration,ZACTIVITYRAWVALUE activity,
                   ZACTUALSTARTDATE actualStart,ZENDDATE endDate,ZNOTES notes,
                   ZSUBJECTNAMESNAPSHOT subjectName,ZMODULENAMESNAPSHOT moduleName,
                   ZTOPICNAMESNAPSHOT topicName FROM ZSTUDYSESSION ORDER BY id
        """),
        "results": rows(database, """
            SELECT hex(ZID) id,ZDATE date,ZMAXIMUMSCORE maximumScore,ZRAWSCORE rawScore,
                   ZSCALEDSCORE scaledScore,ZMODULENAMESNAPSHOT moduleName,ZNOTES notes,
                   ZPAPERORMODULELABEL paperOrModule,ZSUBJECTNAMESNAPSHOT subjectName
            FROM ZSTUDYRESULT ORDER BY id
        """),
        "questionReview": rows(database, """
            SELECT ZEXTERNALQUESTIONID questionID,ZREVIEWSTATERAWVALUE reviewState,ZUSERNOTES notes
            FROM ZADMISSIONSQUESTION
            WHERE ZREVIEWSTATERAWVALUE<>'none' OR ZUSERNOTES IS NOT NULL
            ORDER BY questionID
        """),
        "topicState": rows(database, """
            SELECT ZSTABLETOPICID topicID,ZMANUALSTATUSRAWVALUE manualStatus,
                   ZNEEDSREVIEW needsReview,ZNOTES notes
            FROM ZADMISSIONSTOPICSTATE ORDER BY topicID
        """),
    }


def user_table_hashes(database: sqlite3.Connection) -> dict[str, dict[str, Any]]:
    names = [
        "ZAPPSETTINGS", "ZPLANNEDSTUDYBLOCK", "ZQUESTIONATTEMPT",
        "ZQUESTIONATTEMPTTIMERSTATE", "ZSTUDYRESULT", "ZSTUDYSESSION",
        "ZSTUDYTIMERSTATE", "ZSUBJECT", "ZTOPIC", "ZWEEKLYFOCUS",
    ]
    output: dict[str, dict[str, Any]] = {}
    for name in names:
        columns = [
            row[1] for row in database.execute(f'PRAGMA table_info("{name}")')
            if row[1] not in {"Z_ENT", "Z_OPT"}
        ]
        selected_columns = ",".join('"' + column + '"' for column in columns)
        values = rows(database, f'SELECT {selected_columns} FROM "{name}" ORDER BY Z_PK')
        output[name] = {"count": len(values), "sha256": hashlib.sha256(canonical(values)).hexdigest()}
    return output


def audit(store: Path, snapshot_root: Path | None) -> dict[str, Any]:
    database = connect(store)
    try:
        integrity = database.execute("PRAGMA integrity_check").fetchone()[0]
        logical = table_digest(database)
        counts = {
            "questions": database.execute("SELECT COUNT(*) FROM ZADMISSIONSQUESTION").fetchone()[0],
            "sources": database.execute("SELECT COUNT(*) FROM ZSOURCEDOCUMENT").fetchone()[0],
            "solutions": database.execute("SELECT COUNT(*) FROM ZSOLUTIONDOCUMENT").fetchone()[0],
            "solutionLinks": database.execute("SELECT COUNT(*) FROM ZQUESTIONSOLUTIONLINK").fetchone()[0],
            "videos": database.execute("SELECT COUNT(*) FROM ZSOLUTIONDOCUMENT WHERE ZRESOURCEEXTENSION='mp4'").fetchone()[0],
            "attempts": database.execute("SELECT COUNT(*) FROM ZQUESTIONATTEMPT").fetchone()[0],
            "sessions": database.execute("SELECT COUNT(*) FROM ZSTUDYSESSION").fetchone()[0],
            "results": database.execute("SELECT COUNT(*) FROM ZSTUDYRESULT").fetchone()[0],
            "storedAssignments": database.execute("SELECT COUNT(*) FROM ZPROGRAMMEASSIGNMENT").fetchone()[0],
            "activeAssignments": database.execute("SELECT COUNT(*) FROM ZPROGRAMMEASSIGNMENT WHERE ZISIMPORTEDACTIVE=1").fetchone()[0],
            "completedAssignments": database.execute("SELECT COUNT(DISTINCT ZPROGRAMMEASSIGNMENT) FROM ZQUESTIONATTEMPT WHERE ZOUTCOMERAWVALUE<>'skipped'").fetchone()[0],
            "needsReview": database.execute("SELECT COUNT(*) FROM ZADMISSIONSQUESTION WHERE ZREVIEWSTATERAWVALUE='needsReview'").fetchone()[0],
            "redo": database.execute("SELECT COUNT(*) FROM ZADMISSIONSQUESTION WHERE ZREVIEWSTATERAWVALUE='redo'").fetchone()[0],
        }
        historical = history(database)
        d1_d3 = rows(database, """
            SELECT d.ZDAYNUMBER dayNumber,a.ZEXTERNALASSIGNMENTID assignmentID,
                   a.ZISIMPORTEDACTIVE active,
                   CASE WHEN EXISTS(
                     SELECT 1 FROM ZQUESTIONATTEMPT t
                     WHERE t.ZPROGRAMMEASSIGNMENT=a.Z_PK AND t.ZOUTCOMERAWVALUE<>'skipped'
                   ) THEN 1 ELSE 0 END completed
            FROM ZPROGRAMMEASSIGNMENT a JOIN ZPROGRAMMEDAY d ON d.Z_PK=a.ZPROGRAMMEDAY
            WHERE d.ZDAYNUMBER<=3 ORDER BY dayNumber,a.ZDISPLAYORDER,assignmentID
        """)
        d4_activity = rows(database, """
            SELECT DISTINCT d.ZDAYNUMBER dayNumber,a.ZEXTERNALASSIGNMENTID assignmentID,
                   a.ZISIMPORTEDACTIVE active,hex(t.ZID) attemptID,t.ZOUTCOMERAWVALUE outcome
            FROM ZPROGRAMMEASSIGNMENT a JOIN ZPROGRAMMEDAY d ON d.Z_PK=a.ZPROGRAMMEDAY
            JOIN ZQUESTIONATTEMPT t ON t.ZPROGRAMMEASSIGNMENT=a.Z_PK
            WHERE d.ZDAYNUMBER>=4 ORDER BY dayNumber,assignmentID,attemptID
        """)
        programme = rows(database, """
            SELECT ZEXTERNALPROGRAMMEID programmeID,ZSTARTDATE startDate,
                   ZADMISSIONSTESTRAWVALUE admissionsTest,ZIMPORTREVISION importRevision,
                   ZNAME name,ZISIMPORTEDACTIVE active FROM ZADMISSIONSPROGRAMME ORDER BY programmeID
        """)
        for record in programme:
            record["startDateISO"] = apple_date(record["startDate"])
        settings = rows(database, """
            SELECT ZAPPLIEDSEEDVERSION appliedSeedVersion,ZWEEKLYTARGETMINUTES weeklyTargetMinutes,
                   ZTMUAEXAMDATE examDate,ZTMUAPROGRAMMESTARTDATE programmeStartDate,
                   ZACTIVEADMISSIONSTESTRAWVALUE activeAdmissionsTest,
                   ZAVAILABILITYDATA availabilityData FROM ZAPPSETTINGS
        """)
        for record in settings:
            record["examDateISO"] = apple_date(record["examDate"])
            record["programmeStartDateISO"] = apple_date(record["programmeStartDate"])
            availability = record.get("availabilityData")
            if isinstance(availability, dict) and "hex" in availability:
                raw = bytes.fromhex(availability["hex"])
                try:
                    record["availabilityJSON"] = json.loads(raw)
                except (UnicodeDecodeError, json.JSONDecodeError):
                    record["availabilitySHA256"] = hashlib.sha256(raw).hexdigest()
        subjects = rows(database, "SELECT ZNAME name,ZISACTIVEFORSTUDY active FROM ZSUBJECT ORDER BY name")
        tmua_2022 = rows(database, """
            SELECT ZEXTERNALQUESTIONID questionID,ZPROTECTIONRAWVALUE protection,
                   ZSCHEDULEELIGIBLE scheduleEligible
            FROM ZADMISSIONSQUESTION WHERE ZFAMILY='TMUA Actual' AND ZYEAR=2022
            ORDER BY questionID
        """)
        benchmark = rows(database, """
            SELECT q.ZYEAR year,q.ZPAPER paper,COUNT(*) questionCount,
                   SUM(CASE WHEN q.ZPROTECTIONRAWVALUE='protectedFromAutomaticSelection' THEN 1 ELSE 0 END) explicitProtected,
                   SUM(CASE WHEN q.ZSCHEDULEELIGIBLE=0 THEN 1 ELSE 0 END) scheduleIneligible
            FROM ZADMISSIONSQUESTION q
            WHERE q.ZFAMILY='TMUA Actual' AND q.ZYEAR BETWEEN 2017 AND 2022
            GROUP BY q.ZYEAR,q.ZPAPER ORDER BY q.ZYEAR,q.ZPAPER
        """)
        duplicates = {
            "questionIDs": database.execute("SELECT COUNT(*) FROM (SELECT ZEXTERNALQUESTIONID FROM ZADMISSIONSQUESTION GROUP BY ZEXTERNALQUESTIONID HAVING COUNT(*)>1)").fetchone()[0],
            "sourceIDs": database.execute("SELECT COUNT(*) FROM (SELECT ZSTABLESOURCEID FROM ZSOURCEDOCUMENT GROUP BY ZSTABLESOURCEID HAVING COUNT(*)>1)").fetchone()[0],
            "solutionIDs": database.execute("SELECT COUNT(*) FROM (SELECT ZSTABLESOLUTIONID FROM ZSOLUTIONDOCUMENT GROUP BY ZSTABLESOLUTIONID HAVING COUNT(*)>1)").fetchone()[0],
            "activeAssignmentIDs": database.execute("SELECT COUNT(*) FROM (SELECT ZEXTERNALASSIGNMENTID FROM ZPROGRAMMEASSIGNMENT WHERE ZISIMPORTEDACTIVE=1 GROUP BY ZEXTERNALASSIGNMENTID HAVING COUNT(*)>1)").fetchone()[0],
        }
        dangling = {
            "attemptQuestion": database.execute("SELECT COUNT(*) FROM ZQUESTIONATTEMPT a LEFT JOIN ZADMISSIONSQUESTION q ON q.Z_PK=a.ZQUESTION WHERE q.Z_PK IS NULL").fetchone()[0],
            "attemptAssignment": database.execute("SELECT COUNT(*) FROM ZQUESTIONATTEMPT a LEFT JOIN ZPROGRAMMEASSIGNMENT p ON p.Z_PK=a.ZPROGRAMMEASSIGNMENT WHERE a.ZPROGRAMMEASSIGNMENT IS NOT NULL AND p.Z_PK IS NULL").fetchone()[0],
            "solutionLinkQuestion": database.execute("SELECT COUNT(*) FROM ZQUESTIONSOLUTIONLINK l LEFT JOIN ZADMISSIONSQUESTION q ON q.Z_PK=l.ZQUESTION WHERE q.Z_PK IS NULL").fetchone()[0],
            "solutionLinkSolution": database.execute("SELECT COUNT(*) FROM ZQUESTIONSOLUTIONLINK l LEFT JOIN ZSOLUTIONDOCUMENT s ON s.Z_PK=l.ZSOLUTIONDOCUMENT WHERE s.Z_PK IS NULL").fetchone()[0],
        }
        user_hashes = user_table_hashes(database)
    finally:
        database.close()

    manifest = file_manifest(snapshot_root)
    return {
        "formatIdentifier": "revisr.chunk6.device-audit.v1",
        "store": str(store.resolve()),
        "snapshotRoot": str(snapshot_root.resolve()) if snapshot_root else None,
        "snapshotFiles": manifest,
        "snapshotManifestSHA256": hashlib.sha256(canonical(manifest)).hexdigest(),
        "integrity": integrity,
        "logicalDigest": logical,
        "counts": counts,
        "attemptIDs": [item["id"] for item in historical["attempts"]],
        "latestAttemptTimestamp": max((item["attemptedAtISO"] for item in historical["attempts"]), default=None),
        "history": historical,
        "userTableHashes": user_hashes,
        "programme": programme,
        "d1D3ExpectedFingerprint": EXPECTED_D1_D3_FINGERPRINT,
        "d1D3Records": d1_d3,
        "d4PlusActivity": d4_activity,
        "settings": settings,
        "subjects": subjects,
        "tmua2022ProtectedCount": sum(item["protection"] == "protectedFromAutomaticSelection" and item["scheduleEligible"] == 0 for item in tmua_2022),
        "tmua2022Records": tmua_2022,
        "officialBenchmarkRecords": benchmark,
        "duplicates": duplicates,
        "danglingRelationships": dangling,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("store", type=Path)
    parser.add_argument("--snapshot-root", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--baseline-snapshot-root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    current = audit(arguments.store, arguments.snapshot_root)
    payload: dict[str, Any] = {"audit": current}
    if arguments.baseline:
        baseline = audit(arguments.baseline, arguments.baseline_snapshot_root)
        payload["baseline"] = baseline
        before_review = {item["questionID"]: item for item in baseline["history"]["questionReview"]}
        after_review = {item["questionID"]: item for item in current["history"]["questionReview"]}
        payload["preservation"] = {
            "attempts": baseline["history"]["attempts"] == current["history"]["attempts"],
            "sessions": baseline["history"]["sessions"] == current["history"]["sessions"],
            "results": baseline["history"]["results"] == current["history"]["results"],
            "questionReview": all(after_review.get(key) == value for key, value in before_review.items()),
            "topicState": baseline["history"]["topicState"] == current["history"]["topicState"],
            "d1D3": baseline["d1D3Records"] == current["d1D3Records"],
            "d4PlusActivity": baseline["d4PlusActivity"] == current["d4PlusActivity"],
            "settings": baseline["settings"] == current["settings"],
            "subjects": baseline["subjects"] == current["subjects"],
        }
        payload["allUserHistoryPreserved"] = all(payload["preservation"].values())
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    if current["integrity"] != "ok":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
