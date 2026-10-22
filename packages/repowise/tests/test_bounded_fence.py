import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))

import subprocess
import tempfile
import unittest
from unittest.mock import patch
from source_fence import source_fence


class FenceTests(unittest.TestCase):
    def test_content_changes_fail_even_when_git_status_is_unchanged(self):
        with tempfile.TemporaryDirectory(prefix="factory-source-fence-") as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-q", str(repo)], check=True,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            (repo / ".gitignore").write_text(".repowise/\n.vscode/\n")
            (repo / "source.txt").write_text("baseline")
            subprocess.run(["git", "-C", str(repo), "add", "."], check=True,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            baseline = source_fence(repo)
            self.assertEqual(baseline, source_fence(repo))
            (repo / "source.txt").write_text("modified once")
            modified = source_fence(repo)
            self.assertNotEqual(baseline, modified)
            (repo / "source.txt").write_text("modified twice")
            self.assertNotEqual(modified, source_fence(repo))
            untracked = repo / "new.txt"
            baseline = source_fence(repo)
            untracked.write_text("one")
            self.assertNotEqual(baseline, source_fence(repo))
            baseline = source_fence(repo)
            untracked.write_text("two")
            self.assertNotEqual(baseline, source_fence(repo))
            baseline = source_fence(repo)
            (repo / ".repowise").mkdir()
            (repo / ".repowise" / "state.json").write_text("{}")
            self.assertEqual(baseline, source_fence(repo))
            (repo / ".repowise" / "config.yaml").write_text("synthetic: config")
            self.assertNotEqual(baseline, source_fence(repo))
            baseline = source_fence(repo)
            (repo / ".vscode").mkdir()
            (repo / ".vscode" / "mcp.json").write_text("{}")
            self.assertNotEqual(baseline, source_fence(repo))

    def test_git_never_takes_optional_locks(self):
        with tempfile.TemporaryDirectory(prefix="factory-source-fence-") as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-q", str(repo)], check=True,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            (repo / "source.txt").write_text("baseline")
            real, seen = subprocess.check_output, []

            def record(command, *args, **kwargs):
                seen.append(command)
                return real(command, *args, **kwargs)

            with patch("source_fence.subprocess.check_output", side_effect=record):
                source_fence(repo)
            self.assertTrue(seen)
            for command in seen:
                self.assertEqual(command[:2], ["git", "--no-optional-locks"])


if __name__ == "__main__":
    unittest.main()
