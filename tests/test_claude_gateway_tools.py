"""Synthetic gateway regressions; no credentials or provider calls."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'scripts' / 'claude_gateway_tools.py'


class ToolLoadingTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SOURCE.is_file(), 'gateway deferral compatibility is missing')
        spec = importlib.util.spec_from_file_location('gateway_tools', SOURCE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.prepare = module.prepare_tools
        self.tool = lambda name, deferred=False: {
            'name': name, 'description': 'synthetic schema ' * 100,
            'input_schema': {'type': 'object', 'properties': {}},
            'defer_loading': deferred,
        }
        self.request = {
            'model': 'synthetic-model', 'max_tokens': 32,
            'tools': [self.tool('ToolSearch')] + [self.tool(f'mcp__synthetic__tool{i}', True) for i in range(331)],
            'messages': [{'role': 'user', 'content': 'Find the synthetic issue.'}],
        }

    def test_first_request_omits_deferred_schemas(self):
        original = copy.deepcopy(self.request)
        result = self.prepare(self.request)
        self.assertEqual([x['name'] for x in result['tools']], ['ToolSearch'])
        self.assertLess(len(json.dumps(result['tools'])), len(json.dumps(original['tools'])) // 100)
        self.assertEqual(self.request, original)

    def test_discovered_tool_is_available_and_reference_becomes_text(self):
        self.request['messages'].append({'role': 'user', 'content': [{
            'type': 'tool_result', 'tool_use_id': 'search1', 'content': [
                {'type': 'tool_reference', 'tool_name': 'mcp__synthetic__tool7'}]}]})
        result = self.prepare(self.request)
        self.assertEqual([x['name'] for x in result['tools']], ['ToolSearch', 'mcp__synthetic__tool7'])
        self.assertNotIn('defer_loading', json.dumps(result))
        content = result['messages'][-1]['content'][0]['content'][0]
        self.assertEqual(content['type'], 'text')
        self.assertIn('mcp__synthetic__tool7', content['text'])

    def test_tool_use_in_history_keeps_schema_loaded(self):
        self.request['messages'].append({'role': 'assistant', 'content': [
            {'type': 'tool_use', 'name': 'mcp__synthetic__tool8', 'id': 't8', 'input': {}}]})
        self.assertEqual(self.prepare(self.request)['tools'][-1]['name'], 'mcp__synthetic__tool8')

    def test_eager_catalog_is_blocked_before_provider_call(self):
        for tool in self.request['tools']:
            tool.pop('defer_loading')
        with self.assertRaisesRegex(ValueError, 'tool schema budget'):
            self.prepare(self.request)

    def test_unknown_reference_fails_without_echoing_content(self):
        self.request['messages'].append({'role': 'user', 'content': [
            {'type': 'tool_reference', 'tool_name': 'synthetic-secret-not-for-errors'}]})
        with self.assertRaises(ValueError) as caught:
            self.prepare(self.request)
        self.assertNotIn('synthetic-secret', str(caught.exception))

    def test_unrelated_request_is_preserved(self):
        request = {'model': 'other', 'messages': [{'role': 'user', 'content': 'Hello'}]}
        self.assertEqual(self.prepare(request), request)

    def test_provider_native_tools_fail_closed(self):
        self.request['tools'].append({'name': 'native-search', 'type': 'tool_search_tool_regex_20251119'})
        with self.assertRaisesRegex(ValueError, 'server-side tool'):
            self.prepare(self.request)

    def test_deferral_without_client_search_fails_closed(self):
        self.request['tools'].pop(0)
        with self.assertRaisesRegex(ValueError, 'client ToolSearch'):
            self.prepare(self.request)


if __name__ == '__main__':
    unittest.main()
