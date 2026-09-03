# Studio craft (picture, sound, voice)

Load with `engagement.md` on every **viewer-facing** job that is not a product screencast. Product screencasts stay on the PDS killer-demo gate.

Goal: the encoded file should feel directed, not templated. A narrated slide deck fails even if every schema field is filled.

## Picture

1. Coverage, not one locked frame. Change the picture when the idea changes. Voice-led films: a visual refresh inside ~4.5s (`rhythm.visualRefreshTarget`). Pattern interrupt (cut, archetype, register, or layout) at least every 45–90s on programs longer than two minutes.
2. Hard cuts are the default. One transition language per film. Motion dissolves are not decoration.
3. Shot plan is real: framing, subject, movement, focalPoint. Slow push on before-state; hold or silence on reveal.
4. Texture over void. Full-bleed B-roll, grain, or a designed field — not a forever-black card with type.
5. Recurring motif from `visual-bible.json`. The same visual language returns; it is not a new template per scene.
6. Real product UI is **capture** (`visualMode: screen`). Do not fake dashboards, metrics, or customer quotes in diffusion.
7. First and last frames are designed and stable. Lower-thirds need headroom; do not crop a chin.

Prefer:

`before-after split → real captured queue → silence hold on the exception`

Avoid:

`sixteen identical dark slides` / Ken Burns on type / AI avatar walking a fake UI

## Sound

Three layers. Voice is the anchor.

| Layer | Level | Rule |
| --- | --- | --- |
| Voice | program | Intelligible. Identity-gated for Sarosh. |
| Bed | ducked, felt not heard | `Finish-Media.ps1 -Speech -Music`. Never wall-to-wall under a hero. |
| Sting / silence | sparse | Sting on a cut or reveal. `silenceOnReveal` is true quiet. |

`sfxCue` is not a new engine: sting via ACE-Step, click via Recast on `screen`, silence otherwise.

Spoken-word delivery stays two-pass linear **I=-16 LUFS, TP=-1.5 dBTP** (`Finish-Media.ps1`). Do not one-pass loudnorm. Do not Studio-Sound owner voice.

## Voice

1. Conversational, not announcer. Owner voice uses the style-bank register on **each beat** (`direction.register`). Change register on the payoff.
2. Pauses are architecture. Documentary and trust films run slower than a briefing; let the picture sit. Do not pad TTS — hold in the edit.
3. Do not narrate visible chrome. Name the result after it appears.
4. One thought per sentence. Do not respell for pronunciation.

Prefer:

`firm` on the cost, `explaining` on the how, silence then `serious` on the hold

Avoid:

one register for twelve minutes / reading the slide / “welcome back”
