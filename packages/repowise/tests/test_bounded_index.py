"""Synthetic admission checks, never starts RepoWise or calls a provider."""
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import bounded_index
from bounded_index import (LEASE_OWNER, cli, main, remaining_seconds, require_editor_files_opt_out,
                           require_lease, validate_paths)
from windows_job import LeaseRetentionError


def runtime_tmp():
    """Scratch dirs beneath the permitted receipt root, wherever TEMP points."""
    root = bounded_index.allowed_output_root() / "tmp"
    root.mkdir(parents=True, exist_ok=True)
    return tempfile.TemporaryDirectory(dir=root)


class AdmissionTests(unittest.TestCase):
    def test_deadline_and_budget(self):
        self.assertEqual(remaining_seconds(1, None), 1)
        with self.assertRaisesRegex(RuntimeError, "deadline"):
            remaining_seconds(900, "2000-01-01T00:00:00Z")
        with self.assertRaisesRegex(ValueError, "timezone"):
            remaining_seconds(900, "2100-01-01T00:00:00")

    def test_deadline_keeps_a_cleanup_reserve(self):
        soon = (datetime.now(timezone.utc) + timedelta(seconds=100)).isoformat()
        self.assertTrue(60 <= remaining_seconds(900, soon) <= 70)
        inside_reserve = (datetime.now(timezone.utc) + timedelta(seconds=20)).isoformat()
        with self.assertRaisesRegex(RuntimeError, "deadline"):
            remaining_seconds(900, inside_reserve)

    def test_lease_rejects_foreign_pid_token_or_owner(self):
        with runtime_tmp() as folder:
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
        with runtime_tmp() as folder:
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

    def exercise_acceptance(self, *, child=None, fences=None, commits=None, waiver=None, free_gib=16):
        with runtime_tmp() as folder:
            output = Path(folder) / "result"
            successful = {"exitCode": 0, "reason": "exited",
                          "activeProcessesBeforeCleanup": 0,
                          "activeProcessesAfterCleanup": 0}
            with patch("bounded_index.require_lease"), patch("bounded_index.validate_paths"), \
                    patch("bounded_index.require_editor_files_opt_out"), \
                    patch("bounded_index.free_memory", return_value=free_gib * 1024**3), \
                    patch("bounded_index.shutil.which", return_value="synthetic-cli.exe"), \
                    patch("bounded_index.git_head", return_value="synthetic-head"), \
                    patch("bounded_index.state_commit", side_effect=commits or ["old", "synthetic-head"]), \
                    patch("bounded_index.source_fence", side_effect=fences or [{"sha256": "same"}] * 2), \
                    patch("bounded_index.configure_remote_embedder") as embedder, \
                    patch("bounded_index.run", return_value=child or successful) as job:
                argv = ["--workspace", folder, "--repo-root", folder,
                               "--lease", str(Path(folder) / "lease"),
                               "--lease-token", "synthetic", "--output", str(output)]
                if waiver is not None:
                    argv += ["--ram-floor-waiver-reason", waiver]
                if free_gib <= 8 and waiver is None:
                    with self.assertRaisesRegex(RuntimeError, "free physical RAM"):
                        main(argv)
                    job.assert_not_called()
                    embedder.assert_not_called()
                    return
                result = main(argv)
                args, kwargs = job.call_args
                self.assertIn("--index-only", args[0])
                self.assertNotIn("--no-agents", args[0])  # it persists editor_files in config.yaml
                self.assertIn("--no-workspace", args[0])
                self.assertEqual(kwargs["memory_bytes"], 8 * 1024**3)
                self.assertEqual(kwargs["minimum_free_bytes"], 0 if waiver else 8 * 1024**3)
                self.assertLessEqual(kwargs["timeout_seconds"], 900)
                self.assertEqual(kwargs["parent_pid"], os.getppid())
                embedder.assert_called_once_with()
                receipt = json.loads((output / "acceptance.json").read_text())
                self.assertEqual(receipt["ramFloorPolicy"]["waived"], waiver is not None)
                self.assertEqual(receipt["ramFloorPolicy"]["waiverReason"], waiver)
                self.assertEqual(receipt["ramFloorPolicy"]["freePhysicalBytesAtAdmission"], free_gib * 1024**3)
                self.assertEqual(receipt["accepted"], result == 0)
                return result

    def test_ram_floor_still_refuses_without_explicit_waiver(self):
        self.exercise_acceptance(free_gib=1)
        self.exercise_acceptance(free_gib=8)

    def test_explicit_waiver_reaches_monitor_and_receipt_but_not_other_gates(self):
        self.assertEqual(self.exercise_acceptance(waiver="Owner waived RAM floor for this run", free_gib=1), 0)
        self.assertEqual(self.exercise_acceptance(waiver="Owner waiver", free_gib=1, commits=["old", "old"]), 1)
        self.assertEqual(self.exercise_acceptance(waiver="Owner waiver", free_gib=1,
            child={"exitCode": 124, "reason": "timeout", "activeProcessesBeforeCleanup": 0,
                   "activeProcessesAfterCleanup": 0}), 1)

    def test_empty_or_oversized_waiver_is_rejected_before_launch(self):
        for reason in ("", "   ", "x" * 513):
            with patch("bounded_index.run") as job, self.assertRaisesRegex(ValueError, "waiver"):
                main(["--workspace", ".", "--repo-root", ".", "--lease", "unused",
                      "--lease-token", "unused", "--output", ".", "--ram-floor-waiver-reason", reason])
            job.assert_not_called()

    def test_accepts_only_matching_commit_and_fence(self):
        self.assertEqual(self.exercise_acceptance(), 0)
        self.assertEqual(self.exercise_acceptance(commits=["old", "old"]), 1)
        self.assertEqual(self.exercise_acceptance(
            fences=[{"sha256": "before"}, {"sha256": "after"}]), 1)

    def test_rejects_timeout_failure_and_unreconciled_children(self):
        good = {"exitCode": 0, "reason": "exited",
                "activeProcessesBeforeCleanup": 0, "activeProcessesAfterCleanup": 0}
        for field, value in (("exitCode", 1), ("reason", "timeout"),
                             ("reason", "parent-exited"),
                             ("activeProcessesBeforeCleanup", 1),
                             ("activeProcessesAfterCleanup", 1)):
            self.assertEqual(self.exercise_acceptance(child={**good, field: value}), 1)

    def run_with_failure(self, failure, *, output_below_workspace=False, stage="run"):
        with runtime_tmp() as folder:
            root = Path(folder).resolve()
            workspace = root / "workspace"
            workspace.mkdir()
            output = (workspace if output_below_workspace else root) / "result"
            patches = [patch("bounded_index.require_lease"),
                       patch("bounded_index.free_memory", return_value=16 * 1024**3),
                       patch("bounded_index.shutil.which", return_value="synthetic-cli.exe"),
                       patch("bounded_index.git_head", return_value="synthetic-head"),
                       patch("bounded_index.state_commit", return_value="synthetic-head"),
                       patch("bounded_index.source_fence", return_value={"sha256": "same"}),
                       patch("bounded_index.configure_remote_embedder")]
            if stage == "run":
                patches += [patch("bounded_index.validate_paths"),
                            patch("bounded_index.require_editor_files_opt_out"),
                            patch("bounded_index.run", side_effect=failure)]
            else:
                patches += [patch("bounded_index.validate_paths", side_effect=failure)]
            for item in patches:
                item.start()
                self.addCleanup(item.stop)
            code = cli(["--workspace", str(workspace), "--repo-root", str(workspace),
                        "--lease", str(root / "lease"), "--lease-token", "synthetic",
                        "--output", str(output)])
            receipt = output / "acceptance.json"
            return code, json.loads(receipt.read_text()) if receipt.exists() else None

    def test_output_must_be_beneath_the_agenthub_runtime_root(self):
        with runtime_tmp() as folder:
            root = Path(folder).resolve()
            allowed, workspace, repo = root / "allowed", root / "workspace", root / "workspace" / "repo"
            for path in (allowed, repo / ".repowise"):
                path.mkdir(parents=True)
            (workspace / ".repowise-workspace.yaml").touch()
            (repo / ".repowise" / "state.json").write_text("{}")
            with patch("bounded_index.subprocess.check_output", return_value=str(repo)), \
                    patch("bounded_index.allowed_output_root", return_value=allowed):
                validate_paths(workspace, repo, allowed / "job")
                for outside in (root / "elsewhere", allowed / ".." / "elsewhere", allowed):
                    with self.assertRaisesRegex(RuntimeError, "AgentHub"):
                        validate_paths(workspace, repo, outside.resolve())

    @unittest.skipUnless(os.name == "nt", "junctions are Windows-only")
    def test_junction_inside_the_root_cannot_smuggle_output_outside_it(self):
        with runtime_tmp() as folder:
            root = Path(folder).resolve()
            allowed, outside = root / "allowed", root / "outside"
            allowed.mkdir()
            outside.mkdir()
            link = allowed / "link"
            subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(outside)], check=True,
                           capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            with patch("bounded_index.allowed_output_root", return_value=allowed):
                self.assertFalse(bounded_index.output_permitted((link / "job").resolve()))
                self.assertTrue(bounded_index.output_permitted((allowed / "job").resolve()))

    def test_rejected_output_location_gets_no_admission_receipt(self):
        with runtime_tmp() as folder:
            root = Path(folder).resolve()
            allowed, output = root / "allowed", root / "elsewhere"
            allowed.mkdir()
            with patch("bounded_index.allowed_output_root", return_value=allowed):
                bounded_index.write_admission_failure(root / "workspace", output, RuntimeError("x"))
            self.assertFalse(output.exists())

    def test_instruction_file_regeneration_must_already_be_opted_out(self):
        with runtime_tmp() as folder:
            repo = Path(folder)
            (repo / ".repowise").mkdir()
            config = repo / ".repowise" / "config.yaml"
            with self.assertRaisesRegex(RuntimeError, "claude_md"):
                require_editor_files_opt_out(repo)  # no config: managed CLAUDE.md would be rewritten
            for text, fails in (("editor_files:\n  claude_md: false\n", False),
                                ("editor_files: {claude_md: false, agents_md: false}\n", False),
                                ("editor_files:\n  claude_md: true\n", True),
                                ("provider: openai\n", True),
                                ("editor_files:\n  claude_md: false\n  agents_md: true\n", True),
                                ("editor_files: {claude_md: false, agents_md: true}\n", True)):
                config.write_text(text, encoding="utf-8")
                if fails:
                    with self.assertRaises(RuntimeError, msg=text):
                        require_editor_files_opt_out(repo)
                else:
                    require_editor_files_opt_out(repo)
                self.assertEqual(config.read_text(encoding="utf-8"), text)  # never rewritten

    def test_retention_wins_when_the_receipt_cannot_be_written(self):
        real = Path.write_text

        def refuse(path, *args, **kwargs):
            if path.name == "acceptance.json":
                raise OSError("synthetic disk failure")
            return real(path, *args, **kwargs)

        with patch("pathlib.Path.write_text", refuse):
            code, receipt = self.run_with_failure(LeaseRetentionError("synthetic"))
        self.assertEqual(code, 3)
        self.assertIsNone(receipt)

    def test_unreconciled_processes_exit_with_the_lease_retention_code(self):
        code, receipt = self.run_with_failure(LeaseRetentionError("synthetic"))
        self.assertEqual(code, 3)
        body = receipt
        self.assertFalse(body["accepted"])
        self.assertEqual(body["failure"], "LeaseRetentionError")

    def test_ordinary_failure_exits_one_with_a_receipt(self):
        code, receipt = self.run_with_failure(RuntimeError("synthetic"))
        self.assertEqual(code, 1)
        self.assertEqual(receipt["failure"], "RuntimeError")

    def test_early_failure_writes_a_minimal_non_accepted_receipt(self):
        code, receipt = self.run_with_failure(RuntimeError("synthetic path detail"), stage="early")
        self.assertEqual(code, 1)
        body = receipt
        self.assertEqual(body, {"accepted": False, "failure": "RuntimeError", "stage": "admission"})

    def test_early_failure_never_writes_receipts_into_the_source_workspace(self):
        code, receipt = self.run_with_failure(RuntimeError("synthetic"), stage="early",
                                              output_below_workspace=True)
        self.assertEqual(code, 1)
        self.assertIsNone(receipt)


if __name__ == "__main__":
    unittest.main()
