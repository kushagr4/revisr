#!/usr/bin/env python3
"""Check a Google Drive resource inventory and find duplicates, without importing anything.

The inventory itself is private (revisr-content-private/drive/tmua-drive-inventory.json): one
record per Drive file with its title, folder, type, size and the classification fields below.
This script only reads it. It never downloads, copies or modifies Drive files, and its summary
prints counts, not titles, so its output is safe to quote in public documentation.

Usage:
  drive_inventory.py validate  INVENTORY
  drive_inventory.py duplicates INVENTORY [--repo DIR]   Drive<->Drive and Drive<->local duplicate groups
  drive_inventory.py summary   INVENTORY [--repo DIR]    aggregate counts (JSON)
"""
import json
import os
import re
import sys
from collections import Counter

REQUIRED = ["driveId", "title", "folderPath", "mimeType", "provider", "providerEvidence", "examFamily", "kind"]
KINDS = {"question_paper", "answer_key", "mark_scheme", "worked_solutions", "combined_paper_and_solutions",
         "worksheet", "notes", "video", "image", "other"}
EVIDENCE = {"title", "folder", "cover page read", "unverified"}
LOCAL_DIRS = ["AdmissionsPapers", "AdmissionsSolutions", "AdmissionsVideos"]


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def validate(records):
    problems = []
    seen = set()
    for index, record in enumerate(records):
        label = record.get("driveId") or "record %d" % index
        for field in REQUIRED:
            if record.get(field) in (None, ""):
                problems.append("%s: missing %s" % (label, field))
        if record.get("kind") not in KINDS:
            problems.append("%s: unknown kind %r" % (label, record.get("kind")))
        if record.get("providerEvidence") not in EVIDENCE:
            problems.append("%s: unknown providerEvidence %r" % (label, record.get("providerEvidence")))
        if record.get("driveId") in seen:
            problems.append("%s: duplicate driveId" % label)
        seen.add(record.get("driveId"))
        if record.get("mimeType") == "application/vnd.google-apps.folder":
            problems.append("%s: folders are not inventory records" % label)
    return problems


def normalise(title):
    """A comparable form of a file title: no extension, copy markers, case or punctuation."""
    stem = re.sub(r"\.(pdf|docx?|xlsx?|xlsm|mp4|png|jpe?g)$", "", title.strip(), flags=re.I)
    stem = re.sub(r"^copy of\s+", "", stem, flags=re.I)
    stem = re.sub(r"\s*\(\d+\)$", "", stem)
    return re.sub(r"[^a-z0-9]+", "", stem.lower())


def local_files(repo):
    """(normalised name, size) -> relative path for the bundled library, plus manifest filenames."""
    files = {}
    if not repo:
        return files, {}
    resources = os.path.join(repo, "revisr", "Resources")
    for directory in LOCAL_DIRS:
        root = os.path.join(resources, directory)
        if not os.path.isdir(root):
            continue
        for name in os.listdir(root):
            path = os.path.join(root, name)
            if os.path.isfile(path):
                files.setdefault(os.path.getsize(path), []).append(os.path.join(directory, name))
    names = {}
    for manifest, fields in (("AdmissionsManifest.json", ("expectedFilename",)),
                             ("AdmissionsSolutionsManifest.json", ("originalFilename",))):
        path = os.path.join(resources, manifest)
        if not os.path.isfile(path):
            continue
        data = load(path)
        for entry in data.get("sources", []) + data.get("documents", []):
            for field in fields:
                if entry.get(field):
                    names[normalise(entry[field])] = entry.get("stableSourceID") or entry.get("stableSolutionID")
    return files, names


def duplicates(records, repo=None):
    """Groups of Drive files that are the same document, and Drive files already held locally.
    Same document: equal byte size and equal normalised title, or equal size with a local file."""
    groups = {}
    for record in records:
        key = (normalise(record["title"]), record.get("fileSizeBytes"))
        groups.setdefault(key, []).append(record["driveId"])
    drive_groups = [ids for ids in groups.values() if len(ids) > 1]
    sizes, names = local_files(repo)
    local = {}
    for record in records:
        name = normalise(record["title"])
        size = record.get("fileSizeBytes")
        if name in names:
            local[record["driveId"]] = {"match": names[name], "evidence": "manifest filename"}
        elif size and size in sizes:
            local[record["driveId"]] = {"match": sizes[size][0], "evidence": "identical byte size"}
    return {"driveDuplicateGroups": drive_groups, "localMatches": local}


def summary(records, repo=None):
    found = duplicates(records, repo)
    duplicate_ids = {driveId for group in found["driveDuplicateGroups"] for driveId in group[1:]}
    distinct = [r for r in records if r["driveId"] not in duplicate_ids]
    new = [r for r in distinct if r["driveId"] not in found["localMatches"]]
    return {
        "files": len(records),
        "distinctDocuments": len(distinct),
        "driveInternalCopies": len(duplicate_ids),
        "alreadyLocal": len([r for r in distinct if r["driveId"] in found["localMatches"]]),
        "notLocal": len(new),
        "byProvider": dict(Counter(r["provider"] for r in records).most_common()),
        "byKind": dict(Counter(r["kind"] for r in records).most_common()),
        "notLocalByProvider": dict(Counter(r["provider"] for r in new).most_common()),
        "unverifiedProvider": sum(1 for r in records if r["providerEvidence"] == "unverified"),
    }


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        raise SystemExit(2)
    command, path = sys.argv[1], sys.argv[2]
    repo = sys.argv[sys.argv.index("--repo") + 1] if "--repo" in sys.argv else None
    records = load(path)
    if command == "validate":
        problems = validate(records)
        for problem in problems:
            print("error: " + problem)
        print("%d records, %d problems" % (len(records), len(problems)))
        raise SystemExit(1 if problems else 0)
    if command == "duplicates":
        print(json.dumps(duplicates(records, repo), indent=1))
    elif command == "summary":
        print(json.dumps(summary(records, repo), indent=1))
    else:
        sys.stderr.write(__doc__)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
