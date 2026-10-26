import copy
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("assemble", ROOT / "Scripts" / "assemble_tmua_content.py")
assemble = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(assemble)

CLEARED = {
    "copyrightHolder": "Revisr", "licence": "revisr-original", "inAppUse": "cleared",
    "redistribution": "cleared", "commercialUse": "cleared", "answerKey": "cleared",
    "solution": "cleared", "attribution": "Original Revisr question",
}

ITEM = {
    "stableId": "test-item-001", "version": 1, "paper": 1, "category": "revisr_original",
    "title": "Synthetic", "stem": "Synthetic stem with no real content.",
    "options": [{"id": letter, "text": letter} for letter in "ABCDE"], "correctOptionId": "A",
    "solution": "Synthetic.", "taxonomy": {"topic": "algebra", "strand": "polynomials", "skill": None},
    "difficulty": 2, "estimatedMinutes": 3, "source": None, "rights": CLEARED,
    "review": {"mathematical": "human_approved", "originality": "human_approved",
               "publication": "approved", "editorialStatus": "approved", "notes": "private note"},
}


class DistributionGateTests(unittest.TestCase):
    def test_debug_defaults_to_internal_and_release_to_public(self):
        self.assertEqual(assemble.resolve_distribution({"CONFIGURATION": "Debug"}), "internal")
        self.assertEqual(assemble.resolve_distribution({"CONFIGURATION": "Release"}), "public")

    def test_internal_content_is_refused_outside_debug(self):
        with self.assertRaises(ValueError):
            assemble.resolve_distribution({"CONFIGURATION": "Release", "REVISR_DISTRIBUTION": "internal"})

    def test_archives_are_always_public(self):
        for configuration in ("Debug", "Release"):
            with self.assertRaises(ValueError):
                assemble.resolve_distribution({"CONFIGURATION": configuration, "ACTION": "install",
                                               "REVISR_DISTRIBUTION": "internal",
                                               "REVISR_ALLOW_INTERNAL_NON_DEBUG": "1"})
        self.assertEqual(assemble.resolve_distribution({"CONFIGURATION": "Release", "ACTION": "install"}), "public")

    def test_explicit_local_override_is_possible_but_not_for_archives(self):
        self.assertEqual(assemble.resolve_distribution({"CONFIGURATION": "Release", "REVISR_DISTRIBUTION": "internal",
                                                        "REVISR_ALLOW_INTERNAL_NON_DEBUG": "1"}), "internal")

    def test_unknown_distribution_is_rejected(self):
        with self.assertRaises(ValueError):
            assemble.resolve_distribution({"CONFIGURATION": "Debug", "REVISR_DISTRIBUTION": "beta"})


class PublicGateTests(unittest.TestCase):
    def test_fully_cleared_item_passes(self):
        self.assertEqual(assemble.public_gate_failures(ITEM), [])

    def test_draft_and_fixture_items_fail(self):
        draft = copy.deepcopy(ITEM)
        draft["review"]["mathematical"] = "ai_derivation_only"
        draft["rights"]["inAppUse"] = "pending_review"
        self.assertGreaterEqual(len(assemble.public_gate_failures(draft)), 2)
        fixture = dict(ITEM, category="development_fixture")
        self.assertIn("development fixture", assemble.public_gate_failures(fixture))

    def test_public_assembly_drops_reviewer_notes_and_drafts(self):
        with tempfile.TemporaryDirectory() as directory:
            bank_dir = Path(directory) / "content" / "bank"
            bank_dir.mkdir(parents=True)
            draft = copy.deepcopy(ITEM)
            draft["stableId"] = "test-item-002"
            draft["review"]["publication"] = "not_approved"
            (bank_dir / "items.json").write_text(json.dumps({"bankFile": "test", "items": [ITEM, draft]}))
            output = Path(directory) / "app" / assemble.BANK_FILENAME
            bank = assemble.assemble(str(bank_dir.parent), str(ROOT), "public", str(output))
            self.assertEqual([item["stableId"] for item in bank["items"]], ["test-item-001"])
            self.assertEqual(bank["excludedItemCount"], 1)
            self.assertIsNone(bank["items"][0]["review"]["notes"])

    def test_release_gate_rejects_restricted_resources(self):
        names = sorted(assemble.restricted_names(str(ROOT)))
        if not names:
            self.skipTest("no restricted legacy resources in this checkout")
        with tempfile.TemporaryDirectory() as app:
            Path(app, names[0]).write_bytes(b"placeholder")
            Path(app, assemble.BANK_FILENAME).write_text(json.dumps({"distribution": "public", "items": []}))
            with self.assertRaises(SystemExit):
                assemble.check_app(app, str(ROOT), "public")
            os.remove(Path(app, names[0]))
            assemble.check_app(app, str(ROOT), "public")


STUDY_COPY = dict(copy.deepcopy(ITEM), stableId="tmua-2019-p1-q11", category="past_paper_study_copy", stem="",
                  options=[{"id": letter, "text": ""} for letter in "ABCDEF"], correctOptionId="C",
                  source={"organisation": "UAT-UK (© UCLES)", "examination": "TMUA", "year": 2019,
                          "paperNumber": 1, "questionNumber": 11, "url": "https://esat-tmua.ac.uk/", "attribution": None},
                  rights=dict(CLEARED, inAppUse="not_permitted", redistribution="not_permitted",
                              commercialUse="not_permitted", answerKey="not_permitted", solution="not_permitted"),
                  review={"mathematical": "none", "originality": "not_applicable", "publication": "not_approved",
                          "editorialStatus": "official-paper-study-copy"},
                  presentation={"document": "SRC-TEST.pdf",
                                "regions": [{"page": 2, "x": 50, "y": 300, "width": 480, "height": 400}]},
                  keyProvenance="official answer key", libraryQuestionID="TMUA-2019-P1-Q11")


class StudyCopyTests(unittest.TestCase):
    def setUp(self):
        _, self.topics, self.skills = assemble.load_taxonomy(str(ROOT))

    def test_paper_presented_study_copy_is_valid_without_text(self):
        self.assertEqual(assemble.validate_item(copy.deepcopy(STUDY_COPY), self.topics, self.skills), [])

    def test_study_copy_never_enters_a_public_bundle(self):
        cleared = dict(copy.deepcopy(STUDY_COPY), rights=CLEARED,
                       review=dict(ITEM["review"], originality="not_applicable"))
        self.assertTrue(any("personal study copy" in f for f in assemble.public_gate_failures(cleared)))
        errors = assemble.validate_item(cleared, self.topics, self.skills)
        self.assertTrue(any("cannot claim cleared rights" in e for e in errors))

    def test_study_copy_needs_its_paper_identity_and_letter_only_options(self):
        missing = copy.deepcopy(STUDY_COPY)
        del missing["presentation"]
        del missing["libraryQuestionID"]
        missing["options"][0]["text"] = "transcribed text"
        errors = assemble.validate_item(missing, self.topics, self.skills)
        self.assertTrue(any("shown from its paper" in e for e in errors))
        self.assertTrue(any("libraryQuestionID" in e for e in errors))
        texted = copy.deepcopy(STUDY_COPY)
        texted["options"][0]["text"] = "transcribed text"
        self.assertTrue(any("letters only" in e for e in assemble.validate_item(texted, self.topics, self.skills)))

    def test_presentation_must_point_at_a_bundled_paper(self):
        errors = assemble.validate_item(copy.deepcopy(STUDY_COPY), self.topics, self.skills, str(ROOT))
        self.assertTrue(any("not a bundled paper" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
