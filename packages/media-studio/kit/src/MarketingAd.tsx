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
 * kit/marketing (layout.mjs, crop.mjs): the captured UI sits in a UI band inside the platform-safe area, cropped by a
 * focus-follow camera; kinetic captions, the persistent synthetic label and the CTA sit beside it. It renders the
 * picture only. Voice, effects and the ducked bed are mixed with FFmpeg (mix.mjs), so this file never plays audio.
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
    labelBox: Box & { fontSize: number };
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
  labelLines?: string[];
  disclosure?: string;
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
    uiBand: { x: 0, y: 0, w: 1920, h: 836 },
    captionBox: { x: 96, y: 852, w: 1728, h: 84, fontSize: 50, maxLines: 1 },
    labelBox: { x: 96, y: 946, w: 1000, h: 62, fontSize: 34 },
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
// Fade where the UI band meets the plate, so rows sliced by the crop do not end on a hard edge.
const BAND_FADE_PX = 32;
const PLATE = "15, 23, 42";
const EMPHASIS_COLOR = "#ffd166";

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
  const { fps, height } = useVideoConfig();
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
      {band.y > 0 ? <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: BAND_FADE_PX, background: `linear-gradient(to bottom, rgba(${PLATE}, 0.96), rgba(${PLATE}, 0))` }} /> : null}
      {band.y + band.h < height ? <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: BAND_FADE_PX, background: `linear-gradient(to top, rgba(${PLATE}, 0.96), rgba(${PLATE}, 0))` }} /> : null}
    </div>
  );
};

// Portrait ratios keep text inside the platform-safe area, which leaves wide bands above and below the UI. The same
// real clip, blurred and dimmed to a texture, fills them so the frame is not empty; nothing in it is legible, so it
// carries no claim of its own.
const UiBackdrop: FC<{ beat: AdBeat }> = ({ beat }) => {
  const { fps } = useVideoConfig();
  const clip = beat.clip;
  if (!clip) return null;
  const playFrames = Math.max(1, Math.round(clip.playSec * fps));
  const trimBefore = Math.round(clip.trimBeforeSec * fps);
  const style: CSSProperties = { width: "100%", height: "100%", objectFit: "cover", filter: "blur(34px) brightness(0.32) saturate(0.7)", transform: "scale(1.15)" };
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <Sequence durationInFrames={playFrames} layout="none">
        <OffthreadVideo src={staticFile(clip.src)} muted trimBefore={trimBefore} style={style} />
      </Sequence>
      <Sequence from={playFrames} layout="none">
        <Freeze frame={playFrames - 1}>
          <OffthreadVideo src={staticFile(clip.src)} muted trimBefore={trimBefore} style={style} />
        </Freeze>
      </Sequence>
      <AbsoluteFill style={{ background: "rgba(15, 23, 42, 0.85)" }} />
    </AbsoluteFill>
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

const CardBeat: FC<{ beat: AdBeat; props: MarketingAdProps }> = ({ beat, props }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { brand, layout, cta } = props;
  const rise = interpolate(frame, [0, 0.45 * fps], [28, 0], { extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  const fade = interpolate(frame, [0, 0.35 * fps], [0, 1], { extrapolateRight: "clamp" });
  const box = layout.ctaBox;
  const base = Math.round(Math.min(box.w, box.h) * 0.11);
  const pillFont = layout.ctaPillFont ?? Math.round(base * 0.5);
  // The end card carries the call to action; a different on-screen line (the claim the narration ends on) sits above it.
  const lead = beat.isCta && beat.headline && beat.headline !== cta.text ? beat.headline : null;
  return (
    <AbsoluteFill style={{ background: `linear-gradient(160deg, ${brand.colors.primary} 0%, ${brand.colors.foreground} 78%)` }}>
      <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "flex-start", gap: base * 0.45, opacity: fade, transform: `translateY(${rise}px)` }}>
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
  if (props.beats.some((b) => (b.kind === "card" || b.kind === "title") && t >= b.startSec && t < b.startSec + b.durationSec)) return null;
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
      <div style={{ display: "flex", flexDirection: "column", alignItems: align, maxWidth, textWrap: "balance" } as CSSProperties}>
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

const Label: FC<{ props: MarketingAdProps }> = ({ props }) => {
  const box = props.layout.labelBox;
  const lines = props.labelLines && props.labelLines.length ? props.labelLines : [props.label];
  return (
    <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", alignItems: "center", justifyContent: "center", border: "2px solid rgba(255,255,255,0.85)", borderRadius: 8, background: "rgba(15,23,42,0.92)", color: "#ffffff", fontFamily: stack(props.brand.fontDisplay, props.brand.fontBody, "body"), fontWeight: 600, fontSize: box.fontSize, letterSpacing: "0.05em", textTransform: "uppercase", whiteSpace: "nowrap", flexDirection: "column", lineHeight: 1.1 }}>
      {lines.map((l) => (
        <span key={l}>{l}</span>
      ))}
      {props.disclosure ? <span style={{ fontSize: box.fontSize * 0.7, opacity: 0.85, letterSpacing: "0.04em", textTransform: "none" }}>{props.disclosure}</span> : null}
    </div>
  );
};

export const MarketingAd: FC<MarketingAdProps> = (props) => {
  const { fps } = useVideoConfig();
  const { brand, layout } = props;
  const portrait = props.ratio !== "16x9";
  return (
    <AbsoluteFill style={{ background: brand.colors.foreground }}>
      <FontLoader files={brand.fontFiles} />
      {props.beats.map((beat) => {
        const from = Math.round(beat.startSec * fps);
        const duration = Math.max(1, Math.round(beat.durationSec * fps));
        return (
          <Sequence key={beat.id} from={from} durationInFrames={duration} name={beat.id}>
            {beat.kind === "ui" && portrait ? <UiBackdrop beat={beat} /> : null}
            {beat.kind === "ui" ? <UiCamera beat={beat} band={layout.uiBand} /> : null}
            {beat.kind === "broll" ? <BrollBeat beat={beat} band={layout.uiBand} colors={brand.colors} /> : null}
            {beat.kind === "card" || beat.kind === "title" ? <CardBeat beat={beat} props={props} /> : null}
          </Sequence>
        );
      })}
      <KineticCaptions props={props} />
      <Label props={props} />
    </AbsoluteFill>
  );
};
