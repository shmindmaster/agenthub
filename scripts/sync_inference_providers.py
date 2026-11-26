"""Additive-only AgentHub Daytona inference provider rollout and drift detector.

Reads registry/inference-providers.json and translates the canonical
agenthub-daytona provider + model aliases into each supported coding agent's
native format without changing existing defaults, subscriptions, or agent
assignments. Never prints secret values.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MANAGED_BEGIN = "# BEGIN agenthub-daytona managed block"
MANAGED_END = "# END agenthub-daytona managed block"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def utc_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def resolve_inference_key(user_home: Path) -> str:
    env_key = os.environ.get("AGENTHUB_INFERENCE_KEY", "").strip()
    if env_key:
        return env_key
    secret_file = user_home / ".config" / "opencode" / "daytona" / "secrets" / "inference.key"
    if secret_file.is_file():
        val = secret_file.read_text(encoding="utf-8").strip()
        if val:
            return val
    return ""


def set_owner_only_acl(path: Path) -> None:
    if os.name == "nt":
        user = os.environ.get("USERNAME", "")
        if user:
            subprocess.run(
                ["icacls", str(path), "/inheritance:r", "/grant:r", f"{user}:(R,W)"],
                check=False,
                capture_output=True,
                text=True,
            )
    else:
        os.chmod(path, 0o600)


def strip_jsonc_comments(text: str) -> str:
    # Remove // line comments outside string literals.
    out = []
    in_str = False
    esc = False
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if in_str:
            out.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
        else:
            if ch == '"':
                in_str = True
                out.append(ch)
                i += 1
            elif ch == "/" and i + 1 < n and text[i + 1] == "/":
                while i < n and text[i] != "\n":
                    i += 1
            else:
                out.append(ch)
                i += 1
    return "".join(out)


def upsert_toml_managed_block(existing_text: str, block_body: str) -> str:
    block = f"{MANAGED_BEGIN}\n{block_body.strip()}\n{MANAGED_END}\n"
    pattern = re.compile(
        re.escape(MANAGED_BEGIN) + r".*?" + re.escape(MANAGED_END) + r"\r?\n?",
        re.DOTALL,
    )
    if pattern.search(existing_text):
        return pattern.sub(block, existing_text, count=1)
    sep = "" if existing_text.endswith("\n") or not existing_text else "\n"
    return existing_text + sep + "\n" + block


def extract_toml_managed_block(existing_text: str) -> str:
    pattern = re.compile(
        re.escape(MANAGED_BEGIN) + r"\r?\n(.*?)\r?\n" + re.escape(MANAGED_END),
        re.DOTALL,
    )
    m = pattern.search(existing_text)
    return m.group(1).strip() if m else ""


def model_by_id(spec: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {m["id"]: m for m in spec["models"]}


def build_opencode_provider(spec: dict[str, Any], user_home: Path | None = None) -> dict[str, Any]:
    prov = spec["provider"]
    secret_file = (
        user_home / ".config" / "opencode" / "daytona" / "secrets" / "inference.key"
        if user_home is not None
        else None
    )
    api_key_ref = (
        f"{{file:{secret_file.as_posix()}}}"
        if secret_file is not None and secret_file.is_file()
        else f"{{env:{prov['credentialEnv']}}}"
    )
    models: dict[str, Any] = {}
    for m in spec["models"]:
        default_effort = m["reasoning"]["default"]
        models[m["id"]] = {
            "modelID": m["id"],
            "name": m["displayName"],
            "family": m["family"],
            "package": "@opencode/ai/providers/openai-compatible",
            "compatibility": {"reasoningField": "reasoning"},
            "capabilities": {
                "tools": m["toolCalling"],
                "temperature": True,
                "input": m["modalities"]["input"],
                "output": m["modalities"]["output"],
                "reasoning": {
                    "supported": True,
                    "toggle": True,
                    "effort": m["reasoning"]["supportedEfforts"],
                },
            },
            "limit": {
                "context": m["contextWindow"],
                "output": m["maxOutputTokens"],
            },
            "disabled": bool((m.get("serving") or {}).get("deferred", False)),
            "body": {"reasoning_effort": default_effort},
            "variants": [
                {"id": "fast", "body": {"chat_template_kwargs": {"enable_thinking": False}}},
                {"id": "everyday", "body": {"reasoning_effort": default_effort}},
                {"id": "deep", "body": {"reasoning_effort": "xhigh"}},
            ],
        }
    return {
        "name": prov["displayName"],
        "package": "@opencode/ai/providers/openai-compatible",
        "env": [prov["credentialEnv"]],
        "settings": {
            "apiKey": api_key_ref,
            "baseURL": prov["baseUrl"],
        },
        "models": models,
    }


def sync_opencode(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, _key: str) -> dict[str, Any]:
    path = user_home / ".config" / "opencode" / "opencode.json"
    if not path.is_file():
        return {"host": "opencode", "status": "absent", "path": str(path)}
    data = load_json(path)
    providers = data.setdefault("providers", {})
    legacy_ids = ("daytona-fast", "daytona-flagship", "daytona-specialist", "daytona-turbo-heretic-q6")
    has_legacy = any(k in providers for k in legacy_ids)
    want = build_opencode_provider(spec, user_home=user_home)
    have = providers.get(spec["provider"]["id"])
    if have == want and not has_legacy:
        return {"host": "opencode", "status": "current", "path": str(path)}
    state = "missing" if have is None else "drift"
    if not apply:
        return {"host": "opencode", "status": state, "path": str(path)}
    orig_model = data.get("model")
    orig_small = data.get("small_model")
    orig_agents = json.dumps(data.get("agents"), sort_keys=True)
    for legacy_id in legacy_ids:
        providers.pop(legacy_id, None)
    providers[spec["provider"]["id"]] = want
    if data.get("model") != orig_model or data.get("small_model") != orig_small or json.dumps(data.get("agents"), sort_keys=True) != orig_agents:
        raise RuntimeError("opencode invariant violation: defaults or agents changed")
    write_json(path, data)
    check = load_json(path)
    assert check.get("model") == orig_model and check.get("small_model") == orig_small
    return {"host": "opencode", "status": "applied", "previous": state, "path": str(path)}


def build_codex_block(spec: dict[str, Any]) -> str:
    prov = spec["provider"]
    lines = [
        f'[model_providers.{prov["id"]}]',
        f'name = "{prov["displayName"]}"',
        f'base_url = "{prov["baseUrl"]}"',
        f'env_key = "{prov["credentialEnv"]}"',
        'wire_api = "responses"',
        "requires_openai_auth = false",
        "supports_websockets = false",
    ]
    return "\n".join(lines).strip()


def build_codex_profile_files(spec: dict[str, Any]) -> dict[str, str]:
    prov = spec["provider"]
    out: dict[str, str] = {}
    for m in spec["models"]:
        short = m["id"].replace("agent-", "daytona-")
        out[f"{short}.config.toml"] = (
            f'model_provider = "{prov["id"]}"\n'
            f'model = "{m["id"]}"\n'
            f'model_reasoning_effort = "{m["reasoning"]["default"]}"\n'
            '\n[features]\n'
            'apps = false\n'
        )
    return out


def sync_codex(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, _key: str) -> dict[str, Any]:
    codex_dir = user_home / ".codex"
    path = codex_dir / "config.toml"
    if not path.is_file():
        return {"host": "codex", "status": "absent", "path": str(path)}
    orig_text = path.read_text(encoding="utf-8")
    orig_parsed = tomllib.loads(orig_text)
    want_block = build_codex_block(spec)
    have_block = extract_toml_managed_block(orig_text)
    want_profiles = build_codex_profile_files(spec)

    profile_drifts = []
    for fname, body in want_profiles.items():
        pfile = codex_dir / fname
        if not pfile.is_file() or pfile.read_text(encoding="utf-8") != body:
            profile_drifts.append(fname)

    if have_block == want_block and not profile_drifts:
        return {"host": "codex", "status": "current", "path": str(path)}
    state = "missing" if not have_block else "drift"
    if not apply:
        return {"host": "codex", "status": state, "path": str(path), "profileDiffs": profile_drifts}
    new_text = upsert_toml_managed_block(orig_text, want_block)
    new_parsed = tomllib.loads(new_text)
    for k in ("forced_login_method", "model", "review_model", "model_reasoning_effort"):
        if new_parsed.get(k) != orig_parsed.get(k):
            raise RuntimeError(f"codex invariant violation: root key {k} changed")
    path.write_text(new_text, encoding="utf-8")
    tomllib.loads(path.read_text(encoding="utf-8"))
    for fname, body in want_profiles.items():
        pfile = codex_dir / fname
        pfile.write_text(body, encoding="utf-8")
        tomllib.loads(pfile.read_text(encoding="utf-8"))
    return {"host": "codex", "status": "applied", "previous": state, "path": str(path)}


def build_factory_entries(spec: dict[str, Any], repo: Path) -> list[dict[str, Any]]:
    canonical_path = repo / "packages" / "coding-agent-dispatch" / "factory" / "custom-models.json"
    if canonical_path.is_file():
        data = load_json(canonical_path)
        entries = [m for m in data.get("customModels", []) if str(m.get("model", "")).startswith("daytona-")]
        if entries:
            return entries
    prov = spec["provider"]
    out = []
    for m in spec["models"]:
        short = m["id"].replace("agent-", "daytona-")
        out.append(
            {
                "model": short,
                "displayName": f"{m['displayName']} (AgentHub Gateway)",
                "baseUrl": prov["baseUrl"],
                "apiKey": f"${{{prov['credentialEnv']}}}",
                "provider": "generic-chat-completion-api",
                "maxOutputTokens": m["maxOutputTokens"],
                "extraArgs": {"model": m["id"]},
            }
        )
    return out


def sync_factory(spec: dict[str, Any], user_home: Path, _roaming: Path, repo: Path, apply: bool, _key: str) -> dict[str, Any]:
    path = user_home / ".factory" / "settings.json"
    if not path.is_file():
        return {"host": "factory", "status": "absent", "path": str(path)}
    data = load_json(path)
    want_entries = build_factory_entries(spec, repo)
    want_by_id = {e["model"]: e for e in want_entries}
    existing = list(data.get("customModels") or [])
    existing_by_id = {e.get("model"): e for e in existing if isinstance(e, dict)}
    diffs = [mid for mid, entry in want_by_id.items() if existing_by_id.get(mid) != entry]
    if not diffs:
        return {"host": "factory", "status": "current", "path": str(path)}
    state = "missing" if all(mid not in existing_by_id for mid in want_by_id) else "drift"
    if not apply:
        return {"host": "factory", "status": state, "path": str(path), "diffModels": diffs}
    orig_model = data.get("model")
    merged = [e for e in existing if not (isinstance(e, dict) and e.get("model") in want_by_id)]
    merged.extend(want_entries)
    data["customModels"] = merged
    if data.get("model") != orig_model:
        raise RuntimeError("factory invariant violation: default model changed")
    write_json(path, data)
    load_json(path)
    return {"host": "factory", "status": "applied", "previous": state, "path": str(path)}


def build_grok_block(spec: dict[str, Any]) -> str:
    prov = spec["provider"]
    sections = []
    for m in spec["models"]:
        key = f"{prov['id']}-{m['id'].replace('agent-', '')}"
        vision = "true" if "image" in m["modalities"]["input"] else "false"
        default_eff = m["reasoning"]["default"]
        eff_items = []
        for eff, lbl in (("low", "Low"), ("medium", "Medium"), ("xhigh", "Extra high")):
            dflt = ", default = true" if eff == default_eff else ""
            eff_items.append(f'  {{ id = "{eff}", value = "{eff}", label = "{lbl}"{dflt} }},')
        sections.append(
            "\n".join(
                [
                    f"[model.{key}]",
                    f'model = "{m["id"]}"',
                    f'name = "{m["displayName"]}"',
                    f'description = "Permanent AgentHub Daytona gateway ({prov["baseUrl"]})"',
                    f'base_url = "{prov["baseUrl"]}"',
                    f'env_key = "{prov["credentialEnv"]}"',
                    'api_backend = "chat_completions"',
                    f'context_window = {m["contextWindow"]}',
                    f'max_completion_tokens = {m["maxOutputTokens"]}',
                    f"vision = {vision}",
                    "supports_backend_search = false",
                    f'reasoning_effort = "{default_eff}"',
                    "reasoning_efforts = [",
                    *eff_items,
                    "]",
                ]
            )
        )
    return "\n\n".join(sections)


LEGACY_GROK_SECTIONS = {
    "model.daytona-turbo-heretic-q6",
    "model.daytona-specialist",
    "model.daytona-fast",
    "model.daytona-flagship",
}
LEGACY_VSCODE_GROUP_NAMES = {"Daytona H200"}
LEGACY_ZCODE_PROVIDER_IDS = {
    "daytona-turbo-heretic-q6",
    "daytona-specialist",
    "daytona-fast",
    "daytona-flagship",
}


def strip_legacy_toml_sections(text: str, section_headers: set[str]) -> tuple[str, list[str]]:
    removed: list[str] = []
    out_lines: list[str] = []
    skipping = False
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("[") and not stripped.startswith("[["):
            header = stripped[1:].split("]", 1)[0].strip()
            if header in section_headers:
                skipping = True
                removed.append(header)
                continue
            skipping = False
        elif stripped.startswith("[[") or stripped.startswith(MANAGED_BEGIN):
            skipping = False
        if not skipping:
            out_lines.append(line)
    cleaned = re.sub(r"\n{3,}", "\n\n", "".join(out_lines))
    return cleaned, removed


def sync_grok(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, _key: str) -> dict[str, Any]:
    path = user_home / ".grok" / "config.toml"
    if not path.is_file():
        return {"host": "grok", "status": "absent", "path": str(path)}
    orig_text = path.read_text(encoding="utf-8")
    orig_parsed = tomllib.loads(orig_text)
    want_block = build_grok_block(spec)
    have_block = extract_toml_managed_block(orig_text)
    cleaned_text, legacy_removed = strip_legacy_toml_sections(orig_text, LEGACY_GROK_SECTIONS)
    if have_block == want_block and not legacy_removed:
        return {"host": "grok", "status": "current", "path": str(path)}
    state = "missing" if not have_block else "drift"
    if not apply:
        return {"host": "grok", "status": state, "path": str(path), "legacySections": legacy_removed}
    new_text = upsert_toml_managed_block(cleaned_text, want_block)
    new_parsed = tomllib.loads(new_text)
    if new_parsed.get("models") != orig_parsed.get("models"):
        raise RuntimeError("grok invariant violation: [models] changed")
    path.write_text(new_text, encoding="utf-8")
    tomllib.loads(path.read_text(encoding="utf-8"))
    return {"host": "grok", "status": "applied", "previous": state, "path": str(path), "removedLegacy": legacy_removed}


def sync_copilot(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, key: str) -> dict[str, Any]:
    copilot_dir = user_home / ".copilot"
    if not copilot_dir.is_dir():
        return {"host": "copilot", "status": "absent", "path": str(copilot_dir / "providers.json")}
    path = copilot_dir / "providers.json"
    prov = spec["provider"]
    want_provider = {
        "name": prov["id"],
        "type": "openai",
        "baseUrl": prov["baseUrl"],
        "apiKey": key,
    }
    want_models = [
        {
            "id": m["id"],
            "provider": prov["id"],
            "maxPromptTokens": m["maxInputTokens"],
            "maxOutputTokens": m["maxOutputTokens"],
        }
        for m in spec["models"]
    ]
    data = load_json(path) if path.is_file() else {"providers": [], "models": []}
    cur_provs = list(data.get("providers") or [])
    cur_models = list(data.get("models") or [])
    have_prov = next((p for p in cur_provs if isinstance(p, dict) and p.get("name") == prov["id"]), None)
    have_models = [m for m in cur_models if isinstance(m, dict) and m.get("provider") == prov["id"]]

    prov_ok = (
        have_prov is not None
        and have_prov.get("type") == "openai"
        and have_prov.get("baseUrl") == prov["baseUrl"]
        and (not key or have_prov.get("apiKey") == key)
    )
    if prov_ok and have_models == want_models:
        return {"host": "copilot", "status": "current", "path": str(path)}
    state = "missing" if have_prov is None else "drift"
    if not apply:
        return {"host": "copilot", "status": state, "path": str(path)}
    if not key:
        raise RuntimeError("AGENTHUB_INFERENCE_KEY is required to write copilot providers.json")
    new_provs = [p for p in cur_provs if not (isinstance(p, dict) and p.get("name") == prov["id"])]
    new_provs.append(want_provider)
    new_models = [m for m in cur_models if not (isinstance(m, dict) and m.get("provider") == prov["id"])]
    new_models.extend(want_models)
    data["providers"] = new_provs
    data["models"] = new_models
    write_json(path, data)
    set_owner_only_acl(path)
    load_json(path)
    return {"host": "copilot", "status": "applied", "previous": state, "path": str(path)}


def build_vscode_group(spec: dict[str, Any]) -> dict[str, Any]:
    prov = spec["provider"]
    models = []
    for m in spec["models"]:
        models.append(
            {
                "id": m["id"],
                "name": m["displayName"],
                "url": prov["baseUrl"].rstrip("/") + "/chat/completions",
                "toolCalling": m["toolCalling"],
                "vision": "image" in m["modalities"]["input"],
                "thinking": True,
                "streaming": m["streaming"],
                "maxInputTokens": m["maxInputTokens"],
                "maxOutputTokens": m["maxOutputTokens"],
                "supportsReasoningEffort": m["reasoning"]["supportedEfforts"],
                "reasoningEffortFormat": "chat-completions",
            }
        )
    return {
        "name": prov["displayName"],
        "vendor": "customendpoint",
        "apiKey": f"${{input:{prov['credentialEnv']}}}",
        "apiType": "chat-completions",
        "models": models,
    }


def sync_vscode(spec: dict[str, Any], _user_home: Path, roaming: Path, _repo: Path, apply: bool, _key: str) -> dict[str, Any]:
    path = roaming / "Code - Insiders" / "User" / "chatLanguageModels.json"
    if not path.is_file():
        return {"host": "vscode-insiders", "status": "absent", "path": str(path)}
    groups = load_json(path)
    want = build_vscode_group(spec)
    have = next((g for g in groups if isinstance(g, dict) and g.get("name") == want["name"]), None)
    has_legacy = any(isinstance(g, dict) and g.get("name") in LEGACY_VSCODE_GROUP_NAMES for g in groups)
    if have == want and not has_legacy:
        return {"host": "vscode-insiders", "status": "current", "path": str(path)}
    state = "missing" if have is None else "drift"
    if not apply:
        return {"host": "vscode-insiders", "status": state, "path": str(path), "hasLegacy": has_legacy}
    drop_names = {want["name"], *LEGACY_VSCODE_GROUP_NAMES}
    new_groups = [g for g in groups if not (isinstance(g, dict) and g.get("name") in drop_names)]
    new_groups.append(want)
    write_json(path, new_groups)
    load_json(path)
    return {"host": "vscode-insiders", "status": "applied", "previous": state, "path": str(path)}


def build_kilo_provider(spec: dict[str, Any]) -> dict[str, Any]:
    prov = spec["provider"]
    models = {}
    for m in spec["models"]:
        models[m["id"]] = {
            "name": m["displayName"],
            "tool_call": m["toolCalling"],
            "reasoning": True,
            "limit": {
                "context": m["contextWindow"],
                "output": m["maxOutputTokens"],
            },
            "modalities": m["modalities"],
        }
    return {
        "npm": "@ai-sdk/openai-compatible",
        "name": prov["displayName"],
        "options": {
            "apiKey": f"{{env:{prov['credentialEnv']}}}",
            "baseURL": prov["baseUrl"],
        },
        "models": models,
    }


def sync_kilo(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, _key: str) -> dict[str, Any]:
    kilo_dir = user_home / ".config" / "kilo"
    path = next((kilo_dir / name for name in ("kilo.jsonc", "kilo.json", "config.json") if (kilo_dir / name).is_file()), None)
    if path is None:
        return {"host": "kilo", "status": "absent", "path": str(kilo_dir / "kilo.jsonc")}
    data = json.loads(strip_jsonc_comments(path.read_text(encoding="utf-8")))
    providers = data.setdefault("provider", {})
    want = build_kilo_provider(spec)
    have = providers.get(spec["provider"]["id"])
    if have == want:
        return {"host": "kilo", "status": "current", "path": str(path)}
    state = "missing" if have is None else "drift"
    if not apply:
        return {"host": "kilo", "status": state, "path": str(path)}
    orig_model = data.get("model")
    providers[spec["provider"]["id"]] = want
    if data.get("model") != orig_model:
        raise RuntimeError("kilo invariant violation: default model changed")
    write_json(path, data)
    load_json(path)
    return {"host": "kilo", "status": "applied", "previous": state, "path": str(path)}


def sync_cline(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, key: str) -> dict[str, Any]:
    path = user_home / ".cline" / "data" / "settings" / "providers.json"
    if not path.is_file():
        return {"host": "cline", "status": "absent", "path": str(path)}
    data = load_json(path)
    providers = data.setdefault("providers", {})
    prov = spec["provider"]
    now = utc_iso()
    stale_keys = [
        k for k in list(providers.keys())
        if k.startswith(f"{prov['id']}-") or k == "daytona-turbo-heretic-q6"
    ]
    want_entry = {
        "settings": {
            "provider": "openai-compatible",
            "apiKey": key,
            "model": "qwen3.8-27b-unc-q8",
            "baseUrl": prov["baseUrl"],
        },
        "updatedAt": now,
        "tokenSource": "manual",
    }

    def comparable(entry: dict[str, Any] | None) -> dict[str, Any] | None:
        if not isinstance(entry, dict):
            return None
        s = dict(entry.get("settings") or {})
        if not key:
            s.pop("apiKey", None)
        return s

    w = dict(want_entry["settings"])
    if not key:
        w.pop("apiKey", None)
    have = providers.get("openai-compatible")
    if not stale_keys and comparable(have) == w:
        return {"host": "cline", "status": "current", "path": str(path)}
    state = "missing" if have is None else "drift"
    if not apply:
        return {"host": "cline", "status": state, "path": str(path), "staleKeys": stale_keys}
    if not key:
        raise RuntimeError("AGENTHUB_INFERENCE_KEY is required to write cline providers.json")
    orig_last = data.get("lastUsedProvider")
    orig_cline_oauth = json.dumps(providers.get("cline"), sort_keys=True)
    for sk in stale_keys:
        providers.pop(sk, None)
    providers["openai-compatible"] = want_entry
    if not orig_last or orig_last in stale_keys:
        data["lastUsedProvider"] = "openai-compatible"
    if json.dumps(providers.get("cline"), sort_keys=True) != orig_cline_oauth:
        raise RuntimeError("cline invariant violation: cline OAuth modified")
    write_json(path, data)
    load_json(path)
    return {"host": "cline", "status": "applied", "previous": state, "path": str(path)}


def sync_zcode(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, key: str) -> dict[str, Any]:
    path = user_home / ".zcode" / "v2" / "provider_config.json"
    if not path.is_file():
        return {"host": "zcode", "status": "absent", "path": str(path)}
    data = load_json(path)
    cfg = data.setdefault("config", {})
    order = list(cfg.get("providerOrder") or [])
    rules_wrap = cfg.setdefault("providerConfigRules", {})
    rules = list(rules_wrap.get("providerRules") or [])
    prov = spec["provider"]
    model_ids = [m["id"] for m in spec["models"]]
    want_rule = {
        "providerId": prov["id"],
        "providerName": prov["displayName"],
        "config": {
            "group": "standard-personal",
            "access": {"type": "api-key", "apiKey": key},
            "api": {"type": "openai-chat-completions", "baseUrl": prov["baseUrl"]},
            "personalModelIds": model_ids,
            "modelOrder": model_ids,
        },
    }
    have_rule = next((r for r in rules if isinstance(r, dict) and r.get("providerId") == prov["id"]), None)

    def norm_rule(r: dict[str, Any] | None) -> dict[str, Any] | None:
        if not isinstance(r, dict):
            return None
        copy = json.loads(json.dumps(r))
        if not key:
            copy.get("config", {}).get("access", {}).pop("apiKey", None)
        return copy

    has_legacy = any(oid in LEGACY_ZCODE_PROVIDER_IDS for oid in order) or any(
        isinstance(r, dict) and r.get("providerId") in LEGACY_ZCODE_PROVIDER_IDS for r in rules
    )
    if prov["id"] in order and norm_rule(have_rule) == norm_rule(want_rule) and not has_legacy:
        return {"host": "zcode", "status": "current", "path": str(path)}
    state = "missing" if have_rule is None else "drift"
    if not apply:
        return {"host": "zcode", "status": state, "path": str(path), "hasLegacy": has_legacy}
    if not key:
        raise RuntimeError("AGENTHUB_INFERENCE_KEY is required to write zcode provider_config.json")
    orig_zai = json.dumps(next((r for r in rules if isinstance(r, dict) and r.get("providerId") == "account:zai-start-plan"), None), sort_keys=True)
    order = [oid for oid in order if oid not in LEGACY_ZCODE_PROVIDER_IDS]
    if prov["id"] not in order:
        order.append(prov["id"])
    drop_ids = {prov["id"], *LEGACY_ZCODE_PROVIDER_IDS}
    new_rules = [r for r in rules if not (isinstance(r, dict) and r.get("providerId") in drop_ids)]
    new_rules.append(want_rule)
    cfg["providerOrder"] = order
    rules_wrap["providerRules"] = new_rules
    new_zai = json.dumps(next((r for r in new_rules if isinstance(r, dict) and r.get("providerId") == "account:zai-start-plan"), None), sort_keys=True)
    if new_zai != orig_zai:
        raise RuntimeError("zcode invariant violation: account:zai-start-plan modified")
    write_json(path, data)
    load_json(path)
    return {"host": "zcode", "status": "applied", "previous": state, "path": str(path)}


def sync_amp(spec: dict[str, Any], user_home: Path, _roaming: Path, _repo: Path, apply: bool, key: str) -> dict[str, Any]:
    if user_home.resolve() != Path.home().resolve():
        return {"host": "amp", "status": "skipped-synthetic-profile", "path": str(user_home / ".config" / "amp" / "settings.json")}
    if not shutil.which("amp"):
        return {"host": "amp", "status": "absent", "path": "amp"}
    listed = subprocess.run(["amp", "config", "model-providers", "list"], capture_output=True, text=True, check=False)
    prov = spec["provider"]
    if prov["displayName"] in (listed.stdout or ""):
        return {"host": "amp", "status": "current", "path": "amp config model-providers"}
    if not apply:
        return {"host": "amp", "status": "missing", "path": "amp config model-providers"}
    if not key:
        raise RuntimeError("AGENTHUB_INFERENCE_KEY is required to add Amp custom-url router")
    mapping = ",".join(f"openai/{m['id']} -> {m['id']}" for m in spec["models"])
    cmd = [
        "amp",
        "config",
        "model-providers",
        "add-router",
        "custom-url",
        "--personal",
        "--name",
        prov["displayName"],
        "--api-format",
        "chat-completions",
        "--base-url",
        prov["baseUrl"],
        "--api-key-file",
        "-",
        "--model-mapping",
        mapping,
        "--active",
    ]
    res = subprocess.run(cmd, input=key, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        raise RuntimeError(f"amp add-router failed ({res.returncode}): {(res.stderr or res.stdout).strip()[:240]}")
    return {"host": "amp", "status": "applied", "previous": "missing", "path": "amp config model-providers"}


ADAPTERS = {
    "opencode": sync_opencode,
    "codex": sync_codex,
    "factory": sync_factory,
    "grok": sync_grok,
    "copilot": sync_copilot,
    "vscode-insiders": sync_vscode,
    "kilo": sync_kilo,
    "cline": sync_cline,
    "zcode": sync_zcode,
    "amp": sync_amp,
}


def run_sync(
    repo_root: Path,
    user_home: Path,
    roaming_config: Path,
    apply: bool,
    host_filter: set[str] | None,
) -> list[dict[str, Any]]:
    spec = load_json(repo_root / "registry" / "inference-providers.json")
    key = resolve_inference_key(user_home) if apply or user_home.resolve() == Path.home().resolve() else ""
    results: list[dict[str, Any]] = []

    tmp_backup_root = None
    if apply:
        local_app = Path(os.environ.get("LOCALAPPDATA") or (user_home / "AppData" / "Local"))
        tmp_backup_root = local_app / "AgentHub" / "tmp" / f"inference-sync-{os.getpid()}"
        tmp_backup_root.mkdir(parents=True, exist_ok=True)

    try:
        for host_id, meta in spec["hosts"].items():
            if host_filter and host_id not in host_filter:
                continue
            adapter = ADAPTERS.get(host_id)
            if adapter is None:
                results.append(
                    {
                        "host": host_id,
                        "status": meta["integration"],
                        "notes": meta.get("notes", ""),
                    }
                )
                continue
            try:
                res = adapter(spec, user_home, roaming_config, repo_root, apply, key)
                results.append(res)
            except Exception as exc:
                results.append({"host": host_id, "status": "error", "error": str(exc)})
                if apply:
                    raise
    finally:
        if tmp_backup_root and tmp_backup_root.exists():
            shutil.rmtree(tmp_backup_root, ignore_errors=True)

    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Additive AgentHub Daytona inference provider sync")
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--user-profile", default=str(Path.home()))
    parser.add_argument("--roaming-config", default="")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--host", action="append", default=[])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    user_home = Path(args.user_profile)
    roaming = Path(args.roaming_config) if args.roaming_config else (
        Path(os.environ["APPDATA"]) if (args.user_profile == str(Path.home()) and "APPDATA" in os.environ) else user_home / "AppData" / "Roaming"
    )
    host_filter = {h.strip() for h in args.host if h.strip()} or None
    results = run_sync(Path(args.repo_root), user_home, roaming, args.apply, host_filter)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for row in results:
            extra = row.get("path") or row.get("notes") or row.get("error") or ""
            print(f"{row['host']:<18} {row['status']:<26} {extra}")

    has_error = any(r.get("status") == "error" for r in results)
    return 1 if has_error else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
