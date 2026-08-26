---
name: media-studio-qa
description: Use when a media-studio candidate needs fail-closed screencast evidence, craft, local audio perception, an engagement pass, domain review, arbitration, or final verification.
---

# Media studio QA

Load `../media-studio/references/engagement.md` (Generate / compose / QA own).

## product-screencast

Fail-closed release. Replaces retired `product-demo-studio-qa`.

```powershell
$Pds = Join-Path ($(if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' })) 'packages\product-demo-studio'
```

Follow `$Pds\pipeline\product-demo-studio-qa\SKILL.md`. Scripts and agents stay in that package. Story, pacing, music, and zoom for this kind are that gate — do not apply a second engagement rubric.

## Other kinds

Briefings, training, explainers, talking-heads, animation, and audio-only do **not** run the four-domain screencast gate. For those:

1. Identity-score owner voice and `ai.ps1 listen` on the **exact encoded file**. Above 90 seconds, pass the canonical narration timeline with `--timeline <timeline.json>`; the Local-AI report must bind the original candidate and prove contiguous decoded-sample coverage across its scene-aligned reviews. Do not substitute separately exported clips.
2. Captions from the spoken words.
3. Engagement pass on the **encoded** file (not the screenplay): walk every scene and list stretches that are slow, repetitive, visually static, or emotionally flat per `engagement.md` Diagnose first. Missing hook, wall-to-wall static, rushed payoff, unducked bed, or narration that reads the slide is a fail — remit to writer, director, generate, or compose. Do not ship and do not pretend the file passed Product Demo Studio arbitration.
