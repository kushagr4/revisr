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


if __name__ == "__main__":
    unittest.main()
