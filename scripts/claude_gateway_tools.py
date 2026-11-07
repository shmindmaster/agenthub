"""Client-side tool discovery compatibility for Anthropic-to-Chat gateways.

This handles client tools such as Claude Code's ToolSearch. It does not emulate
Anthropic server-side search. Never import credentials or log request contents.
"""
import copy
import json

MAX_TOOL_SCHEMA_BYTES = 160_000


def prepare_tools(request, max_schema_bytes=MAX_TOOL_SCHEMA_BYTES):
    tools = request.get('tools')
    if not tools:
        return request
    by_name = {}
    for tool in tools:
        if tool.get('type', 'custom') != 'custom':
            raise ValueError('Unsupported server-side tool on the Chat gateway.')
        name = tool.get('name')
        if not isinstance(name, str) or not name or name in by_name:
            raise ValueError('Invalid or duplicate tool catalog entry.')
        by_name[name] = tool

    if any(t.get('defer_loading') for t in tools) and not any(
        t['name'] == 'ToolSearch' and not t.get('defer_loading') for t in tools
    ):
        raise ValueError('Deferred tools require a loaded client ToolSearch tool.')

    selected = set()

    def content_blocks(content):
        if not isinstance(content, list):
            return
        for block in content:
            if not isinstance(block, dict):
                continue
            yield block
            if block.get('type') == 'tool_result':
                yield from content_blocks(block.get('content'))

    for message in request.get('messages', []):
        for block in content_blocks(message.get('content')):
            if block.get('type') == 'tool_reference':
                name = block.get('tool_name')
                if name not in by_name:
                    raise ValueError('Discovered tool is absent; reconnect the selected tool server.')
                selected.add(name)
            elif block.get('type') == 'tool_use' and block.get('name') in by_name:
                selected.add(block['name'])

    result = dict(request)
    result['tools'] = [
        {key: copy.deepcopy(value) for key, value in tool.items() if key != 'defer_loading'}
        for tool in tools
        if not tool.get('defer_loading', False) or tool['name'] in selected
    ]
    if len(json.dumps(result['tools'], ensure_ascii=False).encode('utf-8')) > max_schema_bytes:
        raise ValueError('Local tool schema budget exceeded; enable client tool search or reduce active integrations.')
    result['messages'] = copy.deepcopy(request.get('messages', []))
    for message in result['messages']:
        for block in content_blocks(message.get('content')):
            if block.get('type') == 'tool_reference':
                name = block['tool_name']
                block.clear()
                block.update(type='text', text=f'Tool available in the tool catalog: {name}')
    return result
