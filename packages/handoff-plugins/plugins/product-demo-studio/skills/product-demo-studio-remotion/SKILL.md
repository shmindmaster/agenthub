---
name: product-demo-studio-remotion
description: >
  Product Demo Studio's Remotion integration layer. Use when implementing a validated product-demo
  storyboard in Remotion: compose captured product evidence, protected UI regions, cold open,
  before-state, single hero moment, WIIFM, emotional target, attention cadence, captions, and end
  card. For generic Remotion API or mechanics questions, prefer the current official
  remotion-best-practices capability when available; these bundled rules are a fallback snapshot,
  not a second general Remotion owner. Use product-demo-studio-capture for evidence capture and
  product-demo-studio-render for rendering and release gates.
---

## Ownership boundary

This skill owns Product Demo Studio composition policy and integration. The current official
`remotion-best-practices` capability owns generic Remotion APIs and framework mechanics when it is
available on the host. Consult that owner first for evolving component and prop guidance, then
apply this skill's demo-specific truth, persuasion, safe-region, and evidence requirements. The
bundled rules remain a self-contained fallback for hosts without the official capability.

## Version pin

If the target repo already has a Remotion project, match its existing `remotion`/`@remotion/cli`
and `react` versions exactly — do not let a video workspace drift onto a different Remotion major
version than the rest of that repo's toolchain without a deliberate, explicit upgrade. If several
sibling repos in a workspace already share a pinned version (check via `repo-registry.mjs --root`),
match that shared version for a new repo too, so lockfiles and CLI behavior stay consistent; if
you're working in a single repo with no such context, a recent stable Remotion release is fine.

## New project setup

When in an empty folder or workspace with no existing Remotion project, scaffold one using:

```bash
npx create-video@latest --yes --blank --no-tailwind my-video
```

Replace `my-video` with a suitable project name. Prefer `product-demo-studio`'s
`scripts/scaffold-video-workspace.mjs` instead when you want the plugin's reference shape (typed
catalog, render scripts, pinned versions) rather than a generic blank scaffold — see
`product-demo-studio-render` for that catalog shape.

## Designing a video

Before designing visual scenes, layouts, promos, motion graphics, or text-heavy videos, load
[rules/video-layout.md](rules/video-layout.md) for video-first layout and text sizing guidance.

Read the router's `references/killer-demo-playbook.md` before composing. The storyboard
must already pass `validate-storyboard.mjs`; Remotion implements that plan and does not rescue a
`FAIL` episode whose product UX cannot clear the bar.

Animate properties using `useCurrentFrame()` and `interpolate()`. Prefer `interpolate()` over
`spring()` unless the user explicitly asks for physics-based motion. Use `Easing.bezier()` to
customize timing, including jumpy or overshooting motion; use `Easing.spring()` for spring-style
easing without a full physics simulation.

HTML elements that make sense to drag in Remotion Studio should use `Interactive`: `<div>` ->
`<Interactive.Div>`. Set a descriptive `name` prop such as `name="Hero title"` for `Interactive`,
`Solid`, and `Sequence` so the element is identifiable in the Studio timeline — never
`name=""`.

```tsx
import { useCurrentFrame, Easing, interpolate, Interactive } from "remotion";

export const FadeIn = () => {
  const frame = useCurrentFrame();

  return (
    <Interactive.Div
      name="Title"
      style={{
        opacity: interpolate(frame, [0, 60], [0, 1], {
          extrapolateRight: "clamp",
          extrapolateLeft: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        }),
      }}
    >
      Hello World!
    </Interactive.Div>
  );
};
```

Keep the `interpolate()` call inline in the `style` prop. Prefer the `scale`, `translate`,
`rotate` CSS properties over composing a single `transform` string.

```tsx
// 👍 Inline editable keyframes and transform shorthands
style={{
  scale: interpolate(frame, [0, 100], [0, 1]),
  translate: interpolate(frame, [0, 100], ["0px 0px", "100px 100px"]),
  rotate: interpolate(frame, [0, 100], ["20deg", "90deg"]),
}}

// 👎 Hidden values and transform strings become harder to edit in Studio
const scale = interpolate(frame, [0, 100], [0, 1]);
const translateY = interpolate(frame, [0, 100], [0, 120]);
const rotation = interpolate(frame, [0, 100], [0, 20]);

style={{
  transform: `scale(${scale}) translateY(${translateY}px) rotate(${rotation}deg)`,
}}
```

CSS transitions or animations are **forbidden** — they will not render correctly. Tailwind
animation class names are **forbidden** for the same reason; see
[rules/tailwind.md](rules/tailwind.md) if the project uses Tailwind for static styling.

Place assets in the `public/` folder at your project root. Use `staticFile()` to reference files
from `public/`.

```tsx
import { Img, staticFile } from "remotion";

export const MyComposition = () => {
  return <Img src={staticFile("logo.png")} style={{ width: 100, height: 100 }} />;
};
```

Add video and audio using `@remotion/media`. Use `staticFile()` for files in `public/`, or pass a
remote URL directly:

```tsx
import { Audio, Video } from "@remotion/media";
import { staticFile } from "remotion";

export const MyComposition = () => {
  return (
    <>
      <Video src={staticFile("video.mp4")} style={{ opacity: 0.5 }} />
      <Audio src={staticFile("audio.mp3")} />
      <Video src="https://remotion.media/video.mp4" />
    </>
  );
};
```

To delay content, wrap it in `<Sequence>` and use `from`. To limit the duration of an element,
use `durationInFrames` on `<Sequence>`. `<Sequence>` is an absolute fill by default — for inline
content, use `layout="none"`.

```tsx
export const Title = () => {
  const frame = useCurrentFrame();

  return (
    <div
      style={{
        opacity: interpolate(frame, [0, 60], [0, 1], {
          extrapolateRight: "clamp",
          extrapolateLeft: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        }),
      }}
    >
      Title
    </div>
  );
};

export const Subtitle = () => {
  return <div>Subtitle</div>;
};

const Main = () => {
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill>
      <Sequence>
        <Background />
      </Sequence>
      <Sequence from={30} durationInFrames={60} layout="none">
        <Title />
      </Sequence>
      <Sequence from={60} durationInFrames={60} layout="none">
        <Subtitle />
      </Sequence>
    </AbsoluteFill>
  );
};
```

## One segment, one beat

Each narration segment maps to **exactly one visible beat**. Each act owns its own setup and
navigation and must not rely on an accidental side effect left by a previous act. Static validation
should confirm segment IDs are complete, unique, and ordered, and rendered segments must match the
declared storyboard sequence.

For every episode, preserve exactly one `heroMoment` segment and one `payoff` segment (often the
same beat), a three-to-five-second shown before state, an emotional target, and an end card. Every
segment carries one WIIFM and one primary visual target. Use the primary `feature` → `outcome` →
`identity` ladder; the payoff must reach `outcome` or `identity`. A feature- or
functional-benefit-only payoff fails static
validation.

## Compose for attention and emotional payoff

- Make the first frame carry pain, tension, or a brief result glimpse. Never begin with login,
  decorative logo motion, a dashboard tour, or generic "AI" copy.
- Stage the hero moment with a short pre-silence, restrained push-in, at most one sound cue, and a
  readable hold. Do not create a second competing reveal.
- Build complex screens progressively, preserve spatial continuity, and treat the cursor as an
  actor: gesture, hesitate, trace, click, then park.
- Compose interactive product beats as continuous guided screencasts. The pointer path, real
  control action, visible state transition, annotation, and narration must use the storyboard and
  capture-manifest offsets. Reject decorative cursor motion, unexplained teleporting, click cues
  without a corresponding state change, and narration that names a result before it appears.
- Maximize useful UI: remove extraneous browser/OS chrome at capture, collapse irrelevant
  navigation through real product controls, and crop/push-in/recompose so the active region
  occupies at least half of the usable delivered frame. Preserve enough surrounding product
  context to keep the interaction truthful.
- Use real time for meaningful interaction, speed-ramp bounded boring steps, and return to real time
  for payoff. Change pace, sound, zoom, text, or framing about every 10–15 seconds without becoming
  frenetic.
- Use kinetic type only for the one verified number that expresses the transformation.
- Recompose vertical and square variants around the active region; captions stay primary for muted
  social viewing. Design the thumbnail/first frame and the final outcome/next-step card.

## Generated imagery never invents product truth

Generated/AI imagery may be used for abstract backgrounds or motifs, but it must **never invent
product UI, on-screen text, numbers, tables, or formulas** — anything that reads as the real product
must come from a real capture (`product-demo-studio-capture`).

The width, height, fps, and duration of a video is defined in `src/Root.tsx`:

```tsx
import { Composition } from "remotion";
import { MyComposition } from "./MyComposition";

export const RemotionRoot = () => {
  return (
    <Composition
      id="MyComposition"
      component={MyComposition}
      durationInFrames={100}
      fps={30}
      width={1080}
      height={1080}
    />
  );
};
```

For scaffolds that should stay editable in Studio, keep the component and `<Composition>`
registration in the same file so dimensions, duration, fps, and defaults stay visible next to the
rendered code. Use `defaultProps` for composition-wide values and keep it as an inline object
literal on `<Composition>` or `<Still>`.

Metadata can also be calculated dynamically when it depends on input props, fetched data, or
asset metadata — see [rules/calculate-metadata.md](rules/calculate-metadata.md).

## Starting preview

```bash
npx remotion studio --no-open
```

This starts a long-running process and prints the server URL for the preview.

## Install modules

Use `npx remotion add` to add new packages with the right version:

```bash
npx remotion add @remotion/media
```

This applies to `@remotion/*` packages, `mediabunny`, `@mediabunny/*`, and `zod`.

## Optional: one-frame render check

You can render a single frame with the CLI to sanity-check layout, colors, or timing. Skip it for
trivial edits, pure refactors, or when you already have enough confidence from Studio or prior
renders.

```bash
npx remotion still [composition-id] --scale=0.25 --frame=30
```

At 30 fps, `--frame=30` is the one-second mark (`--frame` is zero-based).

## Detail rules — load only the one you need

| Topic | File |
|---|---|
| Captions / subtitles | [rules/subtitles.md](rules/subtitles.md), [rules/display-captions.md](rules/display-captions.md), [rules/import-srt-captions.md](rules/import-srt-captions.md), [rules/transcribe-captions.md](rules/transcribe-captions.md) |
| FFmpeg operations (trim, silence) | [rules/ffmpeg.md](rules/ffmpeg.md) |
| Silence detection | [rules/silence-detection.md](rules/silence-detection.md) |
| Audio visualization (bars, waveforms, bass-reactive) | [rules/audio-visualization.md](rules/audio-visualization.md) |
| Sound effects | [rules/sfx.md](rules/sfx.md) |
| Visual/pixel effects | [rules/effects.md](rules/effects.md), [rules/html-in-canvas.md](rules/html-in-canvas.md), [rules/light-leaks.md](rules/light-leaks.md) — see effect list below |
| 3D content (Three.js / R3F) | [rules/3d.md](rules/3d.md) |
| Advanced audio (trim, volume, speed, pitch) | [rules/audio.md](rules/audio.md) |
| Dynamic duration / dimensions / props | [rules/calculate-metadata.md](rules/calculate-metadata.md) |
| Stills, folders, default props, nested compositions | [rules/compositions.md](rules/compositions.md) |
| Google Fonts (recommended default) | [rules/google-fonts.md](rules/google-fonts.md) |
| Local fonts | [rules/local-fonts.md](rules/local-fonts.md) |
| Audio/video duration & dimensions (Mediabunny) | [rules/get-audio-duration.md](rules/get-audio-duration.md), [rules/get-video-dimensions.md](rules/get-video-dimensions.md), [rules/get-video-duration.md](rules/get-video-duration.md) |
| Checking decodability before playback | [rules/can-decode.md](rules/can-decode.md) |
| Extracting frames/thumbnails | [rules/extract-frames.md](rules/extract-frames.md) |
| GIFs | [rules/gifs.md](rules/gifs.md) |
| Images (sizing, dynamic paths, dimensions) | [rules/images.md](rules/images.md) |
| Lottie animations | [rules/lottie.md](rules/lottie.md) |
| Measuring DOM nodes | [rules/measuring-dom-nodes.md](rules/measuring-dom-nodes.md) |
| Measuring / fitting text | [rules/measuring-text.md](rules/measuring-text.md) |
| Advanced sequencing (delay, trim, overlap) | [rules/sequencing.md](rules/sequencing.md) |
| TailwindCSS (static styling only) | [rules/tailwind.md](rules/tailwind.md) |
| Text animations (typewriter, word highlight) | [rules/text-animations.md](rules/text-animations.md) |
| Advanced timing (interpolate, Bézier, springs) | [rules/timing.md](rules/timing.md) |
| Scene transitions | [rules/transitions.md](rules/transitions.md) |
| Transparent video export | [rules/transparent-videos.md](rules/transparent-videos.md) |
| Trimming patterns | [rules/trimming.md](rules/trimming.md) |
| Advanced video embedding | [rules/videos.md](rules/videos.md) |
| Parameterized videos (Zod schema) | [rules/parameters.md](rules/parameters.md) |
| Maps (static / Mapbox / MapLibre) | [rules/map.md](rules/map.md), [rules/mapbox.md](rules/mapbox.md), [rules/maplibre.md](rules/maplibre.md) |
| Voiceover — wiring generated audio into the composition (`calculateMetadata`, dynamic duration) | [rules/voiceover.md](rules/voiceover.md) — for actually *generating* the audio (provider-agnostic, with timing/checksum manifests and regenerate-only-changed), use `product-demo-studio-narration` instead of hand-writing a one-off script |
| **Animated charts (bar, pie, staggered)** | [rules/charts.md](rules/charts.md) — use for any metric/revenue/comparison chart scene |
| Video-first layout & text sizing | [rules/video-layout.md](rules/video-layout.md) |
| On-screen text vs. product occlusion (dynamic overlay placement) | [rules/overlay-placement.md](rules/overlay-placement.md) |

Example components referenced by the rules above live in
[rules/assets/](rules/assets/): `charts-bar-chart.tsx`, `text-animations-typewriter.tsx`,
`text-animations-word-highlight.tsx`.

## Visual and pixel effects

When creating a visual effect, prefer, in order: 1) normal Remotion/HTML/CSS/SVG/filter/blend/
mask animation, 2) a listed effect via [rules/effects.md](rules/effects.md) (including on HTML
rendered through `<HtmlInCanvas>`), 3) a custom `createEffect()` via
[rules/effects.md](rules/effects.md) when the user asks for a reusable/project-specific effect,
4) custom `<HtmlInCanvas onPaint>` via [rules/html-in-canvas.md](rules/html-in-canvas.md) only if
no listed effect fits. For light leak overlays, see [rules/light-leaks.md](rules/light-leaks.md).
Docs: https://www.remotion.dev/docs/effects

Available effects: `brightness()`, `contrast()`, `colorKey()`, `duotone()`, `grayscale()`,
`hue()`, `invert()`, `saturation()`, `tint()`, `linearGradient()`, `linearGradientTint()`,
`thermalVision()`, `blur()`, `linearProgressiveBlur()`, `radialProgressiveBlur()`, `zoomBlur()`,
`dropShadow()`, `glow()`, `lightTrail()`, `evolve()`, `venetianBlinds()`, `mirror()`, `scale()`,
`uvTranslate()`, `xyTranslate()`, `barrelDistortion()`, `chromaticAberration()`, `fisheye()`,
`cornerPin()`, `wave()`, `burlap()`, `emboss()`, `dotGrid()`, `halftone()`, `noise()`,
`noiseDisplacement()`, `paper()`, `roughenEdges()`, `pattern()`, `pixelate()`,
`pixelDissolve()`, `scanlines()`, `speckle()`, `shine()`, `shrinkwrap()`, `vignette()`,
`contourLines()`, `checkerboard()`, `halftoneLinearGradient()`, `gridlines()`, `whiteNoise()`,
`tvSignalOff()`, `lines()`, `rings()`, `waves()`, `zigzag()`, `lightLeak()`, `starburst()`.

## Next steps

Once the composition renders correctly in Studio, move to `product-demo-studio-render` to render
the final MP4s, run the evidence gate, and (optionally) hand off to
`product-demo-studio-descript` for editorial finishing.
