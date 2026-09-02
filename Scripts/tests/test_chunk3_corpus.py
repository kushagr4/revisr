import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STAGING_ROOT = ROOT / ".qa" / "chunk3"


def candidate_root() -> Path:
    candidates = sorted(
        (path for path in STAGING_ROOT.glob("staging-v*") if path.is_dir()),
        key=lambda path: int(path.name.removeprefix("staging-v")),
    )
    if not candidates:
        raise unittest.SkipTest("Chunk 3 candidate has not been generated")
    return candidates[-1]


def load_json(path: Path):
    return json.loads(path.read_text())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class Chunk3CorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = candidate_root()
        cls.manifest = load_json(cls.root / "AdmissionsManifest.json")
        cls.solutions = load_json(cls.root / "AdmissionsSolutionsManifest.json")
        cls.inventory = load_json(cls.root / "CorpusInventory.json")
        cls.audit = load_json(cls.root / "Chunk3ImportAudit.json")

    def test_inventory_is_complete_and_every_supplied_file_is_classified(self):
        self.assertEqual(self.inventory["corpusFileCount"], 96)
        self.assertEqual(self.inventory["pdfCount"], 88)
        self.assertEqual(self.inventory["videoCount"], 8)
        self.assertEqual(self.inventory["logicalResourceCount"], 96)
        self.assertEqual(len(self.inventory["records"]), 96)
        self.assertTrue(all(record["logicalType"] for record in self.inventory["records"]))
        self.assertTrue(all(record["logicalResourceIdentity"] for record in self.inventory["records"]))

    def test_identifiers_are_unique_and_all_relationships_resolve(self):
        sources = self.manifest["sources"]
        questions = self.manifest["questions"]
        documents = self.solutions["documents"]
        links = self.solutions["links"]
        source_ids = [item["stableSourceID"] for item in sources]
        question_ids = [item["externalQuestionID"] for item in questions]
        document_ids = [item["stableSolutionID"] for item in documents]
        link_ids = [item["stableLinkID"] for item in links]
        for values in (source_ids, question_ids, document_ids, link_ids):
            self.assertEqual(len(values), len(set(values)))
        source_set, question_set, document_set = set(source_ids), set(question_ids), set(document_ids)
        self.assertTrue(all(item.get("sourceID") in source_set for item in questions if item.get("sourceID")))
        self.assertTrue(all(item.get("sourceID") in source_set for item in documents if item.get("sourceID")))
        self.assertTrue(all(set(item.get("additionalSourceIDs", [])).issubset(source_set) for item in documents))
        self.assertTrue(all(item["solutionID"] in document_set and item["questionID"] in question_set for item in links))

    def test_every_declared_resource_exists_once_and_matches_checksum(self):
        paths = []
        for source in self.manifest["sources"]:
            path = self.root / "AdmissionsPapers" / f'{source["stableSourceID"]}.pdf'
            self.assertTrue(path.is_file(), source["stableSourceID"])
            if source.get("checksum"):
                self.assertEqual(sha256(path), source["checksum"])
            paths.append(path.resolve())
        for document in self.solutions["documents"]:
            container = document["resourceContainer"]
            directory = {
                "sourcePaperBundle": "AdmissionsPapers",
                "solutionBundle": "AdmissionsVideos" if document.get("mediaKind") == "video" else "AdmissionsSolutions",
            }[container]
            path = self.root / directory / f'{document["resourceName"]}.{document["resourceExtension"]}'
            self.assertTrue(path.is_file(), document["stableSolutionID"])
            self.assertEqual(sha256(path), document["sha256"])
        videos = list((self.root / "AdmissionsVideos").glob("*.mp4"))
        self.assertEqual(len(videos), 8)
        self.assertEqual(len({sha256(path) for path in videos}), 8)
        self.assertEqual(len(paths), len(set(paths)))

    def test_page_and_video_mappings_are_valid(self):
        documents = {item["stableSolutionID"]: item for item in self.solutions["documents"]}
        for link in self.solutions["links"]:
            document = documents[link["solutionID"]]
            if document.get("mediaKind") == "video":
                self.assertIsNone(link.get("startPage"), link["stableLinkID"])
                self.assertIsNone(link.get("endPage"), link["stableLinkID"])
                start, end = link.get("startTimeSeconds"), link.get("endTimeSeconds")
                if start is not None:
                    self.assertGreaterEqual(start, 0)
                    self.assertLessEqual(start, document["durationSecondsAudit"])
                if end is not None:
                    self.assertGreaterEqual(end, start or 0)
                    self.assertLessEqual(end, document["durationSecondsAudit"])
            else:
                self.assertIsNone(link.get("startTimeSeconds"), link["stableLinkID"])
                self.assertIsNone(link.get("endTimeSeconds"), link["stableLinkID"])
                if link.get("startPage") is not None:
                    self.assertGreaterEqual(link["startPage"], 1)
                    if document.get("pageCount"):
                        self.assertLessEqual(link["startPage"], document["pageCount"], link["stableLinkID"])
                if link.get("endPage") is not None:
                    self.assertGreaterEqual(link["endPage"], link["startPage"])
                    if document.get("pageCount"):
                        self.assertLessEqual(link["endPage"], document["pageCount"], link["stableLinkID"])

    def test_required_audit_decisions_are_encoded(self):
        questions = self.manifest["questions"]
        ids = {item["externalQuestionID"] for item in questions}
        self.assertEqual(len(questions), 2600)
        self.assertEqual(len(self.manifest["sources"]), 136)
        self.assertEqual(len(self.solutions["documents"]), 120)
        self.assertEqual(len(self.solutions["links"]), 2364)
        self.assertEqual(self.audit["newQuestions"], 1027)
        self.assertEqual(self.audit["existingQuestionsReused"], 40)
        self.assertEqual(self.audit["videoSolutions"], 8)
        self.assertEqual(self.audit["videoQuestionMappings"], 165)
        self.assertTrue({f"YOTTA-P{paper}-Q{number:02d}" for paper in (1, 2) for number in range(1, 21)}.issubset(ids))
        self.assertFalse(any(identifier.startswith("STEP-") and "REPORT" in identifier for identifier in ids))
        mio_q20 = next(item for item in questions if item["externalQuestionID"] == "MIOMATH-2024-P2-Q20")
        self.assertEqual(mio_q20["validityState"], "usable")
        self.assertTrue(mio_q20["scheduleEligible"])
        self.assertIn("three satisfy", mio_q20["validityReason"])
        self.assertFalse(any(item.get("validityState") == "invalid" and item["scheduleEligible"] for item in questions))

        combinatorics_source = next(item for item in self.manifest["sources"] if item.get("semanticDocumentIdentity") == "source:TYLER-COMBINATORICS")
        combinatorics_solution = next(item for item in self.solutions["documents"] if item.get("semanticDocumentIdentity") == "solution:TYLER-COMBINATORICS-ANS")
        self.assertEqual(combinatorics_source["duplicateReviewState"], "verifiedDistinct")
        self.assertEqual(combinatorics_solution["duplicateReviewState"], "verifiedDistinct")

    def test_programme_history_and_protection_are_unchanged(self):
        assignments = self.manifest["programme"]["assignments"]
        legacy = load_json(ROOT / ".qa" / "data-audit" / "snapshot-before" / "AdmissionsManifest.json") if (ROOT / ".qa" / "data-audit" / "snapshot-before" / "AdmissionsManifest.json").exists() else load_json(ROOT / "revisr" / "Resources" / "AdmissionsManifest.json")
        # If the committed manifest is already V2, compare to the immutable programme fields only.
        self.assertEqual(len(assignments), 530)
        self.assertEqual(self.manifest["programme"]["days"], legacy["programme"]["days"])
        self.assertEqual(assignments, legacy["programme"]["assignments"])
        protected = [item for item in self.manifest["questions"] if item["family"] == "TMUA Actual" and item.get("year") == 2022 and item["protection"] != "none"]
        self.assertEqual(len(protected), 40)
        active = {item["displayName"]: item["isActive"] for item in self.manifest["profiles"]}
        self.assertEqual(active["TMUA"], True)


if __name__ == "__main__":
    unittest.main()
