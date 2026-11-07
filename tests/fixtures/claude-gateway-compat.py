"""Run in the deployed LiteLLM image with --network none; no keys required."""
import asyncio
import copy
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from fastapi import HTTPException
from litellm.llms.anthropic.pass_through.adapters.transformation import LiteLLMAnthropicMessagesAdapter
from claude_gateway_callback import deferred_tools

adapter = LiteLLMAnthropicMessagesAdapter()
request = {
    'model': 'claude-compatible/runware-terra', 'max_tokens': 32,
    'messages': [{'role': 'user', 'content': 'Find the synthetic record.'}],
    'tools': [{'name': 'ToolSearch', 'description': 'Discover tools.',
               'input_schema': {'type': 'object', 'properties': {'query': {'type': 'string'}}}}] + [
        {'name': f'mcp__synthetic__tool{i}', 'defer_loading': True,
         'description': 'synthetic documentation ' * 100,
         'input_schema': {'type': 'object', 'properties': {'id': {'type': 'string'}}}}
        for i in range(331)],
}


async def main():
    initial = await deferred_tools.async_pre_call_hook(None, None, request, 'anthropic_messages')
    translated, _ = adapter.translate_anthropic_to_openai(initial)
    assert [t['function']['name'] for t in translated['tools']] == ['ToolSearch']
    assert len(json.dumps(translated['tools'])) < 1000
    # A complete search tool-use/result round trip, followed by a loaded tool call.
    discovered = copy.deepcopy(request)
    discovered['messages'] += [
        {'role': 'assistant', 'content': [{'type': 'tool_use', 'id': 's1', 'name': 'ToolSearch',
                                          'input': {'query': 'synthetic tool7'}}]},
        {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': 's1', 'content': [
            {'type': 'tool_reference', 'tool_name': 'mcp__synthetic__tool7'}]}]},
        {'role': 'assistant', 'content': [{'type': 'tool_use', 'id': 't1',
                                          'name': 'mcp__synthetic__tool7', 'input': {'id': 'synthetic'}}]},
        {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': 't1', 'content': 'Found.'}]},
    ]
    loaded = await deferred_tools.async_pre_call_hook(None, None, discovered, 'anthropic_messages')
    translated, _ = adapter.translate_anthropic_to_openai(loaded)
    assert len(translated['tools']) == 2
    assert translated['tools'][1]['function']['name'] == 'mcp__synthetic__tool7'
    assert 'defer_loading' not in json.dumps(translated)
    assert 'tool_reference' not in json.dumps(translated)
    assert any(m['role'] == 'tool' and 'tool7' in str(m['content']) for m in translated['messages'])
    # No fallback should be able to forward the eager catalog upstream.
    eager = copy.deepcopy(request)
    for tool in eager['tools']:
        tool.pop('defer_loading', None)
    try:
        await deferred_tools.async_pre_call_hook(None, None, eager, 'anthropic_messages')
        raise AssertionError('Eager catalog was not blocked')
    except HTTPException as exc:
        assert exc.status_code == 402
    other = dict(request, model='unrelated-provider')
    assert await deferred_tools.async_pre_call_hook(None, None, other, 'anthropic_messages') is other
    assert await deferred_tools.async_pre_call_hook(None, None, request, 'completion') is request
    print('PASS: pinned gateway translation, search/discovery/use round trip, local refusal, route isolation (offline).')


asyncio.run(main())
