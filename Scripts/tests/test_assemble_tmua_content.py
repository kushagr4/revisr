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


def write_approval(content_dir, items, reviewer="rev-a", name="A. Reviewer", revision=1, grants=None,
                   register_items=None):
    """The private workspace files an approval needs: reviewer registry, register decisions and a
    manifest, in the shapes tools/review_workflow.py and tools/approved_manifest.py write."""
    content_dir = Path(content_dir)
    (content_dir / "review").mkdir(parents=True, exist_ok=True)
    (content_dir / "approved").mkdir(parents=True, exist_ok=True)
    (content_dir / "review" / "reviewers.json").write_text(json.dumps(
        {"schema": 1, "reviewers": {reviewer: {"name": name, "roles": ["mathematical", "owner"]}}}))
    register, manifest = {"schema": 2, "items": {}}, {
        "schema": assemble.MANIFEST_SCHEMA, "policyVersion": assemble.APPROVAL_POLICY_VERSION,
        "revision": revision, "approvedOriginal": [], "approvedLicensed": []}
    for item in items:
        digest = assemble.content_hash(item)
        stages = assemble.REQUIRED_STAGES[item["category"]]
        register["items"][assemble.version_key(item)] = {"human": {
            stage: {"decision": "approved", "reviewer": reviewer, "date": "2026-10-28", "contentHash": digest,
                    "notes": "private reviewer note"} for stage in stages}}
        entry = {"versionKey": assemble.version_key(item), "contentHash": digest, "approvedOn": "2026-10-28",
                 "approvals": {stage: {"decision": "approved", "reviewer": reviewer, "date": "2026-10-28"}
                               for stage in stages}}
        if item["category"] != "revisr_original":
            entry["rightsGrant"] = "grant-fixture"
        manifest["approvedOriginal" if item["category"] == "revisr_original" else "approvedLicensed"].append(entry)
    if register_items is not None:
        register["items"] = register_items(register["items"])
    (content_dir / "review" / "register.json").write_text(json.dumps(register))
    (content_dir / "approved" / "manifest.json").write_text(json.dumps(manifest))
    for grant in grants or []:
        (content_dir / "rights" / "grants").mkdir(parents=True, exist_ok=True)
        (content_dir / "rights" / "grants" / (grant["grantId"] + ".json")).write_text(json.dumps(grant))
    return manifest


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
            draft["stem"] = "A second synthetic stem."
            draft["review"]["publication"] = "not_approved"
            (bank_dir / "items.json").write_text(json.dumps({"bankFile": "test", "items": [ITEM, draft]}))
            write_approval(bank_dir.parent, [ITEM])
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


LICENSED = dict(copy.deepcopy(ITEM), stableId="lic-board-2019-p1-q04", category="licensed_past_paper",
                stem="A licensed synthetic stem.",
                source={"organisation": "Fixture Board", "examination": "Fixture Exam", "year": 2019,
                        "paperNumber": 1, "questionNumber": 4, "url": "https://example.invalid/papers",
                        "attribution": None},
                rights=dict(CLEARED, inAppUse="pending_review", redistribution="pending_review",
                            commercialUse="pending_review", answerKey="pending_review", solution="pending_review"),
                review={"mathematical": "ai_derivation_only", "originality": "not_applicable",
                        "publication": "not_approved", "editorialStatus": "draft"})

GRANT = {"grantId": "grant-fixture", "provider": "fixture-board", "status": "verified",
         "copyrightHolder": "Fixture Board", "licence": "Written permission (fixture)",
         "attributionText": "Source: Fixture Board · Fixture Exam 2019 Paper 1 · Q4 · used with permission",
         "permits": {permission: True for permission in assemble.GRANT_PERMISSIONS},
         "scope": [{"organisation": "Fixture Board", "examination": "Fixture Exam", "year": 2019, "paperNumber": 1}],
         "evidence": {"file": "rights/evidence/fixture.pdf", "receivedOn": "2026-10-28", "verifiedBy": "rev-a"}}

DRAFT = dict(copy.deepcopy(ITEM), review={"mathematical": "ai_derivation_only", "originality": "pending",
                                          "publication": "not_approved", "editorialStatus": "draft"},
             rights=dict(CLEARED, inAppUse="pending_review"))


class ApprovedManifestTests(unittest.TestCase):
    """The public bank comes only from the approved-content manifest, never from item fields."""

    def build(self, items, approve=None, **options):
        directory = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(directory, ignore_errors=True))
        bank_dir = Path(directory) / "content" / "bank"
        bank_dir.mkdir(parents=True)
        (bank_dir / "items.json").write_text(json.dumps({"bankFile": "test", "items": items}))
        if approve is not None:
            write_approval(bank_dir.parent, approve, **options)
        return str(bank_dir.parent), str(Path(directory) / "app" / assemble.BANK_FILENAME)

    def test_no_manifest_means_an_empty_public_bank_even_for_fully_cleared_fields(self):
        content, output = self.build([ITEM])
        bank = assemble.assemble(content, str(ROOT), "public", output)
        self.assertEqual(bank["items"], [])
        self.assertIsNone(bank["approvedManifestRevision"])

    def test_approved_draft_is_published_with_review_and_rights_from_the_manifest(self):
        content, output = self.build([DRAFT], approve=[DRAFT])
        bank = assemble.assemble(content, str(ROOT), "public", output)
        [item] = bank["items"]
        self.assertEqual(item["review"]["publication"], "approved")
        self.assertIsNone(item["review"]["notes"])
        self.assertEqual(item["approval"]["contentHash"], assemble.content_hash(DRAFT))
        self.assertEqual(bank["approvedManifestRevision"], 1)
        self.assertNotIn("rev-a", json.dumps(bank), "reviewer identities never ship")
        self.assertNotIn("private reviewer note", json.dumps(bank))
        assemble.check_app(str(Path(output).parent), str(ROOT), "public")

    def test_public_bank_uses_the_reviewers_difficulty_rating_for_this_content(self):
        def rate(level, digest):
            def apply(items):
                for entry in items.values():
                    entry["human"]["difficultyRating"] = {"level": level, "minutes": 5, "reviewer": "rev-a",
                                                          "contentHash": digest}
                return items
            return apply
        content, output = self.build([DRAFT], approve=[DRAFT],
                                     register_items=rate(4, assemble.content_hash(DRAFT)))
        [item] = assemble.assemble(content, str(ROOT), "public", output)["items"]
        self.assertEqual((item["difficulty"], item["estimatedMinutes"]), (4, 5))
        self.assertIn("independent reviewer", item["difficultyProvenance"])
        content, output = self.build([DRAFT], approve=[DRAFT], register_items=rate(4, "stale"))
        [item] = assemble.assemble(content, str(ROOT), "public", output)["items"]
        self.assertEqual(item["difficulty"], DRAFT["difficulty"], "a rating of other content is ignored")

    def test_internal_build_ignores_the_manifest_and_keeps_drafts_labelled(self):
        content, output = self.build([DRAFT], approve=[DRAFT])
        [item] = assemble.assemble(content, str(ROOT), "internal", output)["items"]
        self.assertEqual(item["review"]["publication"], "not_approved")

    def test_content_changed_after_approval_stops_the_build(self):
        changed = dict(copy.deepcopy(DRAFT), stem="Silently edited stem.")
        content, output = self.build([changed], approve=[DRAFT])
        with self.assertRaises(SystemExit):
            assemble.assemble(content, str(ROOT), "public", output)

    def test_difficulty_estimate_is_outside_the_content_hash(self):
        revised = dict(copy.deepcopy(DRAFT), difficulty=4, estimatedMinutes=5)
        self.assertEqual(assemble.content_hash(revised), assemble.content_hash(DRAFT))
        self.assertNotEqual(assemble.content_hash(dict(DRAFT, correctOptionId="B")), assemble.content_hash(DRAFT))
        reordered = json.loads(json.dumps(DRAFT, sort_keys=True))
        self.assertEqual(assemble.content_hash(reordered), assemble.content_hash(DRAFT))

    def test_manifest_without_matching_register_decisions_stops_the_build(self):
        content, output = self.build([DRAFT], approve=[DRAFT], register_items=lambda items: {})
        with self.assertRaises(SystemExit):
            assemble.assemble(content, str(ROOT), "public", output)

    def test_missing_stage_stops_the_build(self):
        def drop_originality(items):
            for entry in items.values():
                entry["human"].pop("originality")
            return items
        content, output = self.build([DRAFT], approve=[DRAFT], register_items=drop_originality)
        with self.assertRaises(SystemExit):
            assemble.assemble(content, str(ROOT), "public", output)

    def test_ai_reviewer_cannot_approve(self):
        for name in ("Claude", "GPT-5 reviewer", "AI assistant"):
            content, output = self.build([DRAFT], approve=[DRAFT], name=name)
            with self.assertRaises(SystemExit, msg=name):
                assemble.assemble(content, str(ROOT), "public", output)
        self.assertFalse(assemble.is_ai_name("Claudette Morel"))

    def test_study_copies_and_fixtures_can_never_be_published(self):
        study = dict(copy.deepcopy(STUDY_COPY))
        study.pop("presentation")
        study["stem"] = "Transcribed official question."
        study["options"] = [{"id": letter, "text": letter} for letter in "ABCDEF"]
        self.assertIsNone(assemble.REQUIRED_STAGES.get("past_paper_study_copy"))
        self.assertIsNone(assemble.REQUIRED_STAGES.get("development_fixture"))
        entry = {"versionKey": assemble.version_key(study), "contentHash": assemble.content_hash(study)}
        self.assertIn("can never be published", assemble.approval_problems(entry, study, {}, {}, None)[0])

    def test_licensed_question_needs_a_verified_grant_that_covers_it(self):
        content, output = self.build([LICENSED], approve=[LICENSED])
        with self.assertRaises(SystemExit):
            assemble.assemble(content, str(ROOT), "public", output)  # no grant file
        content, output = self.build([LICENSED], approve=[LICENSED], grants=[dict(GRANT, status="requested")])
        with self.assertRaises(SystemExit):
            assemble.assemble(content, str(ROOT), "public", output)
        narrow = dict(GRANT, scope=[{"organisation": "Fixture Board", "year": 2018}])
        content, output = self.build([LICENSED], approve=[LICENSED], grants=[narrow])
        with self.assertRaises(SystemExit):
            assemble.assemble(content, str(ROOT), "public", output)
        partial = dict(GRANT, permits=dict(GRANT["permits"], workedSolutions=False))
        content, output = self.build([LICENSED], approve=[LICENSED], grants=[partial])
        with self.assertRaises(SystemExit):
            assemble.assemble(content, str(ROOT), "public", output)
        content, output = self.build([LICENSED], approve=[LICENSED], grants=[GRANT])
        [item] = assemble.assemble(content, str(ROOT), "public", output)["items"]
        self.assertEqual(item["source"]["attribution"], GRANT["attributionText"])
        self.assertEqual(item["rights"]["copyrightHolder"], "Fixture Board")
        self.assertEqual(item["approval"]["rightsGrant"], "grant-fixture")

    def test_unsupported_markup_fails_the_format_check(self):
        self.assertEqual(assemble.format_failures(ITEM), [])
        unsupported = dict(ITEM, stem="Find \\(\\mathbb{R}\\).")
        self.assertTrue(any("mathbb" in failure for failure in assemble.format_failures(unsupported)))
        raw = dict(ITEM, solution="The answer is \\frac{1}{2} outside maths.")
        self.assertTrue(any("raw TeX" in failure for failure in assemble.format_failures(raw)))
        supported = dict(ITEM, stem="If \\(x \\ge 0\\) then \\(\\sqrt{x^2} = x\\) and \\[\\int_0^1 x\\,dx = \\frac{1}{2}\\]")
        self.assertEqual(assemble.format_failures(supported), [])

    def test_renderer_command_list_matches_the_app(self):
        source = (ROOT / "revisr" / "DesignSystem" / "MathText.swift").read_text()
        symbols = source.split("static let symbols: [String: String] = [", 1)[1].split("]", 1)[0]
        names = set(__import__("re").findall(r'"((?:[^"\\\\]|\\\\.)*)":', symbols))
        names = {name.replace("\\\\", "") if name != "\\\\," else "," for name in names}
        functions = source.split("static let functionNames: Set<String> = [", 1)[1].split("]", 1)[0]
        names |= set(__import__("re").findall(r'"([a-z]+)"', functions))
        for block in __import__("re").findall(r'case ("[a-z]+"(?:, "[a-z]+")*):', source):
            names |= set(__import__("re").findall(r'"([a-z]+)"', block))
        self.assertEqual(names - assemble.RENDERER_COMMANDS, set(), "renderer supports commands the gate rejects")
        self.assertEqual(assemble.RENDERER_COMMANDS - names, set(), "gate accepts commands the renderer lacks")

    def test_duplicate_question_text_is_a_validation_problem(self):
        twin = dict(copy.deepcopy(ITEM), stableId="test-item-twin")
        content, _ = self.build([ITEM, twin])
        problems = assemble.validate_bank(content, str(ROOT))[2]
        self.assertTrue(any("repeats the question text" in problem for problem in problems))

    def test_release_gate_rejects_tampered_items_and_private_review_files(self):
        content, output = self.build([DRAFT], approve=[DRAFT])
        assemble.assemble(content, str(ROOT), "public", output)
        app = Path(output).parent
        bank = json.loads(Path(output).read_text())
        bank["items"][0]["correctOptionId"] = "B"
        Path(output).write_text(json.dumps(bank))
        with self.assertRaises(SystemExit):
            assemble.check_app(str(app), str(ROOT), "public")
        assemble.assemble(content, str(ROOT), "public", output)
        (app / "manifest.json").write_text("{}")
        with self.assertRaises(SystemExit):
            assemble.check_app(str(app), str(ROOT), "public")


    def test_release_gate_rejects_private_fields_in_the_catalogue_reconciliation(self):
        content, output = self.build([DRAFT], approve=[DRAFT])
        assemble.assemble(content, str(ROOT), "public", output)
        app = Path(output).parent
        target = app / assemble.RECONCILIATION_FILENAME
        target.write_text(json.dumps({"documents": [{"questions": [{"questionID": "X-Q1", "page": 3}]}]}))
        assemble.check_app(str(app), str(ROOT), "public")
        target.write_text(json.dumps({"documents": [{"driveFileID": "abc", "questions": [{"answerLetter": "C"}]}]}))
        with self.assertRaises(SystemExit):
            assemble.check_app(str(app), str(ROOT), "public")
        bundled = ROOT / "revisr" / "Resources" / assemble.RECONCILIATION_FILENAME
        self.assertEqual(assemble.reconciliation_failures(str(bundled.parent)), [],
                         "the committed reconciliation file holds metadata only")


if __name__ == "__main__":
    unittest.main()
