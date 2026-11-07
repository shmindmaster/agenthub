"""Offline route regressions; synthetic configuration only."""
import importlib.util
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'scripts' / 'claude_gateway_models.py'


class ModelRoutes(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('gateway_models', SOURCE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.render = module.render

    def test_owned_routes_have_no_gpt_upstream(self):
        result = self.render({})
        routes = {m['model_name']: m for m in result['model_list']}
        self.assertEqual(len(routes), 6)
        self.assertEqual(routes['runware-terra']['litellm_params']['model'], 'custom_openai/deepseek:v4.1@flash-1017')
        self.assertEqual(routes['runware-sol']['litellm_params']['model'], 'custom_openai/deepseek:v4@pro')
        for model in routes.values():
            self.assertEqual(model['litellm_params']['api_key'], 'os.environ/RUNWARE_API_KEY')
            self.assertNotIn('cache_creation_input_token_cost', model['model_info'])

    def test_preserves_unrelated_config_and_is_idempotent(self):
        config = {'model_list': [{'model_name': 'unrelated', 'litellm_params': {'model': 'synthetic'}}],
                  'general_settings': {'master_key': 'os.environ/SYNTHETIC'},
                  'litellm_settings': {'callbacks': ['existing']}}
        result = self.render(config)
        self.assertEqual(result['model_list'][0], config['model_list'][0])
        self.assertEqual(result['general_settings'], config['general_settings'])
        self.assertEqual(result['litellm_settings']['callbacks'], ['existing', 'claude_gateway_callback.deferred_tools'])
        self.assertEqual(result, self.render(result))
        self.assertEqual(len(config['model_list']), 1)
