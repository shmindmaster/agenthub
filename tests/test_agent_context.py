import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('optimizer', Path(__file__).parents[1]/'scripts/Optimize-AgentContext.py')
optimizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(optimizer)
inventory_spec = importlib.util.spec_from_file_location('inventory', Path(__file__).parents[1]/'scripts/Measure-AgentContext.py')
inventory = importlib.util.module_from_spec(inventory_spec)
inventory_spec.loader.exec_module(inventory)

class CleanupTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt', 'Windows junction behavior')
    def test_shared_junctions_are_one_library_and_do_not_duplicate_skill_counts(self):
        import _winapi
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shared = self.skill(root, 'fixture')
            agents=[]
            for host in ('claude', 'cline'):
                host_root=root/('.'+host)
                host_root.mkdir()
                _winapi.CreateJunction(str(shared.parent), str(host_root/'skills'))
                agents.append({'id':host, 'nativePaths':{'skillsDir':str(host_root/'skills')}})
            registry=root/'repository/registry'
            registry.mkdir(parents=True)
            (registry/'agents.json').write_text(json.dumps({'activeAgents':agents}))
            (registry/'capabilities.json').write_text(json.dumps({'capabilities':[]}))
            report=inventory.inventory(registry.parent, root)
            self.assertEqual(len(report['roots']), 1)
            self.assertEqual(len(report['roots'][0]['aliases']), 2)
            self.assertEqual(len(report['skills']), 1)
            self.assertEqual(report['duplicateContent'], [])
            links=inventory.storage_metadata(root)['skillLinks']
            observed=[row for row in links if row['linked']]
            self.assertEqual(len(observed), 2)
            self.assertEqual({row['resolved'] for row in observed}, {str(shared.parent.resolve())})

    def test_config_inventory_never_serializes_credentials_or_server_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder = root/'.claude'
            folder.mkdir()
            (folder/'settings.json').write_text(json.dumps({'apiKey':'SECRET_FIXTURE', 'mcpServers':{'fixture':{'url':'PRIVATE_URL_FIXTURE','env':{'TOKEN':'SECRET_FIXTURE'},'disabled':True}}}))
            output = json.dumps(inventory.config_metadata(root))
            self.assertNotIn('SECRET_FIXTURE', output)
            self.assertNotIn('PRIVATE_URL_FIXTURE', output)
            self.assertIn('fixture', output)
            self.assertIn('explicitlyDisabled', output)

    def skill(self, root, path, text='fixture'):
        folder = root/'.agents/skills'/path
        folder.mkdir(parents=True)
        (folder/'SKILL.md').write_text(text)
        return folder

    def test_audit_apply_recovery_idempotence_and_unknown_preservation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = self.skill(root, 'synced/a/pdf')
            self.skill(root, 'synced/b/pdf')
            self.skill(root, 'synced/a/morning')
            unknown = self.skill(root, 'synced/a/unique-private-skill')
            optimizer.optimize(root)
            self.assertTrue(first.exists())
            result = optimizer.optimize(root, True)
            self.assertTrue(unknown.exists())
            self.assertTrue((root/'.agents/skills/pdf/SKILL.md').exists())
            self.assertTrue((Path(result['recovery'])/'a/morning/SKILL.md').exists())
            self.assertEqual(optimizer.optimize(root, True)['actions'], [])

    def test_conflicting_user_copy_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.skill(root, 'synced/a/pdf', 'import')
            target = self.skill(root, 'pdf', 'user work')
            result = optimizer.optimize(root, True)
            self.assertEqual(result['actions'][0]['action'], 'preserve-conflicting-copy')
            self.assertTrue(source.exists())
            self.assertEqual((target/'SKILL.md').read_text(), 'user work')

if __name__ == '__main__':
    unittest.main()
