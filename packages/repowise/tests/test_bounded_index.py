"""Synthetic admission checks, never starts RepoWise or calls a provider."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from bounded_index import LEASE_OWNER, main, remaining_seconds, require_lease, validate_paths


class AdmissionTests(unittest.TestCase):
    def test_deadline_and_budget(self):
        self.assertEqual(remaining_seconds(1, None), 1)
        with self.assertRaisesRegex(RuntimeError, "deadline"):
            remaining_seconds(900, "2000-01-01T00:00:00Z")
        with self.assertRaisesRegex(ValueError, "timezone"):
            remaining_seconds(900, "2100-01-01T00:00:00")

    def test_lease_rejects_foreign_pid_token_or_owner(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "lease.json"
            expected = {"owner": LEASE_OWNER, "pid": os.getppid(), "token": "synthetic"}
            path.write_text(json.dumps(expected), encoding="utf-8")
            require_lease(path, "synthetic")
            for key, value in (("pid", -1), ("token", "foreign"), ("owner", "foreign")):
                path.write_text(json.dumps({**expected, key: value}), encoding="utf-8")
                with self.assertRaisesRegex(RuntimeError, "not owned"):
                    require_lease(path, "synthetic")
                self.assertTrue(path.exists())

    def test_workspace_and_output_fences(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            workspace, repo = root / "workspace", root / "workspace" / "repo"
            repo.mkdir(parents=True)
            (workspace / ".repowise-workspace.yaml").touch()
            with patch("bounded_index.subprocess.check_output", return_value=str(repo)):
                with self.assertRaisesRegex(RuntimeError, "outside"):
                    validate_paths(workspace, repo, repo / "receipt")
                with self.assertRaisesRegex(RuntimeError, "existing index"):
                    validate_paths(workspace, repo, root / "receipt")
                (repo / ".repowise").mkdir()
                (repo / ".repowise" / "state.json").write_text("{}")
                validate_paths(workspace, repo, root / "receipt")
                with self.assertRaisesRegex(RuntimeError, "member"):
                    validate_paths(workspace, root / "foreign", root / "receipt")

    def exercise_acceptance(self, *, child=None, fences=None, commits=None):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "result"
            successful = {"exitCode": 0, "reason": "exited",
                          "activeProcessesAfterCleanup": 0}
            with patch("bounded_index.require_lease"), patch("bounded_index.validate_paths"), \
                    patch("bounded_index.free_memory", return_value=16 * 1024**3), \
                    patch("bounded_index.shutil.which", return_value="synthetic-cli.exe"), \
                    patch("bounded_index.git_head", return_value="synthetic-head"), \
                    patch("bounded_index.state_commit", side_effect=commits or ["old", "synthetic-head"]), \
                    patch("bounded_index.source_fence", side_effect=fences or [{"sha256": "same"}] * 2), \
                    patch("bounded_index.configure_local_embedder") as embedder, \
                    patch("bounded_index.run", return_value=child or successful) as job:
                result = main(["--workspace", folder, "--repo-root", folder,
                               "--lease", str(Path(folder) / "lease"),
                               "--lease-token", "synthetic", "--output", str(output)])
                args, kwargs = job.call_args
                self.assertIn("--index-only", args[0])
                self.assertIn("--no-agents", args[0])
                self.assertIn("--no-workspace", args[0])
                self.assertEqual(kwargs["memory_bytes"], 8 * 1024**3)
                self.assertLessEqual(kwargs["timeout_seconds"], 900)
                embedder.assert_called_once_with("http://127.0.0.1:8790/v1",
                                                 "text-embedding-3-small")
                receipt = json.loads((output / "acceptance.json").read_text())
                self.assertEqual(receipt["accepted"], result == 0)
                return result

    def test_accepts_only_matching_commit_and_fence(self):
        self.assertEqual(self.exercise_acceptance(), 0)
        self.assertEqual(self.exercise_acceptance(commits=["old", "old"]), 1)
        self.assertEqual(self.exercise_acceptance(
            fences=[{"sha256": "before"}, {"sha256": "after"}]), 1)

    def test_rejects_timeout_failure_and_unreconciled_children(self):
        good = {"exitCode": 0, "reason": "exited", "activeProcessesAfterCleanup": 0}
        for field, value in (("exitCode", 1), ("reason", "timeout"),
                             ("activeProcessesAfterCleanup", 1)):
            self.assertEqual(self.exercise_acceptance(child={**good, field: value}), 1)


if __name__ == "__main__":
    unittest.main()
