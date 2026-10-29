import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("drive_inventory", ROOT / "Scripts" / "drive_inventory.py")
drive = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(drive)


def record(drive_id, title, size, provider="UAT-UK", kind="question_paper", evidence="title"):
    return {"driveId": drive_id, "title": title, "folderPath": "TMUA/for revisr", "mimeType": "application/pdf",
            "provider": provider, "providerEvidence": evidence, "examFamily": "TMUA", "kind": kind,
            "fileSizeBytes": size}


class InventoryValidationTests(unittest.TestCase):
    def test_valid_inventory_has_no_problems(self):
        self.assertEqual(drive.validate([record("a", "Paper 1.pdf", 10), record("b", "Paper 2.pdf", 20)]), [])

    def test_missing_fields_unknown_values_duplicates_and_folders_are_reported(self):
        broken = record("a", "x.pdf", 1)
        del broken["provider"]
        odd = record("b", "y.pdf", 1, kind="poster", evidence="guess")
        folder = dict(record("c", "Folder", 0), mimeType="application/vnd.google-apps.folder")
        problems = drive.validate([broken, odd, record("b", "z.pdf", 2), folder])
        self.assertTrue(any("missing provider" in p for p in problems))
        self.assertTrue(any("unknown kind" in p for p in problems))
        self.assertTrue(any("unknown providerEvidence" in p for p in problems))
        self.assertTrue(any("duplicate driveId" in p for p in problems))
        self.assertTrue(any("folders" in p for p in problems))


class DuplicateDetectionTests(unittest.TestCase):
    def test_copies_inside_drive_group_by_title_and_size(self):
        records = [record("a", "TMUA 2019 Paper 1.pdf", 100), record("b", "Copy of TMUA 2019 Paper 1 (1).pdf", 100),
                   record("c", "TMUA 2019 Paper 1.pdf", 999), record("d", "TMUA 2019 Paper 2.pdf", 100)]
        groups = drive.duplicates(records)["driveDuplicateGroups"]
        self.assertEqual(groups, [["a", "b"]], "same title but a different size is a different file")

    def test_local_matches_by_manifest_filename_or_identical_size(self):
        with tempfile.TemporaryDirectory() as repo:
            resources = Path(repo) / "revisr" / "Resources"
            (resources / "AdmissionsPapers").mkdir(parents=True)
            (resources / "AdmissionsPapers" / "SRC-1.pdf").write_bytes(b"x" * 321)
            (resources / "AdmissionsManifest.json").write_text(json.dumps(
                {"sources": [{"stableSourceID": "SRC-2", "expectedFilename": "MAT 2015.pdf"}]}))
            records = [record("a", "renamed.pdf", 321), record("b", "MAT 2015.pdf", 5), record("c", "new.pdf", 7)]
            local = drive.duplicates(records, repo)["localMatches"]
            self.assertEqual(local["a"]["evidence"], "identical byte size")
            self.assertEqual(local["b"]["match"], "SRC-2")
            self.assertNotIn("c", local)
            totals = drive.summary(records, repo)
            self.assertEqual((totals["files"], totals["alreadyLocal"], totals["notLocal"]), (3, 2, 1))

    def test_summary_counts_without_titles(self):
        records = [record("a", "Secret title.pdf", 1, provider="JZMaths", evidence="unverified")]
        text = json.dumps(drive.summary(records))
        self.assertNotIn("Secret title", text)
        self.assertIn("JZMaths", text)


def snapshot(*files, taken="2026-10-29T00:00:00Z"):
    return {"schema": 1, "takenAt": taken, "folders": [], "files": list(files)}


def listed(record, **changes):
    entry = {field: record.get(field) for field in ("driveId", "title", "folderPath", "mimeType", "fileSizeBytes")}
    entry.update(createdTime="2026-08-01T00:00:00Z", modifiedTime="2026-08-01T00:00:00Z")
    entry.update(changes)
    return entry


class IncrementalSyncTests(unittest.TestCase):
    def setUp(self):
        self.paper = dict(record("p", "TMUA 2019 Paper 1.pdf", 100), createdTime="2026-08-01T00:00:00Z",
                          modifiedTime="2026-08-01T00:00:00Z", localDuplicate={"localID": "SRC-1"})
        self.solutions = dict(record("s", "TMUA 2019 Solutions.pdf", 200, kind="worked_solutions"),
                              createdTime="2026-08-01T00:00:00Z", modifiedTime="2026-08-01T00:00:00Z",
                              localDuplicate={"localID": "SOL-1"})
        self.notes = dict(record("n", "Notes.pdf", 5, kind="notes"), createdTime="2026-08-01T00:00:00Z",
                          modifiedTime="2026-08-01T00:00:00Z")

    def test_unchanged_files_keep_their_classification(self):
        records, report = drive.sync([self.paper], snapshot(listed(self.paper)))
        self.assertEqual(report["counts"]["unchanged"], 1)
        self.assertEqual(records[0]["provider"], "UAT-UK")
        self.assertEqual(records[0]["syncState"], "unchanged")
        self.assertEqual(report["librarySourcesToReindex"], [])

    def test_changed_moved_new_and_missing_files_are_told_apart(self):
        changed = listed(self.paper, modifiedTime="2026-10-28T09:00:00Z", fileSizeBytes=150)
        moved = listed(self.notes, folderPath="TMUA/archive")
        new = {"driveId": "x", "title": "MAT 2024.pdf", "folderPath": "TMUA/MAT", "mimeType": "application/pdf",
               "fileSizeBytes": 9, "createdTime": "2026-10-28T00:00:00Z", "modifiedTime": "2026-10-28T00:00:00Z"}
        records, report = drive.sync([self.paper, self.solutions, self.notes], snapshot(changed, moved, new))
        self.assertEqual(report["counts"], {"unchanged": 0, "changed": 1, "moved": 1, "new": 1, "missing": 1})
        by_id = {r["driveId"]: r for r in records}
        self.assertTrue(by_id["p"]["needsReindex"])
        self.assertEqual(by_id["p"]["fileSizeBytes"], 150)
        self.assertEqual(by_id["n"]["folderPath"], "TMUA/archive")
        self.assertNotIn("needsReindex", by_id["n"], "a move alone is not a content change")
        self.assertEqual(by_id["s"]["syncState"], "missing", "a vanished file is kept, never deleted")
        self.assertEqual(by_id["s"]["missingSince"], "2026-10-29T00:00:00Z")
        self.assertTrue(by_id["x"]["needsClassification"])
        self.assertEqual(report["librarySourcesToReindex"], ["SOL-1", "SRC-1"])
        self.assertEqual(drive.validate(records), [], "the updated inventory stays valid")

    def test_a_file_that_returns_is_no_longer_missing(self):
        gone, _ = drive.sync([self.paper], snapshot(taken="2026-10-30T00:00:00Z"))
        back, report = drive.sync(gone, snapshot(listed(self.paper), taken="2026-11-01T00:00:00Z"))
        self.assertEqual(report["counts"]["unchanged"], 1)
        self.assertNotIn("missingSince", back[0])

    def test_sync_report_has_no_titles(self):
        _, report = drive.sync([self.paper], snapshot(listed(self.paper, modifiedTime="2026-10-28T00:00:00Z")))
        self.assertNotIn("TMUA 2019", json.dumps(report))


if __name__ == "__main__":
    unittest.main()
