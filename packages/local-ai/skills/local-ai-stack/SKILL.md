---
name: local-ai-stack
description: Use when local inference, RAG/retrieval, durable media jobs, Local-AI diagnostics, or knowledge/legal scope routing is required. Thin policy/router over D:\Local-AI\ai.ps1; load only the matching reference.
---

# Local-AI stack

This is the host-neutral operator skill for the user-owned Windows runtime.
`D:\Local-AI` is not a Git repository. Do not initialize, commit, or push it.
AgentHub owns portable policy; the runtime `registry.json` owns executable truth.

Resolve once:

```powershell
$LocalAiRoot = if ($env:LOCAL_AI_ROOT) { $env:LOCAL_AI_ROOT } else { 'D:\Local-AI' }
$LocalAiControl = Join-Path $LocalAiRoot 'ai.ps1'
```

## Discover before routing

```powershell
& $LocalAiControl status
& $LocalAiControl check
& $LocalAiControl doctor --json
& $LocalAiControl capabilities --json
& $LocalAiControl capability <id> --json
& $LocalAiControl route --intent <intent> --quality <tier> --json
```

`status` reports listener/readiness state. `check` validates the legacy
runtime/files contract and always emits a result. `doctor` is read-only,
returns stable issue codes, and distinguishes warnings from errors.

Quality tiers are `preview`, `standard`, `high`, and
`identity-critical`. Resolve services, ports, models, privacy classes,
resource conflicts, defaults, and fallbacks from the registry or discovery
output, never from prose alone.

## Durable work

Heavy legacy commands now submit through the durable queue and remain blocking.
For explicit control:

```powershell
& $LocalAiControl job submit <capability-id> --quality <tier> --wait -- <adapter-args>
& $LocalAiControl job list --json
& $LocalAiControl job inspect <job-id> --json
& $LocalAiControl job cancel <job-id>
& $LocalAiControl job retry <job-id> [--stage <stage>]
& $LocalAiControl job resume <job-id> [--stage <stage>]
& $LocalAiControl qa <artifact-or-job-id> --profile <tier> --json
```

One SQLite queue and one reconciled GPU lease system serialize transient jobs
and resident services. Unknown GPU occupants block; never kill or reclaim them
automatically. Large/private inputs stay referenced and hashed by default.
Owner identity QA runs only when a job explicitly carries `--owner-voice`.

## Retrieval

```powershell
& $LocalAiControl knowledge status --json
& $LocalAiControl knowledge stale --json
& $LocalAiControl knowledge explain '<query>' --index knowledge --json
& $LocalAiControl knowledge eval --json
& $LocalAiControl refresh <knowledge|legal|all>
```

Use alias `knowledge` for project/career/business evidence and `legal` only
for explicit legal scope. Local-AI Qdrant is `:16333`; `:6333` is another
instance. `refresh` owns scan/build/parity/alias activation. Do not activate a
replacement until parity and retrieval acceptance pass.

## Services and gateway

Use `start|stop|restart <target>` only with authority to mutate shared runtime
state. `all` starts core services, not a transient media engine. Stable
loopback adapters are `/local/chat`, `/local/retrieve`, `/local/voice`,
`/local/image`, `/local/asr`, and `/local/jobs`; direct ports remain for
compatibility and health checks. No route may silently fall back to cloud.

## Progressive disclosure

| Need | Load |
| --- | --- |
| Human command map | `references/operator-guide.md` |
| Voice, STT, identity | `references/voice.md` |
| Image and Visual Bank | `references/image.md` |
| Video, lipsync, portrait | `references/video.md` |
| Music | `references/music.md` |
| Retrieval and chat policy | `references/retrieval.md` |
| Storage, scheduling, adoption | `references/ops.md` |
| Long-running generation | also load `long-running-generation` |

## Guardrails

- Local-only by default; external transmission needs explicit approval.
- Never centralize secrets, authentication state, private evidence, customer
  data, owner voice, corpora, or weights in AgentHub.
- Do not add a redundant Codex plugin or a second Local-AI launcher.
- Do not phonetic-respell owner narration.
- Keep runtime-updated, committed, fleet-deployed, and live-verified states
  separate.
