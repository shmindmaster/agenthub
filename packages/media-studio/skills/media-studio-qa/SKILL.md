---
name: media-studio-qa
description: Use when a media-studio screencast candidate needs fail-closed evidence, craft, local audio perception, domain review, arbitration, or final verification.
---

# Media studio QA

Fail-closed release for `product-screencast`. Replaces retired `product-demo-studio-qa`.

```powershell
$Pds = Join-Path ($(if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' })) 'packages\product-demo-studio'
```

Follow `$Pds\pipeline\product-demo-studio-qa\SKILL.md`. Scripts and agents stay in that package.

Briefings, training, explainers, and talking-heads do **not** run the four-domain screencast gate. For those: identity-score owner voice, `ai.ps1 listen` on the encoded file, captions from the spoken words. Do not pretend a briefing passed Product Demo Studio arbitration.
