"""Isolated native management configuration, without live CLI/OAuth calls."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("clerk_management", ROOT / "scripts/Prepare-ClerkManagement.py")
management = importlib.util.module_from_spec(spec)
spec.loader.exec_module(management)


class ClerkManagementTests(unittest.TestCase):
    def test_default_plan_never_writes(self):
        with patch("sys.argv", ["prepare", "--host", "cursor"]), patch.dict("os.environ", {"LOCALAPPDATA": "C:/private"}), patch.object(management, "prepare") as prepare:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                management.main()
            self.assertEqual(json.loads(output.getvalue())["result"], "plan-only")
            prepare.assert_not_called()

    def test_canonical_endpoint_and_private_configs(self):
        with tempfile.TemporaryDirectory() as temp:
            for host in ("cursor", "amp"):
                plan = management.layout(temp, host)
                path = Path(plan["configPath"])
                self.assertTrue(path.is_relative_to(Path(temp)))
                self.assertIn("https://mcp.clerk.com/mcp", json.dumps(plan["config"]))
                self.assertEqual(management.prepare(plan), "created")
                self.assertEqual(management.prepare(plan), "unchanged")
                self.assertEqual(json.loads(path.read_text()), plan["config"])
                self.assertEqual(plan["execution"], "not-started")

    def test_conflicting_existing_content_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = management.layout(temp, "amp")
            path = Path(plan["configPath"])
            path.parent.mkdir(parents=True)
            content = '{"amp.mcpServers":{"other":{"url":"https://example.org"}}}'
            path.write_text(content)
            with self.assertRaisesRegex(RuntimeError, "preserving"):
                management.prepare(plan)
            self.assertEqual(path.read_text(), content)

    def test_linked_ancestor_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "owner"
            target.mkdir()
            link = root / "linked"
            try:
                link.symlink_to(target, target_is_directory=True)
            except OSError:
                self.skipTest("OS does not allow synthetic symlink creation")
            with self.assertRaisesRegex(RuntimeError, "linked"):
                management.prepare(management.layout(link, "cursor"))
            self.assertEqual(list(target.iterdir()), [])

    def test_amp_commands_always_select_isolated_settings(self):
        plan = management.layout("C:/private", "amp")
        self.assertIn("requires a vendor-supported client ID", plan["loginBlocker"])
        for command in plan["commands"]:
            self.assertEqual(command[1:3], ["--settings-file", plan["configPath"]])
            self.assertNotIn("login", command)

    def test_cursor_approves_only_clerk_before_native_login(self):
        plan = management.layout("C:/private", "cursor")
        self.assertEqual(plan["commands"][0], ["cursor-agent", "mcp", "enable", "clerk"])
        self.assertEqual(plan["commands"][1], ["cursor-agent", "mcp", "login", "clerk"])


if __name__ == "__main__":
    unittest.main()
