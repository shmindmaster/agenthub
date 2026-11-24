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


def inactive_hosts():
    """Ids the registry lists under inactiveAgents; read directly so the tests do not depend on installer internals."""
    registry = json.loads((ROOT / "registry/agents.json").read_text(encoding="utf-8-sig"))
    return {agent["id"] for agent in registry.get("inactiveAgents", [])}


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

    def test_skills_only_hosts_get_official_skills_and_no_mcp_entry(self):
        policy = json.loads((ROOT / "registry/mcps.json").read_text(encoding="utf-8-sig"))["activationPolicy"]["pluginOnly"]["hosts"]
        for host, root in fleet.SKILLS_ONLY.items():
            self.assertNotIn("clerk", policy[host], host)
            with tempfile.TemporaryDirectory() as temp, patch.object(fleet, "run") as run:
                home = Path(temp) / "home"
                upstream = Path(temp) / "upstream"
                skill = upstream / "skills" / "clerk"
                skill.mkdir(parents=True)
                (skill / "SKILL.md").write_text("---\nname: clerk\n---\n")
                fleet.bridge(host, upstream, home)
                run.assert_not_called()
                self.assertTrue((home / root / "skills/clerk/SKILL.md").is_file())
                self.assertEqual([p.name for p in (home / root).iterdir()], ["skills"])

    @unittest.skipUnless(fleet.os.name == "nt", "Windows fleet audit")
    def test_audit_accepts_a_missing_remote_only_under_the_skills_only_policy(self):
        policy = {"remotePolicy": "skills only: pluginOnly permits no direct MCP entry on this host"}
        good = {"kilo": {"matchingOfficialSkills": 20, "remoteConfigured": None, **policy}}
        missing = {"kilo": {"matchingOfficialSkills": 0, "remoteConfigured": None, **policy}}
        other = {"warp": {"matchingOfficialSkills": 20, "remoteConfigured": None}}
        for rows, code in ((good, 0), (missing, 1), (other, 1)):
            with contextlib.ExitStack() as stack:
                stack.enter_context(patch("sys.argv", ["installer", "--audit"]))
                stack.enter_context(patch.object(fleet, "audit", return_value=rows))
                stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
                with self.assertRaises(SystemExit) as result:
                    fleet.main()
                self.assertEqual(result.exception.code, code, rows)

    def test_every_active_surface_has_a_rollout_route(self):
        agents = json.loads((ROOT / "registry/agents.json").read_text(encoding="utf-8-sig"))
        supported = set(fleet.NATIVE) | fleet.BRIDGES | set(fleet.ALIASES) | set(fleet.BLOCKED)
        self.assertFalse({a["id"] for a in agents["activeAgents"]} - supported)
        # A blocked disposition must carry a reason and never claim a
        # supported surface.
        self.assertTrue(all(fleet.BLOCKED.values()))
        self.assertTrue(set(fleet.SKILLS_ONLY) <= fleet.BRIDGES)
        self.assertFalse(set(fleet.BLOCKED) & (set(fleet.NATIVE) | fleet.BRIDGES | set(fleet.ALIASES)))

    def test_blocked_host_plan_reports_reason_without_side_effects(self):
        with patch.dict(fleet.BLOCKED, {"pending-host": "discovery-required: no approved route"}), \
                patch("sys.argv", ["installer", "--host", "pending-host"]), patch.object(fleet, "run") as run:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                fleet.main()
            plan = json.loads(output.getvalue())
            self.assertEqual(plan["hosts"], [])
            self.assertIn("discovery-required", plan["blocked"]["pending-host"])
            run.assert_not_called()

    def test_blocked_host_apply_refuses_before_any_runtime_write(self):
        for host in ("pending-host", "other-pending-host"):
            with tempfile.TemporaryDirectory() as temp:
                runtime = Path(temp) / "runtime"
                argv = ["installer", "--host", host, "--apply", "--runtime", str(runtime)]
                with patch.dict(fleet.BLOCKED, {host: "discovery-required: no approved route"}), \
                        patch("sys.argv", argv), patch.object(fleet, "run") as run:
                    with contextlib.redirect_stdout(io.StringIO()) as output:
                        with self.assertRaises(SystemExit) as caught:
                            fleet.main()
                    self.assertEqual(caught.exception.code, 1)
                    run.assert_not_called()
                    self.assertFalse(runtime.exists())
                    self.assertIn("discovery-required", output.getvalue())

    def test_unknown_host_is_still_rejected(self):
        with patch("sys.argv", ["installer", "--host", "ghost"]):
            with self.assertRaises(SystemExit) as caught:
                fleet.main()
            self.assertEqual(caught.exception.code, 2)

    def test_default_selection_excludes_every_inactive_agent(self):
        inactive = set(inactive_hosts())
        self.assertTrue(inactive, "registry/agents.json lists no inactive agents, so this check would be vacuous")
        with patch("sys.argv", ["installer"]), patch.object(fleet, "run") as run:
            with contextlib.redirect_stdout(io.StringIO()) as output, contextlib.redirect_stderr(io.StringIO()) as errors:
                fleet.main()
        plan = json.loads(output.getvalue())
        selected = set(plan["hosts"]) | set(plan["blocked"])
        self.assertFalse(selected & inactive, f"inactive agents in the default selection: {sorted(selected & inactive)}")
        self.assertIn("claude", plan["hosts"])
        known_default = (set(fleet.NATIVE) | fleet.BRIDGES | set(fleet.BLOCKED)) & inactive
        self.assertTrue(known_default, "no inactive host overlaps the default target list, so the skip was not exercised")
        for host in sorted(known_default):
            self.assertIn(f"skipped {host}: listed under inactiveAgents", errors.getvalue())
        run.assert_not_called()

    def test_naming_an_inactive_agent_refuses_in_plan_and_apply(self):
        for host in sorted(inactive_hosts()):
            with self.subTest(host=host), tempfile.TemporaryDirectory() as temp:
                runtime = Path(temp) / "runtime"
                for mode in ([], ["--apply"]):
                    argv = ["installer", "--host", host, "--runtime", str(runtime), *mode]
                    with patch("sys.argv", argv), patch.object(fleet, "run") as run:
                        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as errors:
                            with self.assertRaises(SystemExit) as caught:
                                fleet.main()
                    self.assertEqual(caught.exception.code, 2, mode)
                    self.assertIn("inactive in registry/agents.json", errors.getvalue(), mode)
                    run.assert_not_called()
                    self.assertFalse(runtime.exists())

    def good_row(self):
        return {"matchingOfficialSkills": 20, "remoteConfigured": True}

    def test_audit_reads_back_only_the_selected_hosts_never_inactive_or_blocked_ones(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(fleet.os.environ, {"APPDATA": temp}):
            home, upstream = Path(temp) / "home", Path(temp) / "upstream"
            (upstream / "skills/clerk").mkdir(parents=True)
            (upstream / "skills/clerk/SKILL.md").write_text("---\nname: clerk\n---\n", encoding="utf-8")
            wanted = {"claude", "cline", "warp", "mimo-code", "zcode", "qwen"}
            rows = fleet.audit(upstream, home, wanted)
            self.assertEqual(set(rows), {"claude", "cline", "warp", "mimo-code"})  # blocked hosts are never audited rows
            rows = fleet.audit(upstream, home, wanted - inactive_hosts())
            self.assertEqual(set(rows), {"claude", "cline"})

    def test_an_empty_audit_does_not_pass_and_blocked_hosts_are_not_rows_that_can_fail_it(self):
        self.assertFalse(fleet.audit_ok({}))
        self.assertTrue(fleet.audit_ok({"claude": self.good_row()}))
        self.assertFalse(fleet.audit_ok({"claude": {**self.good_row(), "matchingOfficialSkills": 0}}))

    @unittest.skipUnless(fleet.os.name == "nt", "Windows fleet audit")
    def test_audit_passes_with_blocked_hosts_reported_separately_and_skips_inactive_ones(self):
        rows = {"claude": self.good_row()}
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch("sys.argv", ["installer", "--audit"]))
            audit = stack.enter_context(patch.object(fleet, "audit", return_value=rows))
            output = stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            with patch.dict(fleet.BLOCKED, {"pending-host": "discovery-required: no approved route"}), self.assertRaises(SystemExit) as result:
                fleet.main()
        self.assertEqual(result.exception.code, 0)
        self.assertFalse(set(audit.call_args.args[2]) & (inactive_hosts() | set(fleet.BLOCKED)))
        report = json.loads(output.getvalue())
        self.assertEqual(set(report["hosts"]), {"claude"})
        self.assertIn("pending-host", report["blocked"])

    def test_a_blocked_host_that_the_registry_retired_says_so(self):
        for host in set(fleet.BLOCKED) & inactive_hosts():
            self.assertIn("retired", fleet.BLOCKED[host], host)
        self.assertNotIn("became a dispatch host", fleet.BLOCKED["qwen"])

    def test_every_recorded_update_command_names_a_host_the_installer_will_accept(self):
        registry = json.loads((ROOT / "registry/native-connectors.json").read_text(encoding="utf-8-sig"))
        clerk = next(e for e in registry["thirdPartyExtensions"]["extensions"] if e["extensionId"] == "clerk-skills")
        accepted = (set(fleet.NATIVE) | fleet.BRIDGES | set(fleet.ALIASES)) - inactive_hosts()
        for entry in clerk["hostChannels"]:
            words = entry["updateCommand"].split()
            self.assertIn("Install-ClerkFleet.py", entry["updateCommand"])
            if "--host" in words:
                self.assertIn(words[words.index("--host") + 1], accepted, entry["hostId"])


if __name__ == "__main__":
    unittest.main()
