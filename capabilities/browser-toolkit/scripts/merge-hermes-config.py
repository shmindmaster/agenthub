"""Merge the browser toolkit into Hermes config without exposing credentials."""

from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path

from ruamel.yaml import YAML


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    path = Path(args.config).expanduser().resolve()
    yaml = YAML()
    yaml.preserve_quotes = True

    with path.open("r", encoding="utf-8") as stream:
        config = yaml.load(stream) or {}

    model = config.setdefault("model", {})
    model["default"] = "qwen3.7-max"
    model["provider"] = "custom:qwencloud"
    for legacy_key in ("api_key", "base_url", "api_mode"):
        model.pop(legacy_key, None)

    raw_providers = config.get("custom_providers") or []
    if isinstance(raw_providers, dict):
        providers = [value for value in raw_providers.values() if isinstance(value, dict)]
    elif isinstance(raw_providers, list):
        providers = [value for value in raw_providers if isinstance(value, dict)]
    else:
        raise TypeError("custom_providers must be a list or mapping")
    providers = [provider for provider in providers if provider.get("name") != "qwencloud"]
    providers.append(
        {
            "name": "qwencloud",
            "base_url": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic",
            "key_env": "QWEN_API_KEY",
            "api_mode": "anthropic_messages",
        }
    )
    config["custom_providers"] = providers

    mcp_servers = config.setdefault("mcp_servers", {})
    chrome_args = [
        "-y",
        "chrome-devtools-mcp@latest",
    ]
    if args.port > 0:
        chrome_args.append(f"--browser-url=http://127.0.0.1:{args.port}")
    mcp_servers["chrome-devtools"] = {
        "command": "npx",
        "args": chrome_args,
        "enabled": True,
    }

    handle, temporary_name = tempfile.mkstemp(
        prefix=f"{path.name}.",
        suffix=".tmp",
        dir=path.parent,
        text=True,
    )
    os.close(handle)
    temporary = Path(temporary_name)
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as stream:
            yaml.dump(config, stream)
        os.replace(temporary, path)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
