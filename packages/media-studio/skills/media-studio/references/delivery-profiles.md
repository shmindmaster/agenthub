# Delivery profiles

Set `deliveryProfile` on `job.json`. Default by kind (`program-forms.md` may override).

| Kind | Default profile | Frame |
| --- | --- | --- |
| `briefing` | `briefing-board` | 1600×1000 30fps |
| `training` | `onboarding` | 1600×1000 30fps |
| `explainer` | `youtube-16x9` | 1920×1080 30fps |
| `talking-head` | `youtube-16x9` | 1920×1080 30fps |
| `animation` | `youtube-16x9` | 1920×1080 30fps |
| `series-episode` | `youtube-16x9` | 1920×1080 30fps |
| `webcast` | `webcast` | 1920×1080 30fps |
| `webinar` | `webcast` | 1920×1080 30fps |
| `keynote` | `youtube-16x9` | 1920×1080 30fps |
| `documentary` | `youtube-16x9` | 1920×1080 30fps |
| `teaser` | `linkedin` | 1920×1080 30fps (use `vertical-9x16` when the brief is Shorts/Reels) |
| `audio-only` | n/a | no picture |
| `product-screencast` | PDS delivery spec | do not apply this file |

| Profile | Frame | Notes |
| --- | --- | --- |
| `youtube-16x9` | 1920×1080 | Title/thumbnail/opening promise must agree. Spoken-word finish I=-16. |
| `vertical-9x16` | 1080×1920 | Safe-area type; no edge-locked kickers. |
| `linkedin` | 1920×1080 | First 3s must read muted; captions required. |
| `presentation` | 1920×1080 | Hold after each claim. |
| `onboarding` | 1600×1000 | One outcome per clip. |
| `briefing-board` | 1600×1000 | House kit native size. |
| `webcast` | 1920×1080 | Lower-thirds, chapter cards, speaker+slide. Safe title area. |

Compose letterboxes or re-layouts the kit to the profile. Do not invent a second Remotion app. Loudness stays `Finish-Media.ps1` two-pass linear I=-16 unless the job explicitly passes another `-Integrated` for a broadcast stem.
