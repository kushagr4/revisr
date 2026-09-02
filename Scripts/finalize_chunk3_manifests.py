#!/usr/bin/env python3
"""Finalize Chunk 3 metadata after programme-compatibility preflight."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from atomic_generation import staged_output_set


def canonical_hash(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    ).hexdigest()


def without_revision(record: dict) -> dict:
    return {key: value for key, value in record.items() if key != "importRevision"}


def finalize(root: Path) -> dict[str, object]:
    manifest_path = root / "AdmissionsManifest.json"
    solutions_path = root / "AdmissionsSolutionsManifest.json"
    manifest = json.loads(manifest_path.read_text())
    solutions = json.loads(solutions_path.read_text())

    assigned_ids = {item["questionID"] for item in manifest["programme"]["assignments"]}
    changed_ids = []
    for question in manifest["questions"]:
        if question["externalQuestionID"] not in assigned_ids:
            continue
        uses = set(question.get("intendedUses") or [])
        primary = question.get("primaryPreparationStream")
        effective = uses | ({primary} if primary else set())
        if "tmua" not in effective:
            uses.add("tmua")
            question["intendedUses"] = sorted(uses)
            changed_ids.append(question["externalQuestionID"])

    admissions_revision = canonical_hash({
        "formatVersion": manifest["formatVersion"],
        "profiles": manifest["profiles"],
        "sources": manifest["sources"],
        "questions": [without_revision(item) for item in manifest["questions"]],
        "topics": manifest["topics"],
        "programme": manifest["programme"],
    })
    manifest["importRevision"] = admissions_revision
    for question in manifest["questions"]:
        question["importRevision"] = admissions_revision

    solutions_revision = canonical_hash({
        "formatVersion": solutions["formatVersion"],
        "admissionsRevision": admissions_revision,
        "documents": [without_revision(item) for item in solutions["documents"]],
        "links": [without_revision(item) for item in solutions["links"]],
    })
    solutions["importRevision"] = solutions_revision
    for item in solutions["documents"] + solutions["links"]:
        item["importRevision"] = solutions_revision

    targets = [manifest_path, solutions_path]
    audit_path = root / "Chunk3ImportAudit.json"
    audit = None
    if audit_path.exists():
        audit = json.loads(audit_path.read_text())
        audit["intendedUseCounts"]["tmua"] = sum(
            "tmua" in (question.get("intendedUses") or []) for question in manifest["questions"]
        )
        audit["manifestImportRevision"] = admissions_revision
        audit["solutionsImportRevision"] = solutions_revision
        audit["historicalProgrammeTMUAUsesAdded"] = len(changed_ids)
        targets.append(audit_path)

    with staged_output_set(targets) as staged:
        staged[0].parent.mkdir(parents=True, exist_ok=True)
        staged[0].write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        staged[1].write_text(json.dumps(solutions, indent=2, ensure_ascii=False) + "\n")
        if audit is not None:
            staged[2].write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n")

    return {
        "root": str(root),
        "historicalProgrammeTMUAUsesAdded": len(changed_ids),
        "admissionsRevision": admissions_revision,
        "solutionsRevision": solutions_revision,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("roots", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([finalize(root) for root in args.roots], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
