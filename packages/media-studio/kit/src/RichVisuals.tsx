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
import { Easing, continueRender, delayRender, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
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
