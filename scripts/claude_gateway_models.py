"""Render the owned gateway routes without credentials or provider calls."""
import copy
import json
from pathlib import Path

REGISTRY = Path(__file__).resolve().parents[1] / 'registry' / 'claude-gateway-models.json'


def render(config, policy=None):
    policy = policy or json.loads(REGISTRY.read_text(encoding='utf-8'))
    models = {m['alias']: m for m in policy['models']}
    aliases = {name: name for name in models} | policy['compatibilityAliases']
    result = copy.deepcopy(config)
    result['model_list'] = [m for m in result.get('model_list', []) if m['model_name'] not in aliases]
    for alias, target in aliases.items():
        model = models[target]
        result['model_list'].append({
            'model_name': alias,
            'litellm_params': {
                'model': 'custom_openai/' + model['upstream'],
                'api_base': 'https://api.runware.ai/v1',
                'api_key': 'os.environ/RUNWARE_API_KEY',
            },
            'model_info': {
                'supports_function_calling': True,
                'input_cost_per_token': model['inputCost'],
                'output_cost_per_token': model['outputCost'],
                'cache_read_input_token_cost': model['cacheReadCost'],
            },
        })
    callbacks = result.setdefault('litellm_settings', {}).setdefault('callbacks', [])
    if 'claude_gateway_callback.deferred_tools' not in callbacks:
        callbacks.append('claude_gateway_callback.deferred_tools')
    return result
