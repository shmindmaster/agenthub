import unittest
import tempfile
import pathlib
from content_host_controls import blocked, codex_block, ELEVENLABS_APP, run


class HostControls(unittest.TestCase):
    def test_absent_config_audits_without_creation_and_apply_creates_block(self):
        with tempfile.TemporaryDirectory() as folder:
            config = pathlib.Path(folder) / "new-home/config.toml"
            self.assertFalse(run(config)["configured_block"])
            self.assertFalse(config.parent.exists())
            self.assertTrue(run(config, apply=True)["configured_block"])
            self.assertTrue(blocked(config.read_text()))

    def test_missing_block_is_detected_and_add_is_idempotent(self):
        original = '[apps._default]\ndefault_tools_approval_mode="auto"\n[plugins.sample]\nenabled=true\n'
        self.assertFalse(blocked(original))
        result = codex_block(original)
        self.assertTrue(blocked(result))
        self.assertEqual(codex_block(result), result)
        self.assertIn('[plugins.sample]\nenabled=true', result)

    def test_existing_app_table_keeps_other_settings_and_later_tables(self):
        original = f'[apps.{ELEVENLABS_APP}]\nenabled = true\ndefault_tools_enabled=true\n[features]\nx=true\n'
        result = codex_block(original)
        self.assertTrue(blocked(result))
        self.assertIn('default_tools_enabled=true', result)
        self.assertIn('[features]\nx=true', result)

    def test_invalid_input_and_equivalent_quoted_table_fail_closed(self):
        for original in ('invalid {', f'[apps."{ELEVENLABS_APP}"]\nenabled=true\n'):
            with self.assertRaises((ValueError, RuntimeError)):
                codex_block(original)


if __name__ == '__main__':
    unittest.main()
