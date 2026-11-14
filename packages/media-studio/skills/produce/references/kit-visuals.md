# Kit visuals (Briefing composition)

Read this when writing `briefing-props.json`. One scene: `{ id, kicker, title, bullets: [], accent, visual, visualScale?, durationSeconds }`. `at` is seconds from scene start, taken from the word boundaries so a part arrives on the word that names it. Kit source: `kit/src/Visuals.tsx` and `kit/src/RichVisuals.tsx`.

## Picture kinds

```json
{"kind":"chart","form":"bars","unit":"%","caption":"Share of volume","items":[{"label":"FedEx heavy bulk","value":37,"at":0.6,"mark":"emphasis"},{"label":"Other tenants","value":22,"at":1.4}]}
{"kind":"chart","form":"waffle","items":[{"label":"of the heavy bulk volume","value":37,"at":0.4}]}
{"kind":"svg","caption":"Equipment path","viewBox":"0 0 1200 520","groups":[{"at":0.4,"svg":"<rect x='60' y='180' width='260' height='120' rx='14' fill='none' stroke='#8B6BFF' stroke-width='5'/><text x='190' y='250' text-anchor='middle' font-size='38' fill='#EFEBE0'>Penske</text>"}]}
{"kind":"lottie","src":"lottie/check.json","loop":false,"at":0.4,"caption":"Written answer sent"}
{"kind":"flow","caption":"...","nodes":[{"label":"...","sub":"...","at":1.2,"mark":"risk"}]}
{"kind":"layers","layers":[...]}   {"kind":"sequence","actors":[...],"steps":[...]}
{"kind":"timeline","events":[{"at":"Nov 5","label":"..."}]}   {"kind":"beforeafter","before":{...},"after":{...}}
{"kind":"map","lanes":[...]}   {"kind":"code","lines":[{"text":"...","at":1.0}]}
{"kind":"still","src":"stills/truck.png"}   {"kind":"screen-in-context","src":"clips/screen.mp4"}
```

## Typographic and card kinds

`stat`, `table`, `split`, `proof` (words arranged as a figure) and `hero`, `quote`, `checklist`, `cta`, `sidecar`, `chapter`, `lower-third` (cards). Use them for what they are good at; `check_visual_variety.py` counts them as not-pictures.

## SVG authoring

- A group is a fragment: shapes, paths, `<text>`. The kit adds the fade and rise; do not wrap groups in `<svg>`.
- Fill the 1200x520 viewBox; a drawing in one corner reads as empty. Raise `visualScale` if it still looks small.
- Colours: the accent is in `var(--accent)`; use `#3DDC84` good, `#E85D5D` risk, `#F5C518` emphasis, `#EFEBE0` text.
- Put the words a viewer reads in `<text>`. The relevance gate reads only `<text>` content, so a drawing that has no words from the line fails, on purpose.

## Lottie

Put the JSON in `kit/public/lottie/`. See `lottie.md`. Three small ones ship: `check.json`, `pulse.json`, `arrow.json`.

## Props and render

```text
npx remotion still src/index.ts Briefing out.png --props props.json --frame 120 --public-dir public
npx remotion render src/index.ts Briefing out.mp4 --props props.json --public-dir public
```

Mux the voice with explicit stream maps (`-map 0:v:0 -map 1:a:0`); a Remotion mp4 carries a silent audio track that ffmpeg would otherwise prefer.
