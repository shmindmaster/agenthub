"""Safety/behavior checks for targeted official Clerk rollout, no live CLI calls."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("clerk_fleet", ROOT / "scripts/Install-ClerkFleet.py")
fleet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fleet)


class ClerkFleetTests(unittest.TestCase):
    def test_plan_has_no_subprocess_or_filesystem_side_effect(self):
        with patch("sys.argv", ["installer", "--host", "cursor-agent"]), patch.object(fleet, "run") as run:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                fleet.main()
            self.assertEqual(json.loads(output.getvalue())["hosts"], ["cursor"])
            run.assert_not_called()

    def test_direct_merge_preserves_other_servers_and_existing_auth_state(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "config.json"
            data = {"otherSetting": True, "mcpServers": {"other": {"url": "https://example.org"},
                    "clerk": {"url": fleet.URL, "disabled": False, "existingOAuthSetting": True}}}
            path.write_text(json.dumps(data), encoding="utf-8")
            fleet.merge_mcp(path)
            actual = json.loads(path.read_text())
            self.assertEqual(actual["mcpServers"]["other"], data["mcpServers"]["other"])
            self.assertFalse(actual["mcpServers"]["clerk"]["disabled"])
            self.assertTrue(actual["mcpServers"]["clerk"]["existingOAuthSetting"])
            self.assertTrue(actual["otherSetting"])

    def test_conflicting_endpoint_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "config.json"
            before = '{"mcpServers":{"clerk":{"url":"https://other.invalid"}}}'
            path.write_text(before)
            with self.assertRaisesRegex(RuntimeError, "Conflicting"):
                fleet.merge_mcp(path)
            self.assertEqual(path.read_text(), before)

    def test_local_process_entry_is_not_silently_converted_or_retained(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "config.json"
            before = '{"mcpServers":{"clerk":{"command":"legacy-clerk","args":[]}}}'
            path.write_text(before)
            with self.assertRaisesRegex(RuntimeError, "Conflicting"):
                fleet.merge_mcp(path)
            self.assertEqual(path.read_text(), before)

    @unittest.skipUnless(fleet.os.name == "nt", "Windows wrapper safety")
    def test_windows_wrapper_rejects_shell_metacharacters_before_launch(self):
        with patch.object(fleet.shutil, "which", return_value="C:/tools/vendor.cmd"), patch.object(fleet.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "metacharacters"):
                fleet.run(["vendor", "unsafe&value"])
            run.assert_not_called()

    @unittest.skipUnless(fleet.os.name == "nt", "Windows wrapper quoting")
    def test_windows_wrapper_preserves_spaces_in_executable_and_argument(self):
        with tempfile.TemporaryDirectory(prefix="clerk fleet ") as temp:
            script = Path(temp) / "vendor wrapper.cmd"
            script.write_text('@echo off\n@echo %~1\n', encoding="utf-8")
            self.assertEqual(fleet.run([str(script), "literal value with spaces"]), "literal value with spaces")

    def test_gemini_preserves_conflicting_local_process_entry(self):
        with tempfile.TemporaryDirectory() as temp:
            home, upstream = Path(temp) / "home", Path(temp) / "upstream"
            (upstream / "skills").mkdir(parents=True)
            path = home / ".gemini/settings.json"
            path.parent.mkdir(parents=True)
            original = '{"mcpServers":{"clerk":{"command":"legacy","args":[]}}}'
            path.write_text(original)
            with self.assertRaisesRegex(RuntimeError, "Conflicting"):
                fleet.bridge("gemini", upstream, home)
            self.assertEqual(path.read_text(), original)

    def test_cursor_companion_rejects_linked_rules_ancestor(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            path, _ = fleet.companion_rule(home)
            original = fleet.Path.is_junction
            with patch.object(fleet.Path, "is_junction", lambda p: p == path.parent or original(p)):
                with self.assertRaisesRegex(RuntimeError, "linked"):
                    fleet.deploy_companion(home)
            self.assertFalse(path.exists())

    def test_cursor_companion_matches_canonical_policy_and_preserves_other_rules(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            other = home / ".cursor/rules/owner.mdc"
            other.parent.mkdir(parents=True)
            other.write_text("Always preserve this owner rule.")
            fleet.deploy_companion(home)
            path, expected = fleet.companion_rule(home)
            self.assertEqual(path.read_text(), expected)
            self.assertIn("alwaysApply: true", expected)
            self.assertIn("direct backend access", expected)
            self.assertEqual(other.read_text(), "Always preserve this owner rule.")
            fleet.deploy_companion(home)
            self.assertEqual(path.read_text(), expected)

    def test_cursor_companion_refuses_owner_authored_same_name(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            path, _ = fleet.companion_rule(home)
            path.parent.mkdir(parents=True)
            path.write_text("Owner-authored conflicting file.")
            with self.assertRaisesRegex(RuntimeError, "owner-authored"):
                fleet.deploy_companion(home)
            self.assertEqual(path.read_text(), "Owner-authored conflicting file.")

    @unittest.skipUnless(fleet.os.name == "nt", "Windows fleet audit")
    def test_audit_fails_when_cursor_guidance_is_missing_or_stale(self):
        row = {"cursor": {"matchingOfficialSkills": 20, "remoteConfigured": True,
                          "qaGuidanceConfigured": False}}
        with patch("sys.argv", ["installer", "--audit"]), patch.object(fleet, "audit", return_value=row):
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as result:
                fleet.main()
            self.assertEqual(result.exception.code, 1)

    def test_remote_audit_requires_exact_clerk_entry_not_incidental_url(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "config.json"
            path.write_text(json.dumps({"note": fleet.URL, "mcpServers": {
                "clerk": {"url": "https://other.invalid"}}}))
            self.assertFalse(fleet.has_remote(path))
            path.write_text(json.dumps({"mcpServers": {"clerk": {"url": fleet.URL}}}))
            self.assertTrue(fleet.has_remote(path))

    def test_shared_skill_destination_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(fleet.Path, "home", return_value=Path(temp)):
            source = Path(temp) / "source"
            source.mkdir()
            with self.assertRaisesRegex(RuntimeError, "shared"):
                fleet.copy_official(source, Path(temp) / ".agents/skills/clerk")

    def test_amp_attaches_one_remote_to_routing_skill_and_registers_all_skills(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp) / "home"
            upstream = Path(temp) / "upstream"
            for name in ("clerk", "clerk-testing"):
                skill = upstream / "skills" / name
                skill.mkdir(parents=True)
                (skill / "SKILL.md").write_text("---\nname: " + name + "\n---\n")
            fleet.bridge("amp", upstream, home)
            target = home / ".config/amp/plugins/clerk"
            self.assertIn("skills/clerk-testing", (target / "index.ts").read_text())
            self.assertEqual(json.loads((target / "skills/clerk/mcp.json").read_text()),
                             {"clerk": {"url": fleet.URL}})
            self.assertFalse((target / "skills/clerk-testing/mcp.json").exists())

    def test_every_active_surface_has_a_rollout_route(self):
        agents = json.loads((ROOT / "registry/agents.json").read_text(encoding="utf-8-sig"))
        supported = set(fleet.NATIVE) | fleet.BRIDGES | set(fleet.ALIASES)
        self.assertFalse({a["id"] for a in agents["activeAgents"]} - supported)


if __name__ == "__main__":
    unittest.main()
