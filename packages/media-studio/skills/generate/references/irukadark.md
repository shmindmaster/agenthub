# IrukaDark: generated clips, pictures and audio by hand

IrukaDark (https://irukadark.com) is a web creative suite signed in through the abacare.ai Google login. Its sidebar has Video, Image, Audio, Screenplay, Assets, Directions and Meeting Notes. It is the funded generative-video lane (`irukadark` in `policy/provider-routing.json`). Nothing in the app exposes an API, so it is driven through the signed-in Chrome with Claude in Chrome and never scripted.

## What was measured on 2026-11-06

- Settings > Plans & Billing showed 12,800 credits on a plan labelled Free. The F6S code (10k credits) is already redeemed; entering it again says it cannot be used. That is expected, not a fault.
- Video page: Seedance 2.5, 5 s, 16:9, 720p, audio on, 4 variations shown as `/4`, Generate costs 232 credits. About 54 clips left.
- One test clip was generated (a loaded freight truck backing into a dock at dawn, no text, logos or people): 232 credits charged exactly, balance 12,568, about 4 minutes to render, a 5 s 720p clip with audio. Only the thumbnail frame was inspected and nothing was downloaded. Allow several minutes per clip and do not stack requests.

## When to use it

Only for an approved hero shot: a place, an outcome or a moment of tension, never product UI, a metric, a testimonial or a real person. Everything else stays in the cheaper lanes (the Remotion kit, Azure or Runware stills). A cinematic moment that a still plus a slow push-in in the kit can carry does not need a clip.

## Loop for one clip

1. Quote it first: `screenplay_breakdown.py <jobRoot>` shows `clips` and `clipCredits` for every `broll` scene. A `broll` scene may set `visual.seconds`; the clip count is that many seconds divided by 5, rounded up. Default is one clip.
2. Read the credit counter on https://irukadark.com/settings/billing. Stop if it is under the clip cost plus 500.
3. Open https://irukadark.com/ai/video. Prompt from the scene's `visual.prompt`: subject, place, light, camera move, and "no text, no logos, no people" unless the scene needs people. Keep Seedance 2.5, 5 s, 16:9, 720p.
4. Generate one clip, wait, and look at it before generating another. A bad clip is a prompt problem: change the prompt, never regenerate blindly.
5. Download the winner into `<jobRoot>/assets/clips/<sceneId>.mp4`. Ask the owner before each download, naming the file, the source and the size.
6. Set `visual.src` to the file, and append one line to `qa/spend-ledger.jsonl`: `{"lane":"irukadark","kind":"clip","scene":"<id>","credits":232,"at":"<iso>"}`.
7. Extract frames at 0, mid and end with ffmpeg and judge them with the contact sheet before the clip is accepted. Note anything that looks generated (hands, text, warped objects) and cut around it.

## Pictures and audio

Image: https://irukadark.com/ai/image. Use only for a by-hand still when Azure and Runware cannot make it; the scripted lanes are cheaper and keep a ledger. Audio and Screenplay: use the sidebar entries. Music and sound effects are disabled elsewhere in media-studio by policy; a track from here is a draft until the owner lifts that.

## Never

No real people, no logos, no claim about a real product or number. No bulk runs. No second account or code to top up. Do not count the credit as permission to raise any cap; read the counter again before every run, because a free-plan balance can change without notice.
