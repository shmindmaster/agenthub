import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import factory


class FactoryTests(unittest.TestCase):
    def test_only_allowlisted_apps_and_full_lowercase_commit(self):
        self.assertEqual(factory.validate_request("abacare", "a" * 40), "a" * 40)
        for app, revision in [("anything", "a" * 40), ("abacare", "main"), ("revolva", "A" * 40),
                              ("empowera", "a" * 40 + "\n"), ("abacare", "--all")]:
            with self.subTest(app=app, revision=revision), self.assertRaises(ValueError):
                factory.validate_request(app, revision)

    def test_only_commits_reachable_from_trusted_refs_are_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            def git(*args):
                return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()
            git("init", "-q")
            git("config", "user.email", "test@example.test")
            git("config", "user.name", "Factory Test")
            git("commit", "--allow-empty", "-qm", "base")
            first = git("rev-parse", "HEAD")
            git("commit", "--allow-empty", "-qm", "trusted")
            git("update-ref", "refs/remotes/origin/main", git("rev-parse", "HEAD"))
            git("checkout", "--detach", "-q", first)
            git("commit", "--allow-empty", "-qm", "foreign branch")
            self.assertTrue(factory.trusted_commit(repo, first, ("main",)))
            self.assertFalse(factory.trusted_commit(repo, git("rev-parse", "HEAD"), ("main",)))

    def test_receipt_requires_complete_artifacts_and_verifies_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("tests.log", "capture.webm", "demo.mp4"):
                (root / name).write_text(name, encoding="utf-8")
            preview = {"status": "verified and revoked"}
            workers = {"build": "build-worker", "render": "render-worker"}
            receipt = factory.write_receipt(root, "abacare", "a" * 40, preview, workers)
            self.assertEqual(json.loads((root / "receipt.json").read_text()), receipt)
            self.assertTrue(factory.verify_receipt(root, "abacare", "a" * 40))
            self.assertFalse(factory.verify_receipt(root, "abacare", "b" * 40))
            factory.write_receipt(root, "abacare", "a" * 40, preview, {})
            self.assertFalse(factory.verify_receipt(root, "abacare", "a" * 40))
            factory.write_receipt(root, "abacare", "a" * 40, preview, workers)
            (root / "demo.mp4").write_text("wrong", encoding="utf-8")
            self.assertFalse(factory.verify_receipt(root, "abacare", "a" * 40))
            (root / "demo.mp4").unlink()
            with self.assertRaises(ValueError):
                factory.write_receipt(root, "abacare", "a" * 40, preview, workers)


if __name__ == "__main__":
    unittest.main()
