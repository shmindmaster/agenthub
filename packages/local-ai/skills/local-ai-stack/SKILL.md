---
name: local-ai-stack
description: Use when local model inference, RAG/retrieval, media generation, or legal/knowledge scope routing are required. Thin router over D:\Local-AI\ai.ps1 — load references/voice.md, image.md, music.md, retrieval.md, or ops.md only for the needed specialty.
---

# Local AI stack

This is the operator skill for one user-owned Local-AI runtime. Its instructions
are host-neutral, but the supported operator interface is Windows PowerShell.
The skill's presence does not prove that it is installed on every agent host or
that the runtime is currently ready.

`D:\Local-AI` is a local runtime tree, not a git repository. Do not `git init`,
commit, or push it. Canonical agent instructions for this capability live in
this AgentHub package.

## Resolve the runtime

Resolve the root once. The environment override supports another machine; the
default for this workstation is `D:\Local-AI`.

```powershell
$LocalAiRoot = if ($env:LOCAL_AI_ROOT) { $env:LOCAL_AI_ROOT } else { 'D:\Local-AI' }
$LocalAiControl = Join-Path $LocalAiRoot 'ai.ps1'
$LocalAiRegistry = Join-Path $LocalAiRoot 'registry.json'
```

After this bootstrap, resolve services, ports, models, indexes, storage roots,
and artifacts from `$LocalAiRegistry`. Examples below describe intent; embedded
paths or ports are not a second source of truth.

## Layout

```text
models\chat | retrieve | generate
data\catalog | artifacts | cache | secrets | runtime
runtimes\retrieve | media | llama | python
apps\retrieval | api
media\   # image/voice/motif/music/transcribe scripts
```

Qdrant is the Compose service with Docker named volumes, not a folder
under `data\`. Verified against disk 2026-08-21. This is orientation, not
authority — the registry stays the source of truth for any path you act on.

## Outcome-oriented discovery

Use this skill only after layered checks:

1. `& $LocalAiControl status` for current service state.
2. `& $LocalAiControl check` for the control-plane contract, or `check deep`
   when the requested task warrants the full deterministic smoke gate.
3. Confirm the requested route's services, model files, and stable alias—not
   only generic stack health.
4. For a heavy job, inspect GPU occupancy and active jobs. Reclaim only with
   task authority and only after identifying what it will unload.

Proceed only for the route whose checks passed:

- **chat + attachments** -> Open WebUI route.
- **knowledge/legal retrieval** -> RAG route.
- **image / motif video** -> ComfyUI route (`ai.ps1 image` / `motif`).
- **music beds** -> `ai.ps1 music` (ACE-Step resident). Do **not** start ComfyUI.
- **voice/STT/audio perception** -> dedicated media runtime route. TTS and `listen` do not need music or Comfy.

## One control interface

`$LocalAiControl` is the only control plane for this capability.

```powershell
& $LocalAiControl status
& $LocalAiControl check [deep]
& $LocalAiControl start <target>
& $LocalAiControl stop <target>
& $LocalAiControl reclaim <minimum GiB>
& $LocalAiControl reindex <knowledge|legal|all> [--recreate] [--activate]
```

`start`, `stop`, `restart`, `clean`, `reclaim`, every `reindex`, media generation,
`--recreate`, and `--activate` mutate shared runtime state, consume shared GPU,
or write artifacts. Inspect the exact target and active jobs, then obtain the
authority required by the current task. Build a replacement collection without
`--activate`; activate only after point parity, retrieval acceptance, and
independent review pass.

The retrieval service's local admin credentials are auto-provisioned on first
`start retrieval` / `start core`: `ai.ps1` writes
`data\secrets\retrieval-admin-secrets.json` under the resolved root with a
restrictive ACL when it is absent. No manual environment variables are
required for a local run.

All media and synthesis routes are also under the same interface:

```powershell
& $LocalAiControl image <single|batch>
& $LocalAiControl voice <qwen|qwen-role|qwen-clone|qwen-*-batch|score|verify>
& $LocalAiControl catalog ["<voice alias>"]
& $LocalAiControl transcribe <audio-or-video-path>
& $LocalAiControl listen <encoded-video-path> --output <immutable-native-report.json> `
  --candidate-id <id> --source-revision <revision> --render-provenance-id <id>
& $LocalAiControl music <batch-json>
& $LocalAiControl motif <verify|single|batch>
```

Do not add a second control script or a parallel launcher for this capability.
**`ai.ps1 voice kokoro` is removed** and fails loudly.

`ai.ps1 listen` is the only full-program audio-perception route for a system-owned
Product Demo Studio audio release gate. It runs locally and emits the immutable
native report described by Product Demo Studio's `local-ai-listen-report.schema.json`;
it is not human playback. Product Demo Studio binds that untouched report inside
`candidate-audio-perception-report.schema.json` with the model receipt and fresh
calibration before read-only adjudication. Load `references/voice.md` for details.

## Progressive disclosure

Do **not** load specialist knowledge until the task needs it. After the control
plane checks above, open only the matching reference:

| Need | Load |
| --- | --- |
| Voice / TTS / STT / voice corpus | `references/voice.md` |
| Image / Visual Bank | `references/image.md` |
| Music beds / underscore | `references/music.md` |
| RAG, chat model policy, knowledge/legal scope | `references/retrieval.md` |
| Storage, GPU scheduling, validation, adoption | `references/ops.md` |
| Long batch jobs | also load skill `long-running-generation` |

Keep one control plane: `D:\Local-AI\ai.ps1` (or `$env:LOCAL_AI_ROOT\ai.ps1`).
Do not invent parallel launchers.

## Guardrails (always)

- Never centralize credentials, customer data, or private evidence in AgentHub.
- Never write Local-AI runtime paths, corpora, or weights into this repository.
- Never add a second control script beside `ai.ps1`.
- Load the smallest reference set that covers the task.
