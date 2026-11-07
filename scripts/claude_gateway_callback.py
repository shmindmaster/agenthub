"""Opt-in LiteLLM pre-call hook for the local Runware Chat gateway."""
from fastapi import HTTPException
from litellm.integrations.custom_logger import CustomLogger
from claude_gateway_tools import prepare_tools


class DeferredTools(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        model = data.get('model', '').removeprefix('claude-compatible/')
        if call_type != 'anthropic_messages' or model not in {
            'runware-terra', 'runware-sol', 'runware-deepseek', 'runware-v4.1-flash-1017',
        }:
            return data
        try:
            return prepare_tools(data)
        except ValueError as exc:
            # 402 is terminal to the client. A 400 could trigger eager fallback,
            # precisely the expensive failure this hook must refuse locally.
            raise HTTPException(status_code=402, detail=str(exc)) from None


deferred_tools = DeferredTools()
