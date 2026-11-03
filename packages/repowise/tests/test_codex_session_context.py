"""Synthetic tests; no RepoWise imports, networks, models or real index updates."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "codex_session_context.py"
spec = importlib.util.spec_from_file_location("codex_session_context", SCRIPT)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class SessionContextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.workspace = Path(self.tmp.name)
        self.repo = self.workspace / "repo"
        (self.repo / ".git").mkdir(parents=True)
        (self.repo / ".repowise").mkdir()
        self.state = self.repo / ".repowise" / "state.json"
        self.state.write_text(json.dumps({"last_sync_commit": "a" * 40}))
        self.payload = {"hook_event_name": "SessionStart", "cwd": str(self.repo)}

    def check(self, head="a" * 40, dirty=""):
        with patch.object(hook, "git", side_effect=[head, dirty]):
            return hook.context(self.payload, self.workspace)

    def test_current_clean_is_qualified(self):
        text = self.check()
        self.assertIn("matches HEAD", text)
        self.assertIn("Recorded index commit", text)
        self.assertIn("availability and coverage are unverified", text)
        self.assertIn("Untracked files were not checked", text)
        self.assertNotIn(str(self.repo), text)
        self.assertLessEqual(len(text), 600)

    def test_different_head_and_dirty(self):
        text = self.check("b" * 40, " M source.py")
        self.assertIn("differs from HEAD", text)
        self.assertIn("coverage of them is unknown", text)

    def test_nearest_repository_from_nested_directory(self):
        child = self.repo / "src"
        child.mkdir()
        self.payload["cwd"] = str(child)
        self.assertIn("matches HEAD", self.check())

    def test_missing_and_malformed_state_quiet(self):
        self.state.unlink()
        self.assertIsNone(self.check())
        for value in ['{}', '[]', '{"last_sync_commit":"injected text"}']:
            self.state.write_text(value)
            self.assertIsNone(self.check())
        self.state.write_text("broken json")
        with patch.object(hook.sys, "stdin", io.StringIO(json.dumps(self.payload))), patch.object(hook.sys, "stdout", new_callable=io.StringIO) as out, patch.object(hook, "context", side_effect=ValueError):
            hook.main()
            self.assertEqual(out.getvalue(), "")

    def test_wrong_event_outside_and_relative_cwd_quiet(self):
        for payload in [None, {}, {**self.payload, "hook_event_name":"PostToolUse"}, {**self.payload, "cwd":str(self.workspace.parent)}, {**self.payload, "cwd":"relative"}]:
            self.assertIsNone(hook.context(payload, self.workspace))

    def test_workspace_only_does_not_run_git(self):
        meta = self.workspace / ".repowise-workspace"
        meta.mkdir()
        (meta / "workspace.db").touch()
        with patch.object(hook, "git") as git:
            text = hook.context({**self.payload, "cwd":str(self.workspace)}, self.workspace)
            self.assertIn("freshness was not checked", text)
            git.assert_not_called()

    def test_main_output_shape_cap_and_fail_open(self):
        with patch.object(hook.sys, "stdin", io.StringIO("{}")), patch.object(hook.sys, "stdout", new_callable=io.StringIO) as out, patch.object(hook, "context", return_value="x" * 900):
            hook.main()
            result = json.loads(out.getvalue())["hookSpecificOutput"]
            self.assertEqual(result["hookEventName"], "SessionStart")
            self.assertEqual(len(result["additionalContext"]), 600)
        for error in [subprocess.TimeoutExpired("git", 1), OSError(), ValueError()]:
            with patch.object(hook.sys, "stdin", io.StringIO("{}")), patch.object(hook.sys, "stdout", new_callable=io.StringIO) as out, patch.object(hook, "context", side_effect=error):
                hook.main()
                self.assertEqual(out.getvalue(), "")

    def test_invalid_and_oversized_input_quiet(self):
        for raw in ["broken json", "[]", "x" * (hook.MAX_INPUT + 1)]:
            with patch.object(hook.sys, "stdin", io.StringIO(raw)), patch.object(hook.sys, "stdout", new_callable=io.StringIO) as out:
                hook.main()
                self.assertEqual(out.getvalue(), "")

    def test_oversized_state_and_unindexed_repo_quiet(self):
        self.state.write_text(" " * (hook.MAX_STATE + 1))
        self.assertIsNone(self.check())
        self.state.unlink()
        (self.repo / ".repowise").rmdir()
        self.assertIsNone(self.check())

    def test_bom_state_is_supported(self):
        self.state.write_text(json.dumps({"last_sync_commit": "a" * 40}), encoding="utf-8-sig")
        self.assertIn("matches HEAD", self.check())

    def test_state_read_is_bounded(self):
        class BoundedReader(io.StringIO):
            def read(reader, size=-1):
                self.assertEqual(size, hook.MAX_STATE + 1)
                return super(BoundedReader, reader).read(size)

        reader = BoundedReader(" " * (hook.MAX_STATE + 2))
        original_open = Path.open

        def fake_open(path, *args, **kwargs):
            if path == self.state:
                self.assertEqual(kwargs.get("encoding"), "utf-8-sig")
                return reader
            return original_open(path, *args, **kwargs)

        with patch.object(Path, "open", fake_open), patch.object(hook, "git") as git:
            self.assertIsNone(hook.context(self.payload, self.workspace))
            git.assert_not_called()
    def test_git_hidden_bounded_no_locks(self):
        with patch.object(hook.subprocess, "run") as run:
            run.return_value.stdout = "a" * 40
            hook.git(self.repo, "rev-parse", "HEAD")
            args, kw = run.call_args
            self.assertIn("--no-optional-locks", args[0])
            self.assertIn("core.fsmonitor=false", args[0])
            self.assertEqual(kw["env"]["GIT_OPTIONAL_LOCKS"], "0")
            self.assertEqual(kw["timeout"], 1)
            if hook.os.name == "nt":
                self.assertEqual(kw["creationflags"], subprocess.CREATE_NO_WINDOW)


if __name__ == "__main__":
    unittest.main()
