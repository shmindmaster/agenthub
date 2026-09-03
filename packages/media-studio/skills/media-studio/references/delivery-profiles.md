# Delivery profiles

Set `deliveryProfile` on `job.json`. Default by kind:

| Kind | Default profile | Frame |
| --- | --- | --- |
| `briefing` | `briefing-board` | 1600×1000 30fps |
| `training` | `briefing-board` | 1600×1000 30fps |
| `explainer` | `youtube-16x9` | 1920×1080 30fps |
| `talking-head` | `youtube-16x9` | 1920×1080 30fps |
| `animation` | `youtube-16x9` | 1920×1080 30fps |
| `series-episode` | `youtube-16x9` | 1920×1080 30fps |
| `audio-only` | n/a | no picture |
| `product-screencast` | PDS delivery spec | do not apply this file |

Overrides:

| Profile | Frame | Notes |
| --- | --- | --- |
| `youtube-16x9` | 1920×1080 | Title/thumbnail/opening promise must agree. |
| `vertical-9x16` | 1080×1920 | Safe-area type; no edge-locked kickers. |
| `linkedin` | 1920×1080 | First 3s must read muted; captions required. |
| `presentation` | 1920×1080 | Hold after each claim; presenter may pause. |
| `onboarding` | 1600×1000 | One outcome per clip; shorter than a briefing. |
| `briefing-board` | 1600×1000 | House kit native size. |

Compose letterboxes or re-layouts the kit to the profile. Do not invent a second Remotion app.
