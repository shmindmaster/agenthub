---
name: local-ai-stack
description: Operate the standalone local media stack on this workstation. Use for local Ollama, ComfyUI, Qwen VoiceDesign, Chatterbox, Z-Image, Wan, Motif, and ACE-Step readiness or synthetic media smoke work.
---

# Local AI stack

This is a personal machine capability. Its runtime and model data live only
under `D:\AI-Platform`; AgentHub owns this capability record and its host
adapters. It is not an MCP server, a product-demo capability, or a source of
truth for any application repository.

## Control interface

```powershell
D:\AI-Platform\ai.ps1 status
D:\AI-Platform\ai.ps1 check
D:\AI-Platform\ai.ps1 start
D:\AI-Platform\ai.ps1 stop
```

The standalone runtime is `D:\AI-Platform\media`. Generated files belong in
`D:\AI-Platform\artifacts\media`; do not create root-level `C:\` folders,
copy model weights, or introduce another registry, skill tree, plugin, or MCP
wrapper for this capability.

## Supported routes

- Voice: Qwen VoiceDesign BF16 and Chatterbox native.
- Image: Z-Image Turbo BF16 through ComfyUI.
- Video: Wan FP16 and Motif Q8 direct Diffusers route.
- Music: ACE-Step through ComfyUI.

Use the registry at `D:\AI-Platform\media\registry.json` for exact paths,
model revisions, and required VRAM. Run `D:\AI-Platform\media\gpu_guard.py`
before a heavy route and reclaim VRAM after it. Serialize GPU-heavy jobs.

## Guardrails

- Do not pass `num_ctx` to Ollama; model context is baked into the model.
- Keep flash-attention disabled on this Blackwell workstation.
- Use synthetic inputs for reusable capability checks.
- Do not restore removed legacy pipelines, model copies, or deprecated
  product-demo workflows.
