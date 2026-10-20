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
export type CaptionChunk = { startSec: number; endSec: number; words: CaptionWord[] };

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
    uiBand: { x: 0, y: 0, w: 1920, h: 896 },
    captionBox: { x: 96, y: 908, w: 1728, h: 90, fontSize: 50, maxLines: 1 },
    labelBox: { x: 96, y: 1008, w: 780, h: 52, fontSize: 24 },
    ctaBox: { x: 116, y: 190, w: 1688, h: 600 },
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
  return (
    <AbsoluteFill style={{ background: `linear-gradient(160deg, ${brand.colors.primary} 0%, ${brand.colors.foreground} 78%)` }}>
      <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", flexDirection: "column", justifyContent: "center", gap: base * 0.5, opacity: fade, transform: `translateY(${rise}px)` }}>
        <div style={{ fontFamily: stack(brand.fontDisplay, brand.fontBody, "display"), fontSize: base * 0.55, letterSpacing: "0.12em", textTransform: "uppercase", color: "rgba(255,255,255,0.78)" }}>{brand.productName}</div>
        <div style={{ fontFamily: stack(brand.fontDisplay, brand.fontBody, "display"), fontSize: base, fontWeight: 600, lineHeight: 1.08, letterSpacing: "-0.02em", color: brand.colors.onPrimary }}>
          {beat.isCta ? cta.text : beat.headline}
        </div>
        {beat.isCta ? (
          <div style={{ alignSelf: "flex-start", marginTop: base * 0.35, padding: `${base * 0.22}px ${base * 0.5}px`, borderRadius: 999, background: brand.colors.accent, color: "#0f172a", fontFamily: stack(brand.fontDisplay, brand.fontBody, "display"), fontWeight: 600, fontSize: base * 0.62 }}>
            {cta.displayUrl}
          </div>
        ) : null}
      </div>
    </AbsoluteFill>
  );
};

const KineticCaptions: FC<{ props: MarketingAdProps }> = ({ props }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const chunk = props.captions.find((c) => t >= c.startSec && t < c.endSec);
  const box = props.layout.captionBox;
  if (!chunk) return null;
  const emphasis = new Set(props.emphasis.map((w) => w.toLowerCase().replace(/[^a-z0-9$%]/g, "")));
  const enter = interpolate(t, [chunk.startSec, chunk.startSec + 0.18], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", alignItems: "center", justifyContent: props.ratio === "16x9" ? "flex-start" : "center", flexWrap: "wrap", alignContent: "center", columnGap: box.fontSize * 0.4, rowGap: box.fontSize * 0.08, opacity: enter, overflow: "hidden", textAlign: "center" }}>
      {chunk.words.map((w, i) => {
        const key = w.word.toLowerCase().replace(/[^a-z0-9$%]/g, "");
        const active = t >= w.start - 0.04 && t < w.end + 0.04;
        const spoken = t >= w.start - 0.04;
        const color = emphasis.has(key) ? props.brand.colors.emphasis ?? EMPHASIS_COLOR : "#ffffff";
        const wordStyle: CSSProperties = {
          fontFamily: stack(props.brand.fontDisplay, props.brand.fontBody, "display"),
          fontSize: box.fontSize,
          lineHeight: 1.12,
          letterSpacing: "-0.01em",
          color,
          opacity: spoken ? 1 : UNSPOKEN_OPACITY,
          fontWeight: emphasis.has(key) ? 700 : 600,
          // The spoken word lifts slightly; the gap above is wider than its growth, so neighbours never touch. No
          // underline: on a product film an underlined word reads as a link.
          transform: active ? "scale(1.03)" : "scale(1)",
          transformOrigin: "50% 60%",
          textShadow: "0 2px 10px rgba(15,23,42,0.55)",
        };
        return (
          <span key={`${i}-${w.word}`} style={wordStyle}>
            {w.word}
          </span>
        );
      })}
    </div>
  );
};

const Label: FC<{ props: MarketingAdProps }> = ({ props }) => {
  const box = props.layout.labelBox;
  return (
    <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, display: "flex", alignItems: "center", justifyContent: "center", border: "2px solid rgba(255,255,255,0.85)", borderRadius: 8, background: "rgba(15,23,42,0.92)", color: "#ffffff", fontFamily: stack(props.brand.fontDisplay, props.brand.fontBody, "body"), fontWeight: 600, fontSize: box.fontSize, letterSpacing: "0.05em", textTransform: "uppercase", whiteSpace: "nowrap", flexDirection: "column", lineHeight: 1.1 }}>
      <span>{props.label}</span>
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
