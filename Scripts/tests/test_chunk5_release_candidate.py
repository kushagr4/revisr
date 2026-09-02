import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "chunk5_audit", ROOT / "Scripts" / "audit_chunk5_release_candidate.py"
)
chunk5_audit = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(chunk5_audit)


class Chunk5ReleaseCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.release_store = ROOT / ".qa/chunk5/release-candidate-snapshot/Revisr.store"
        cls.baseline_store = ROOT / ".qa/chunk4/pre-migration-device/Revisr.store"
        if not cls.release_store.exists() or not cls.baseline_store.exists():
            raise unittest.SkipTest("trusted release-candidate fixtures are unavailable")
        cls.audit = chunk5_audit.run_audit(cls.release_store, cls.baseline_store)

    def test_release_candidate_passes_every_structural_and_resource_gate(self):
        self.assertEqual(self.audit["verdict"], "PASS")
        self.assertTrue(all(self.audit["validations"].values()))
        self.assertEqual(self.audit["integrity"], "ok")
        self.assertEqual(self.audit["missingResources"], [])
        self.assertEqual(self.audit["checksumMismatches"], [])
        self.assertEqual(self.audit["invalidPageOrMediaLinks"], [])

    def test_history_streams_protection_and_bundle_are_exact(self):
        self.assertTrue(all(item["unchanged"] for item in self.audit["historicalComparison"].values()))
        self.assertEqual(
            self.audit["d1D3Fingerprint"],
            "326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e",
        )
        self.assertEqual(self.audit["tmua2022ProtectedCount"], 40)
        self.assertEqual(self.audit["resourceBundle"]["pdfCount"], 234)
        self.assertEqual(self.audit["resourceBundle"]["videoCount"], 8)
        self.assertEqual(
            self.audit["canonicalStreamCounts"],
            {"bmo": 93, "csat": 80, "nil": 763, "smc": 300, "tmua": 1364},
        )
        self.assertEqual(
            self.audit["intendedUseCounts"],
            {"bmo": 93, "cambridgeCSInterview": 268, "csat": 348, "smc": 300, "tmua": 1920},
        )


if __name__ == "__main__":
    unittest.main()
