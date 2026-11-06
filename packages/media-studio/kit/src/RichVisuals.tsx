/**
 * Picture types that are drawings, not words: a chart that grows from zero, a hand-drawn SVG scene whose
 * parts arrive on the spoken words, and Lottie motion. Added in 2.2.0 after a film shipped as "words
 * presented well". Each one is driven by useCurrentFrame() so the frame keeps moving while the line is spoken.
 *
 * `at` is seconds from scene start (the same clock the other visuals use), so a reveal can be pinned to the
 * word that names it.
 */
import type { FC } from "react";
import { useEffect, useState } from "react";
import { AbsoluteFill, Easing, Img, continueRender, delayRender, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Lottie, type LottieAnimationData } from "@remotion/lottie";

const SANS = 'Inter, "Segoe UI", system-ui, sans-serif';
const MONO = '"JetBrains Mono", "Cascadia Code", Consolas, ui-monospace, monospace';
const TONE = { default: "#E8E4D9", good: "#3DDC84", risk: "#E85D5D", emphasis: "#F5C518" } as const;
type Tone = keyof typeof TONE;

const ease = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const, easing: Easing.bezier(0.16, 1, 0.3, 1) };

const Heading: FC<{ text?: string; accent: string }> = ({ text, accent }) =>
  text ? (
    <div style={{ color: accent, fontFamily: SANS, fontSize: 22, fontWeight: 700, letterSpacing: "0.18em", marginBottom: 22 }}>
      {text.toUpperCase()}
    </div>
  ) : null;

/* ----------------------------------------------------------------- chart -- */

export type ChartVisual = {
  kind: "chart";
  caption?: string;
  /** bars: one bar per item on a shared zero-based scale. waffle: one percentage drawn as 100 squares. */
  form?: "bars" | "waffle";
  unit?: string;
  max?: number;
  items: { label: string; value: number; at?: number; mark?: Tone }[];
  /** waffle only: short lines that arrive beside the number on the words that name them. */
  notes?: { text: string; at?: number }[];
};

export const Chart: FC<{ v: ChartVisual; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (v.form === "waffle") {
    const pct = Math.max(0, Math.min(100, v.items[0]?.value ?? 0));
    const at = v.items[0]?.at ?? 0.4;
    const color = TONE[v.items[0]?.mark ?? "emphasis"];
    const filled = Math.round(interpolate(frame, [at * fps, (at + 1.6) * fps], [0, pct], ease));
    return (
      <div style={{ display: "flex", gap: 56, alignItems: "center" }}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(10, 34px)", gap: 6 }}>
          {Array.from({ length: 100 }, (_, i) => (
            <div key={i} style={{ width: 34, height: 34, borderRadius: 6, background: i < filled ? color : "#2A2A33" }} />
          ))}
        </div>
        <div>
          <Heading text={v.caption} accent={accent} />
          <div style={{ color, fontFamily: SANS, fontSize: 150, fontWeight: 900, lineHeight: 0.95 }}>{filled}%</div>
          <div style={{ color: "#EFEBE0", fontFamily: SANS, fontSize: 36, fontWeight: 700, marginTop: 10, maxWidth: 560 }}>{v.items[0]?.label}</div>
          <div style={{ marginTop: 26, display: "flex", flexDirection: "column", gap: 12 }}>
            {(v.notes ?? []).map((n, i) => {
              const nat = n.at ?? at + 1.2 + i * 1.4;
              const o = interpolate(frame, [nat * fps, (nat + 0.35) * fps], [0, 1], ease);
              const y = interpolate(frame, [nat * fps, (nat + 0.45) * fps], [12, 0], ease);
              return (
                <div key={i} style={{ opacity: o, transform: `translateY(${y}px)`, color: "#EFEBE0", fontFamily: SANS, fontSize: 32, fontWeight: 600 }}>
                  <span style={{ color }}>▸ </span>
                  {n.text}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    );
  }
  const top = v.max ?? Math.max(1, ...v.items.map((i) => i.value));
  const n = v.items.length;
  return (
    <div>
      <Heading text={v.caption} accent={accent} />
      <div style={{ display: "flex", flexDirection: "column", gap: 22 }}>
        {v.items.map((it, i) => {
          const at = it.at ?? 0.4 + (i * Math.max(0.5, d * 0.8 - 0.4)) / Math.max(1, n);
          const color = TONE[it.mark ?? "default"] === TONE.default ? accent : TONE[it.mark ?? "default"];
          const w = interpolate(frame, [at * fps, (at + 0.9) * fps], [0, (it.value / top) * 100], ease);
          const op = interpolate(frame, [at * fps, (at + 0.3) * fps], [0, 1], ease);
          return (
            <div key={i} style={{ opacity: op }}>
              <div style={{ color: "#EFEBE0", fontFamily: SANS, fontSize: 30, fontWeight: 700, marginBottom: 8 }}>{it.label}</div>
              <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
                <div style={{ height: 38, width: `${w}%`, background: color, borderRadius: 6, minWidth: w > 0 ? 6 : 0 }} />
                <div style={{ color, fontFamily: MONO, fontSize: 34, fontWeight: 700 }}>
                  {Math.round(interpolate(frame, [at * fps, (at + 0.9) * fps], [0, it.value], ease) * 10) / 10}
                  {v.unit ?? ""}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

/* ------------------------------------------------------------------- svg -- */

export type SvgVisual = {
  kind: "svg";
  caption?: string;
  viewBox?: string;
  /** Each group is a fragment of inline SVG (shapes, paths, text) that arrives at `at` seconds. */
  groups: { at?: number; svg: string }[];
};

export const SvgScene: FC<{ v: SvgVisual; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const n = v.groups.length;
  return (
    <div>
      <Heading text={v.caption} accent={accent} />
      <svg viewBox={v.viewBox ?? "0 0 1200 520"} style={{ width: "100%", height: "auto", maxHeight: 560 }} fontFamily={SANS}>
        {v.groups.map((g, i) => {
          const at = g.at ?? 0.4 + (i * Math.max(0.5, d * 0.8 - 0.4)) / Math.max(1, n);
          const a = at * fps;
          return (
            <g
              key={i}
              style={{
                opacity: interpolate(frame, [a, a + 0.35 * fps], [0, 1], ease),
                transform: `translateY(${interpolate(frame, [a, a + 0.45 * fps], [14, 0], ease)}px)`,
                ["--accent" as string]: accent,
              }}
              dangerouslySetInnerHTML={{ __html: g.svg }}
            />
          );
        })}
      </svg>
    </div>
  );
};

/* ---------------------------------------------------------------- lottie -- */

export type LottieVisual = {
  kind: "lottie";
  caption?: string;
  /** Path under public/, for example "lottie/check.json". */
  src: string;
  loop?: boolean;
  playbackRate?: number;
  /** Seconds from scene start when playback begins. */
  at?: number;
};

export const LottieScene: FC<{ v: LottieVisual; accent: string }> = ({ v, accent }) => {
  const { fps } = useVideoConfig();
  const frame = useCurrentFrame();
  const [data, setData] = useState<LottieAnimationData | null>(null);
  const [handle] = useState(() => delayRender(`lottie ${v.src}`));
  useEffect(() => {
    fetch(staticFile(v.src))
      .then((r) => r.json())
      .then((j) => {
        setData(j);
        continueRender(handle);
      })
      .catch(() => continueRender(handle));
  }, [v.src, handle]);
  const at = v.at ?? 0;
  return (
    <div>
      <Heading text={v.caption} accent={accent} />
      <div style={{ opacity: interpolate(frame, [at * fps, (at + 0.3) * fps], [0, 1], ease), height: 520 }}>
        {data ? <Lottie animationData={data} loop={v.loop ?? true} playbackRate={v.playbackRate ?? 1} style={{ width: "100%", height: "100%" }} /> : null}
      </div>
    </div>
  );
};

/* ---------------------------------------------------------------- photo -- */

export type PhotoFocus = "center" | "left" | "right" | "top" | "bottom";
const FOCUS_POSITION: Record<PhotoFocus, string> = {
  center: "50% 50%",
  left: "30% 50%",
  right: "70% 50%",
  top: "50% 30%",
  bottom: "50% 70%",
};
const FOCUS_DRIFT: Record<PhotoFocus, [number, number]> = {
  center: [0, 0],
  left: [-14, 0],
  right: [14, 0],
  top: [0, -10],
  bottom: [0, 10],
};

/**
 * A generated or captured photograph that owns the whole frame. The line is carried by the picture;
 * the title sits low on a gradient so the subject stays clear. A slow push and a small drift keep
 * the frame alive for as long as the voice is talking. Use for a place, an object or a mood that no
 * diagram can carry (skills/generate/references/stills.md). Text goes here, never inside the image.
 */
export const PhotoScene: FC<{
  src: string;
  title: string;
  kicker?: string;
  caption?: string;
  accent: string;
  durationSeconds: number;
  focus?: PhotoFocus;
  index?: number;
}> = ({ src, title, kicker, caption, accent, durationSeconds, focus = "center", index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const span = Math.max(1, durationSeconds * fps);
  const ease = Easing.bezier(0.16, 1, 0.3, 1);
  const [dx, dy] = FOCUS_DRIFT[focus];
  const push = interpolate(frame, [0, span], [1.0, 1.08], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.linear });
  const drift = interpolate(frame, [0, span], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.linear });
  const fade = (from: number, to: number) => interpolate(frame, [from * fps, to * fps], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  const rise = (from: number, to: number, px: number) => interpolate(frame, [from * fps, to * fps], [px, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  return (
    <AbsoluteFill style={{ backgroundColor: "#0B0B0B", fontFamily: 'Inter, "Segoe UI", system-ui, sans-serif' }}>
      <AbsoluteFill style={{ overflow: "hidden" }}>
        <Img
          src={staticFile(src)}
          style={{
            width: "100%",
            height: "100%",
            objectFit: "cover",
            objectPosition: FOCUS_POSITION[focus],
            opacity: fade(0, 0.5),
            scale: String(push),
            translate: `${dx * drift}px ${dy * drift}px`,
          }}
        />
      </AbsoluteFill>
      <AbsoluteFill
        style={{ background: "linear-gradient(to top, rgba(8,8,8,0.9) 0%, rgba(8,8,8,0.6) 26%, rgba(8,8,8,0.0) 56%)" }}
      />
      <AbsoluteFill style={{ justifyContent: "flex-end", padding: "0 110px 96px" }}>
        {kicker ? (
          <div
            style={{
              color: accent,
              letterSpacing: "0.28em",
              fontSize: 22,
              fontWeight: 700,
              marginBottom: 14,
              opacity: fade(0.2, 0.7),
              translate: `0px ${rise(0.2, 0.7, 10)}px`,
            }}
          >
            {kicker}
            {typeof index === "number" ? <span style={{ color: "#9A9588", marginLeft: 18 }}>{String(index + 1).padStart(2, "0")}</span> : null}
          </div>
        ) : null}
        <div
          style={{
            color: "#F3EFE4",
            fontSize: 64,
            fontWeight: 800,
            lineHeight: 1.08,
            maxWidth: "78%",
            textShadow: "0 2px 24px rgba(0,0,0,0.55)",
            opacity: fade(0.3, 0.9),
            translate: `0px ${rise(0.3, 0.9, 16)}px`,
          }}
        >
          {title}
        </div>
        {caption ? (
          <div
            style={{
              color: "#D8D3C4",
              fontSize: 28,
              marginTop: 14,
              maxWidth: "70%",
              opacity: fade(0.6, 1.2),
              translate: `0px ${rise(0.6, 1.2, 12)}px`,
            }}
          >
            {caption}
          </div>
        ) : null}
      </AbsoluteFill>
      <AbsoluteFill style={{ justifyContent: "flex-end" }}>
        <div style={{ height: 3, backgroundColor: "#FFFFFF10" }}>
          <div style={{ height: 3, backgroundColor: `${accent}AA`, width: `${drift * 100}%` }} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
