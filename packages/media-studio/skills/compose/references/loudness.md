# Loudness targets and bed ducking

Finish with `Finish-Media.ps1`. Do not hand-write an FFmpeg graph. It runs two-pass linear loudnorm and refuses one-pass.

| Target | `-Integrated` | `-TruePeak` |
| --- | --- | --- |
| YouTube, web (about) | -14 | -1 |
| Podcast, spoken word | -16 | -1 |
| Broadcast, EBU R128 | -23 | -1 |

Set `loudnessTargetLufs` in `job.json` to the same target; the release gate defaults to -16. A job with a bed must finish from stems with `-Speech -Music` so the helper ducks the bed (asplit, sidechaincompress, amix; 200 ms attack, 800 ms release). Start the bed about -18 dB under speech and adjust by ear. Never mux an unducked bed. If only LRA blocks the linear pass, add `-LoudnessRange 11`; never `-AllowDynamic` on TTS. Do not run a hosted enhancer on voice; regenerate the segment.
