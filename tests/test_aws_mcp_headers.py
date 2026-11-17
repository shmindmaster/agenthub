import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("aws_headers", Path(__file__).resolve().parents[1] / "scripts/aws-mcp-headers.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class AwsHeadersTests(unittest.TestCase):
    def invoke(self, grant=None, returncode=0, side_effect=None):
        response = subprocess.CompletedProcess([], returncode, json.dumps(grant or {"accessToken": "synthetic-token", "expiresIn": 3600}), "secret synthetic stderr")
        with patch.object(helper.shutil, "which", return_value=sys.executable), patch.object(helper.subprocess, "run", return_value=response, side_effect=side_effect) as run:
            headers = helper.get_headers("selected-account", "us-east-1", None)
        return headers, run.call_args

    def test_explicit_profile_overrides_inherited_identity_and_endpoint(self):
        with patch.dict(os.environ, {"AWS_ACCESS_KEY_ID": "other-account", "AWS_SESSION_TOKEN": "other-token", "AWS_PROFILE": "other", "AWS_ENDPOINT_URL_SIGNIN": "https://example.invalid"}):
            headers, call = self.invoke()
        self.assertEqual(headers, {"Authorization": "Bearer synthetic-token"})
        command = call.args[0]
        self.assertEqual(command[command.index("--profile") + 1], "selected-account")
        self.assertEqual(command[command.index("--resource") + 1], "aws-mcp.amazonaws.com")
        for key in ("AWS_ACCESS_KEY_ID", "AWS_SESSION_TOKEN", "AWS_PROFILE", "AWS_ENDPOINT_URL_SIGNIN"):
            self.assertNotIn(key, call.kwargs["env"])
        self.assertEqual(call.kwargs["timeout"], 8)
        self.assertTrue(call.kwargs["capture_output"])

    def test_new_grant_on_each_refresh(self):
        first, _ = self.invoke({"accessToken": "first", "expiresIn": 3600})
        second, _ = self.invoke({"accessToken": "second", "expiresIn": 3600})
        self.assertNotEqual(first, second)

    def test_failed_grant_never_uses_stdout(self):
        with self.assertRaises(RuntimeError):
            self.invoke(returncode=1)

    def test_rejects_control_characters(self):
        with self.assertRaises(RuntimeError):
            self.invoke({"accessToken": "synthetic\nheader", "expiresIn": 3600})

    def test_rejects_expired_grant(self):
        with self.assertRaises(RuntimeError):
            self.invoke({"accessToken": "synthetic", "expiresIn": 1})

    def test_missing_cli_fails_before_network(self):
        with patch.object(helper.shutil, "which", return_value=None), patch.object(helper.subprocess, "run") as run:
            with self.assertRaises(RuntimeError):
                helper.get_headers("selected-account", "us-east-1", None)
            run.assert_not_called()

    def test_failures_are_redacted(self):
        for error in (RuntimeError("secret-value"), subprocess.TimeoutExpired("secret-command", 8), json.JSONDecodeError("secret-value", "secret-value", 0)):
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.object(sys, "argv", ["helper", "--profile", "selected-account"]), patch.object(helper, "get_headers", side_effect=error), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(helper.main(), 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertNotIn("secret", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
