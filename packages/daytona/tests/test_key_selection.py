"""Offline credential routing tests; only synthetic values enter child processes."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills/daytona/scripts/with-key.py"


class KeySelectionTests(unittest.TestCase):
    def run_child(self, *args, env=None):
        clean = {k: v for k, v in os.environ.items() if not k.startswith("DAYTONA_")}
        clean.update(env or {})
        return subprocess.run([sys.executable, str(SCRIPT), *args], env=clean,
                              capture_output=True, text=True)

    def test_default_keeps_primary_and_exit_status(self):
        r = self.run_child("--", sys.executable, "-c",
            "import os,sys; sys.exit(17 if os.environ['DAYTONA_API_KEY']=='synthetic-primary' else 19)",
            env={"DAYTONA_API_KEY": "synthetic-primary", "DAYTONA_API_KEY1": "synthetic-secondary"})
        self.assertEqual(r.returncode, 17, r.stderr)
        self.assertNotIn("synthetic-", r.stdout + r.stderr)

    def test_explicit_secondary_maps_only_child_primary(self):
        r = self.run_child("--key", "DAYTONA_API_KEY1", "--", sys.executable, "-c",
            "import os,sys; sys.exit(0 if os.environ['DAYTONA_API_KEY']=='synthetic-secondary' and os.environ['DAYTONA_KEY_REF']=='DAYTONA_API_KEY1' else 19)",
            env={"DAYTONA_API_KEY": "synthetic-primary", "DAYTONA_API_KEY1": "synthetic-secondary"})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("synthetic-", r.stdout + r.stderr)

    def test_missing_primary_does_not_fall_back(self):
        r = self.run_child("--", sys.executable, "-c", "raise Exception('child ran')",
                           env={"DAYTONA_API_KEY1": "synthetic-secondary"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("DAYTONA_API_KEY is unavailable", r.stderr)
        self.assertNotIn("child ran", r.stderr)

    def test_missing_secondary_does_not_fall_back(self):
        r = self.run_child("--key", "DAYTONA_API_KEY1", "--", sys.executable, "-c", "print('child ran')",
                           env={"DAYTONA_API_KEY": "synthetic-primary"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("DAYTONA_API_KEY1 is unavailable", r.stderr)
        self.assertNotIn("child ran", r.stdout)

    def test_arbitrary_secret_name_refused(self):
        r = self.run_child("--key", "OTHER_SECRET", "--", sys.executable, "-c", "print('child ran')")
        self.assertEqual(r.returncode, 2)
        self.assertIn("invalid choice", r.stderr)
        self.assertNotIn("child ran", r.stdout)

    def test_restored_sdk_references(self):
        for language in ("go", "java", "ruby"):
            self.assertTrue((ROOT / f"skills/daytona/references/{language}-sdk/README.md").is_file())

    def test_moved_workflow_links_resolve(self):
        import re
        doc = ROOT / "skills/daytona/references/sdk-workflows.md"
        for target in re.findall(r"\]\((\./[^)#]+)(?:#[^)]*)?\)", doc.read_text(encoding="utf-8")):
            self.assertTrue((doc.parent / target).exists(), target)


if __name__ == "__main__":
    unittest.main()
