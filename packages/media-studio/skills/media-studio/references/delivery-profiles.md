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
| `linkedin` | 1920×1080 | Legacy landscape profile; first 3s must read muted. |
| `linkedin-4x5` | 1080×1350 | Portrait feed; graphics stay 5% clear of sides, 8% clear of top, 20% clear of bottom. |
| `presentation` | 1920×1080 | Hold after each claim. |
| `onboarding` | 1600×1000 | One outcome per clip. |
| `briefing-board` | 1600×1000 | House kit native size. |
| `webcast` | 1920×1080 | Lower-thirds, chapter cards, speaker+slide. Safe title area. |

`compose-screencast.mjs` scales captured footage to fit and pads to the selected profile by default. For intentional portrait framing, each campaign capture clip declares a normalized `sourceRegion`; the crop happens before fit, and the encoded-picture gate compares the candidate against the same cropped source. The selected region must retain the action, visible result, and relevant controls. Portrait campaigns also declare a `captionRegion` within the profile safe area and clear of protected controls and graphics; the exact-candidate caption review confirms placement. The card renderer uses the target frame. The encoded release gate checks exact width, height, and timeline duration whenever a profile is declared. Campaign forms require an explicit profile and additionally check their encoded duration range. Loudness stays `Finish-Media.ps1` two-pass linear I=-16 unless the job explicitly passes another `-Integrated` for a broadcast stem.
