# Local-AI music (progressive load)

Load when the task needs instrumental beds or underscore. Control plane remains
`ai.ps1` / `$LocalAiControl`.

## Rule

**`ai.ps1 music` is ACE-Step v1 3.5B, GPU-resident, no ComfyUI.** Do not
`start comfyui` for music. ComfyUI stays the image/motif canvas only.

TTS narration does **not** need music or Comfy. Speech is `ai.ps1 voice …`
(`faster-qwen3-tts`). Mix a bed under it later if you want one.

## Media Studio cues

`media-studio-generate` is the caller. ACE-Step still has **one** instrument:
instrumental generation. Map screenplay/storyboard cues onto that instrument.
There is no separate SFX plugin.

| Cue | Generate | Mix |
| --- | --- | --- |
| `musicCue: bed` | One program bed. Prompt for underscore, not a song with vocals (unless `singer: sarosh`). | `Finish-Media.ps1 -Speech -Music` sidechain duck. Bed is **felt not heard** — under speech, never competing with consonants, names, or numbers. |
| `musicCue: sting` | A **short** 2–4s hit (accent / riser / whoosh / impact-soft). Separate ACE-Step job, not a second 3-minute bed. | Place on the cut or reveal. Do not loop a sting as a bed. |
| `musicCue: silence` or `silenceOnReveal: true` | **Do not generate** music for that window. | True quiet. Do not sneak a bed under a hero hold. |
| `sfxCue: click` on a `screen` beat | Recast click, not ACE-Step. | Product feedback owns the hit. |

Prefer:

`one ducked bed + silence on the reveal + one sting on the match-cut`

Avoid:

`wall-to-wall bed at speech level` / filling every gap / a 90s 'sting'

Serialized GPU: do not run music next to ingest, TTS, or Comfy without
explicit ownership of the card.

**Sarosh is the singer** for owner-sung songs. MiniMax's generated vocal is not
him. Prepare dry vocals from the owner singing folder, then set
`"singer": "sarosh"` on the job. Identity-score the result against the enrolled
Sarosh profile before calling it his voice.

```powershell
& $LocalAiControl music prepare-singer --resume
& $LocalAiControl music <batch.json> [--manifest-out <manifest.json>] [--resume]
```

Resolve the live runtime and weights from `$LocalAiRegistry` capability
`music.ace-step`. Do not call ComfyUI Python, `:8188`, or a second launcher.

The host is the same *kind* of trick as `faster-qwen3-tts`: same ACE-Step
weights, hot process, not a different model. `faster-qwen3-tts` is an inference
backend, not a new voice checkpoint.

`ai.ps1 start media` still starts Comfy for images. That is not the music
route.
