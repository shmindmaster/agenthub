# Lottie

Read this when a beat wants small vector motion: a check landing, a pulse on the thing being named, an arrow drawing, a loader, a sting.

## Roles

- **Authoring:** the `diffusionstudio/lottie` skill (`text-to-lottie`, MIT) writes Lottie JSON from a description and previews it with Skottie. It is not a renderer and has no video export.
- **Playback in video:** the kit's `lottie` visual kind uses `@remotion/lottie` (lottie-web, headless Chromium, no GPU). That is the frame you judge.
- **Not the same renderer:** Skottie and lottie-web can draw a file differently. Render a Remotion still of the scene and look at it before accepting an animation.

## Use

1. Author or get the JSON; save it in `kit/public/lottie/<name>.json`.
2. Add a scene: `{"kind":"lottie","src":"lottie/<name>.json","loop":false,"at":0.4}`.
3. `npx remotion still ... --frame <n> --public-dir public`, look at it at the start, middle and end.
4. Keep it small and purposeful: one idea, under two seconds for a sting, a loop only for a held state.

## Shipped

`check.json` (stroke draws a tick), `pulse.json` (ring expands, loops), `arrow.json` (line and head draw left to right). Hand-authored, no external assets.

## Licence

Remotion is free for individuals and for-profit companies of up to three people; larger companies need a Company License. `@remotion/lottie` follows the Remotion licence. Lottie files from a marketplace carry their own licence; check before shipping one.
