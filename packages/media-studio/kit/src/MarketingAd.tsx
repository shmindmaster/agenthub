import type { CSSProperties, FC } from "react";
import { useEffect, useState } from "react";
import {
  AbsoluteFill,
  Easing,
  Freeze,
  Img,
  OffthreadVideo,
  Sequence,
  delayRender,
  continueRender,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

/**
 * MarketingAd: one composition for every ratio of an mvg ad (16:9, 4:5, 9:16). All geometry arrives in props from
 * kit/marketing (layout.mjs, crop.mjs, integrity.mjs): each ratio's native recording fills the frame at scale <= 1;
 * kinetic captions sit on their own plate over it; a kinetic title opens and an end card with the logo, the CTA and the
 * synthetic-data disclosure closes. It renders the picture only. Voice, effects and the bed are mixed with FFmpeg
 * (mix.mjs), so this file never plays audio.
 */

export type Box = { x: number; y: number; w: number; h: number };

/** Normalized source-region keyframes over a beat; times are seconds from the beat start (strictly increasing). */
export type Camera = { times: number[]; x: number[]; y: number[]; w: number[]; h: number[] };

export type AdBeat = {
  id: string;
  kind: "ui" | "broll" | "card" | "title";
  startSec: number;
  durationSec: number;
  headline?: string;
  isCta?: boolean;
  clip?: { src: string; trimBeforeSec: number; playSec: number; srcW: number; srcH: number; camera: Camera };
  image?: { src: string };
};

export type CaptionWord = { word: string; start: number; end: number };
export type CaptionChunk = { startSec: number; endSec: number; words: CaptionWord[]; lines?: number[] };

export type MarketingAdProps = {
  ratio: string;
  width: number;
  height: number;
  fps: number;
  durationSec: number;
  layout: {
    uiBand: Box;
    captionBox: Box & { fontSize: number; maxLines: number };
    ctaBox: Box;
    ctaPillFont?: number;
  };
  brand: {
    productName: string;
    colors: { primary: string; foreground: string; background: string; accent: string; onPrimary: string; emphasis?: string };
    fontDisplay: string;
    fontBody: string;
    fontFiles: { family: string; src: string; weight: number }[];
  };
  label: string;
  disclosure?: string;
  logo?: string;
  beats: AdBeat[];
  captions: CaptionChunk[];
  emphasis: string[];
  cta: { text: string; displayUrl: string };
};

export const sampleMarketingAd: MarketingAdProps = {
  ratio: "16x9",
  width: 1920,
  height: 1080,
  fps: 30,
  durationSec: 6,
  layout: {
    uiBand: { x: 0, y: 0, w: 1920, h: 1080 },
    captionBox: { x: 96, y: 924, w: 1728, h: 100, fontSize: 52, maxLines: 1 },
    ctaBox: { x: 96, y: 0, w: 1728, h: 1080 },
    ctaPillFont: 46,
  },
  brand: {
    productName: "ABACare",
    colors: { primary: "#6e56f8", foreground: "#0f172a", background: "#f6f8fb", accent: "#d97706", onPrimary: "#ffffff" },
    fontDisplay: "Space Grotesk",
    fontBody: "Geist",
    fontFiles: [],
  },
  label: "SYNTHETIC DEMO · NO PHI · REAL PRODUCT",
  beats: [
    { id: "T1", kind: "title", startSec: 0, durationSec: 3, headline: "Sample ad" },
    { id: "C1", kind: "card", startSec: 3, durationSec: 3, headline: "Try it on synthetic data", isCta: true },
  ],
  captions: [],
  emphasis: [],
  cta: { text: "Try it on synthetic data", displayUrl: "abacare.ai/demo" },
};

const EASE = Easing.inOut(Easing.cubic);
// Caption contrast on the navy bar (vision QA flagged grey unspoken words and orange emphasis as low contrast): unspoken
// words stay at 0.88 opacity and the emphasis is a light amber (about 12:1 on #0f172a) instead of the brand orange.
const UNSPOKEN_OPACITY = 0.88;
// A caption cue fades in over at most 6 frames: a longer fade is caught mid-way by any sampled frame and reads as unreadable.
const CAPTION_FADE_FRAMES = 6;
const PLATE = "15, 23, 42";
const EMPHASIS_COLOR = "#ffd166";

/**
 * The frames each beat occupies, [{ from, durationInFrames }]. Beat boundaries are not frame-aligned (edit.beatGrid), so start and
 * duration are never rounded on their own: a beat's end is the next beat's start, rounded once, and the sequences tile exactly. Rounding
 * both separately left a frame in no sequence (the navy AbsoluteFill showed as one black frame at the cut). kit/marketing/lib/timing.mjs
 * (sequenceFrames) is the tested twin of this function.
 */
const beatFrames = (beats: AdBeat[], fps: number): { from: number; durationInFrames: number }[] => {
  let cursor = beats.length ? Math.round(beats[0].startSec * fps) : 0;
  return beats.map((b) => {
    const from = cursor;
    cursor = Math.max(from + 1, Math.round((b.startSec + b.durationSec) * fps));
    return { from, durationInFrames: cursor - from };
  });
};

const stack = (display: string, body: string, which: "display" | "body"): string =>
  `${which === "display" ? display : body}, ${which === "display" ? body : display}, "Segoe UI", system-ui, sans-serif`;

const FontLoader: FC<{ files: MarketingAdProps["brand"]["fontFiles"] }> = ({ files }) => {
  const [handle] = useState(() => (files.length ? delayRender("brand fonts") : null));
  useEffect(() => {
    if (handle === null) return;
    Promise.all(
      files.map((f) => {
        const face = new FontFace(f.family, `url(${staticFile(f.src)})`, { weight: String(f.weight) });
        return face.load().then((loaded) => document.fonts.add(loaded));
      }),
    )
      .catch(() => undefined)
      .finally(() => continueRender(handle));
  }, [handle, files]);
  return null;
};

const UiCamera: FC<{ beat: AdBeat; band: Box }> = ({ beat, band }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const clip = beat.clip;
  if (!clip) return null;
  const t = frame / fps;
  const opts = { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE } as const;
  const cam = clip.camera;
  const rx = interpolate(t, cam.times, cam.x, opts);
  const ry = interpolate(t, cam.times, cam.y, opts);
  const rw = interpolate(t, cam.times, cam.w, opts);
  const rh = interpolate(t, cam.times, cam.h, opts);
  // The region (normalized) maps onto the band: scale the full source so the region fills it.
  const drawW = band.w / rw;
  const drawH = band.h / rh;
  const style: CSSProperties = { position: "absolute", left: -rx * drawW, top: -ry * drawH, width: drawW, height: drawH, maxWidth: "none" };
  const playFrames = Math.max(1, Math.round(clip.playSec * fps));
  const trimBefore = Math.round(clip.trimBeforeSec * fps);
  return (
    <div style={{ position: "absolute", left: band.x, top: band.y, width: band.w, height: band.h, overflow: "hidden", background: "#ffffff" }}>
      <div style={style}>
        <Sequence durationInFrames={playFrames} layout="none">
          <OffthreadVideo src={staticFile(clip.src)} muted trimBefore={trimBefore} style={{ width: "100%", height: "100%" }} />
        </Sequence>
        <Sequence from={playFrames} layout="none">
          <Freeze frame={playFrames - 1}>
            <OffthreadVideo src={staticFile(clip.src)} muted trimBefore={trimBefore} style={{ width: "100%", height: "100%" }} />
          </Freeze>
        </Sequence>
      </div>
    </div>
  );
};

const BrollBeat: FC<{ beat: AdBeat; band: Box; colors: MarketingAdProps["brand"]["colors"] }> = ({ beat, band, colors }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const zoom = interpolate(frame, [0, beat.durationSec * fps], [1.0, 1.08], { extrapolateRight: "clamp" });
  return (
    <div style={{ position: "absolute", left: band.x, top: band.y, width: band.w, height: band.h, overflow: "hidden", background: colors.foreground }}>
      {beat.image ? <Img src={staticFile(beat.image.src)} style={{ width: "100%", height: "100%", objectFit: "cover", transform: `scale(${zoom})` }} /> : null}
    </div>
  );
};

// The opening title is the hook: the stake in a few big words on brand colour, landing word by word on the beat. Each
// sentence is its own row so a line never wraps mid-sentence ("...Out in 2 / days."); the stagger counts across rows.
const TitleBeat: FC<{ beat: AdBeat; props: MarketingAdProps }> = ({ beat, props }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { brand, layout } = props;
  const box = layout.ctaBox;
  const rows = String(beat.headline ?? "").split(/(?<=[.!?])\s+/).map((r) => r.split(/\s+/).filter(Boolean)).filter((r) => r.length);
  // Each sentence row fits on one line: the type is sized from the widest row (Space Grotesk 600 is about 0.56 em per character,
  // plus the 0.28 em gap between words), never above the hook size and never below a floor of 0.08 of the box (only there may a row wrap).
  const cap = Math.round(Math.min(box.w, box.h) * (props.ratio === "16x9" ? 0.16 : 0.15));
  const floor = Math.round(Math.min(box.w, box.h) * 0.08);
  const rowEm = Math.max(0, ...rows.map((r) => 0.56 * r.join("").length + 0.28 * (r.length - 1)));
  const size = rowEm > 0 ? Math.max(floor, Math.min(cap, Math.floor(box.w / rowEm))) : cap;
  const STAGGER = 0.09;
  return (
    <AbsoluteFill style={{ background: `linear-gradient(150deg, ${brand.colors.primary} 0%, ${brand.colors.foreground} 85%)` }}>
      <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", flexDirection: "column", justifyContent: "center", rowGap: size * 0.06 }}>
        {rows.map((row, r) => {
          const first = rows.slice(0, r).reduce((n, x) => n + x.length, 0);
          return (
            <div key={r} style={{ display: "flex", flexWrap: "wrap", columnGap: size * 0.28, rowGap: size * 0.06 }}>
              {row.map((w, j) => {
                const i = first + j;
                const at = i * STAGGER * fps;
                const rise = interpolate(frame, [at, at + 0.28 * fps], [size * 0.5, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
                const fade = interpolate(frame, [at, at + 0.2 * fps], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
                const em = props.emphasis.some((e) => e.toLowerCase().replace(/[^a-z0-9$%]/g, "") === w.toLowerCase().replace(/[^a-z0-9$%]/g, ""));
                return (
                  <span key={`${i}-${w}`} style={{ fontFamily: stack(brand.fontDisplay, brand.fontBody, "display"), fontSize: size, fontWeight: 600, lineHeight: 1.02, letterSpacing: "-0.03em", color: em ? brand.colors.emphasis ?? EMPHASIS_COLOR : brand.colors.onPrimary, opacity: fade, transform: `translateY(${rise}px)` }}>
                    {w}
                  </span>
                );
              })}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// The end card: logo lockup, the line the film ends on, the call to action, and the synthetic-data disclosure as one
// small line at the foot (the only place it appears; it is never a chip over the product picture).
const CardBeat: FC<{ beat: AdBeat; props: MarketingAdProps }> = ({ beat, props }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { brand, layout, cta } = props;
  const rise = interpolate(frame, [0, 0.45 * fps], [28, 0], { extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  const fade = interpolate(frame, [0, 0.35 * fps], [0, 1], { extrapolateRight: "clamp" });
  const box = layout.ctaBox;
  const base = Math.round(Math.min(box.w, box.h) * 0.11);
  const pillFont = layout.ctaPillFont ?? Math.round(base * 0.5);
  const lead = beat.isCta && beat.headline && beat.headline !== cta.text ? beat.headline : null;
  const foot = [props.label, props.disclosure].filter(Boolean).join(" · ");
  return (
    <AbsoluteFill style={{ background: `linear-gradient(160deg, ${brand.colors.primary} 0%, ${brand.colors.foreground} 78%)` }}>
      <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "flex-start", gap: base * 0.45, opacity: fade, transform: `translateY(${rise}px)` }}>
        {beat.isCta && props.logo ? <Img src={staticFile(props.logo)} style={{ height: Math.round(base * 0.9), width: "auto", marginBottom: base * 0.25 }} /> : null}
        {lead ? (
          <div style={{ fontFamily: stack(brand.fontDisplay, brand.fontBody, "display"), fontSize: Math.round(base * 0.62), fontWeight: 600, lineHeight: 1.15, color: "rgba(255,255,255,0.94)" }}>{lead}</div>
        ) : null}
        <div style={{ fontFamily: stack(brand.fontDisplay, brand.fontBody, "display"), fontSize: base, fontWeight: 600, lineHeight: 1.08, letterSpacing: "-0.02em", color: brand.colors.onPrimary }}>
          {beat.isCta ? cta.text : beat.headline}
        </div>
        {beat.isCta ? (
          <div style={{ marginTop: base * 0.3, padding: `${pillFont * 0.34}px ${pillFont * 0.78}px`, borderRadius: 999, background: brand.colors.emphasis ?? EMPHASIS_COLOR, color: brand.colors.foreground, fontFamily: stack(brand.fontDisplay, brand.fontBody, "display"), fontWeight: 700, fontSize: pillFont, lineHeight: 1.1 }}>
            {cta.displayUrl}
          </div>
        ) : null}
      </div>
      {beat.isCta && foot ? (
        <div style={{ position: "absolute", left: box.x, top: box.y + box.h - Math.round(pillFont * 1.6), width: box.w, fontFamily: stack(brand.fontDisplay, brand.fontBody, "body"), fontSize: Math.round(pillFont * 0.62), fontWeight: 600, letterSpacing: "0.04em", color: "rgba(255,255,255,0.86)", opacity: fade }}>
          {foot}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

// A word that is spoken (or emphasised) is bold as well as brighter: colour alone is a 1.4:1 luminance step. The bold weight
// is reserved in every word's box (a hidden bold copy sizes it), so the line never reflows as words are spoken.
const CaptionWord_: FC<{ word: string; bold: boolean; opacity: number; color: string; scale: number; style: CSSProperties }> = ({ word, bold, opacity, color, scale, style }) => (
  <span style={{ display: "inline-grid", ...style }}>
    <span style={{ gridArea: "1 / 1", visibility: "hidden", fontWeight: 700 }}>{word}</span>
    <span style={{ gridArea: "1 / 1", justifySelf: "center", fontWeight: bold ? 700 : 600, color, opacity, transform: `scale(${scale})`, transformOrigin: "50% 60%", textShadow: "0 2px 10px rgba(15,23,42,0.55)" }}>{word}</span>
  </span>
);

const KineticCaptions: FC<{ props: MarketingAdProps }> = ({ props }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const t = frame / fps;
  // The end card's headline already says it, and a caption mid-fade on the plate falls below 3:1: no captions on card beats.
  // Compared in frames, against the same frames the sequences use, so the first and last frame of a card agree with its sequence.
  const frames = beatFrames(props.beats, fps);
  if (props.beats.some((b, i) => (b.kind === "card" || b.kind === "title") && frame >= frames[i].from && frame < frames[i].from + frames[i].durationInFrames)) return null;
  const chunk = props.captions.find((c) => t >= c.startSec && t < c.endSec);
  const box = props.layout.captionBox;
  if (!chunk) return null;
  const emphasis = new Set(props.emphasis.map((w) => w.toLowerCase().replace(/[^a-z0-9$%]/g, "")));
  const startFrame = Math.round(chunk.startSec * fps);
  const enter = interpolate(frame, [startFrame, startFrame + CAPTION_FADE_FRAMES], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const counts = chunk.lines && chunk.lines.length ? chunk.lines : [chunk.words.length];
  const rows: CaptionWord[][] = [];
  let at = 0;
  for (const n of counts) { rows.push(chunk.words.slice(at, at + n)); at += n; }
  const maxWidth = Math.min(box.w, Math.round(width * 0.82));
  const align = props.ratio === "16x9" ? "flex-start" : "center";
  return (
    <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: align, opacity: enter, overflow: "hidden" }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: align, maxWidth, textWrap: "balance", background: `rgba(${PLATE}, 0.86)`, borderRadius: Math.round(box.fontSize * 0.34), padding: `${Math.round(box.fontSize * 0.16)}px ${Math.round(box.fontSize * 0.42)}px` } as CSSProperties}>
        {rows.map((row, r) => (
          <div key={r} style={{ display: "flex", justifyContent: align, columnGap: box.fontSize * 0.4, lineHeight: 1.12 }}>
            {row.map((w, i) => {
              const key = w.word.toLowerCase().replace(/[^a-z0-9$%]/g, "");
              const active = t >= w.start - 0.04 && t < w.end + 0.04;
              const spoken = t >= w.start - 0.04;
              const em = emphasis.has(key);
              return (
                <CaptionWord_
                  key={`${r}-${i}-${w.word}`}
                  word={w.word}
                  bold={em || spoken}
                  opacity={spoken ? 1 : UNSPOKEN_OPACITY}
                  color={em ? props.brand.colors.emphasis ?? EMPHASIS_COLOR : "#ffffff"}
                  scale={active ? 1.03 : 1}
                  style={{ fontFamily: stack(props.brand.fontDisplay, props.brand.fontBody, "display"), fontSize: box.fontSize, letterSpacing: "-0.01em" }}
                />
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
};

export const MarketingAd: FC<MarketingAdProps> = (props) => {
  const { fps } = useVideoConfig();
  const { brand, layout } = props;
  const frames = beatFrames(props.beats, fps);
  return (
    <AbsoluteFill style={{ background: brand.colors.foreground }}>
      <FontLoader files={brand.fontFiles} />
      {props.beats.map((beat, i) => {
        const { from, durationInFrames: duration } = frames[i];
        return (
          <Sequence key={beat.id} from={from} durationInFrames={duration} name={beat.id}>
            {beat.kind === "ui" ? <UiCamera beat={beat} band={layout.uiBand} /> : null}
            {beat.kind === "broll" ? <BrollBeat beat={beat} band={layout.uiBand} colors={brand.colors} /> : null}
            {beat.kind === "title" ? <TitleBeat beat={beat} props={props} /> : null}
            {beat.kind === "card" ? <CardBeat beat={beat} props={props} /> : null}
          </Sequence>
        );
      })}
      <KineticCaptions props={props} />
    </AbsoluteFill>
  );
};
