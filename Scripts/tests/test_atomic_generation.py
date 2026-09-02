import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from atomic_generation import staged_output_set


class AtomicGenerationTests(unittest.TestCase):
    def test_failed_generation_preserves_every_existing_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            resource = root / "Resources"
            resource.mkdir()
            (resource / "old.pdf").write_bytes(b"old")
            manifest = root / "manifest.json"
            manifest.write_text("old-manifest")

            with self.assertRaises(ValueError):
                with staged_output_set([resource, manifest]) as staged:
                    staged[0].mkdir(parents=True)
                    (staged[0] / "new.pdf").write_bytes(b"new")
                    # Deliberately omit staged[1], simulating failed validation.

            self.assertEqual((resource / "old.pdf").read_bytes(), b"old")
            self.assertFalse((resource / "new.pdf").exists())
            self.assertEqual(manifest.read_text(), "old-manifest")

    def test_success_replaces_the_complete_output_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            resource = root / "Resources"
            resource.mkdir()
            (resource / "old.pdf").write_bytes(b"old")
            manifest = root / "manifest.json"
            manifest.write_text("old-manifest")

            with staged_output_set([resource, manifest]) as staged:
                staged[0].mkdir(parents=True)
                (staged[0] / "new.pdf").write_bytes(b"new")
                staged[1].parent.mkdir(parents=True, exist_ok=True)
                staged[1].write_text("new-manifest")

            self.assertFalse((resource / "old.pdf").exists())
            self.assertEqual((resource / "new.pdf").read_bytes(), b"new")
            self.assertEqual(manifest.read_text(), "new-manifest")


if __name__ == "__main__":
    unittest.main()
