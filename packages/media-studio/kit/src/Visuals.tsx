/**
 * Richer scene bodies for the briefing kit.
 *
 * The bullets board answers "what are the points". It cannot show a policy,
 * a request path, or a number worth remembering. These do. Every one of them
 * is driven by useCurrentFrame() so the frame is still moving while a line is
 * being spoken — a code block that appears whole and then sits there is the
 * same frozen-slide failure the bullets board already fixed.
 *
 * Additive by construction: a scene with no `visual` never reaches this file.
 *
 * `revealFrom` continues one visual across consecutive scenes. Items before the
 * index are already on screen at full opacity; items from it onward animate in
 * across this scene. That is how a long answer keeps building one diagram
 * instead of holding a finished one — which is what a frozen-run measurement
 * correctly calls a still.
 */
import type { FC } from "react";
import { Easing, Img, Interactive, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";

const MONO = '"JetBrains Mono", "Cascadia Code", Consolas, ui-monospace, monospace';
const SANS = 'Inter, "Segoe UI", system-ui, sans-serif';

export type MarkTone = "default" | "good" | "risk" | "emphasis";

const MARK: Record<MarkTone, string> = {
  default: "#E8E4D9",
  good: "#3DDC84",
  risk: "#E85D5D",
  emphasis: "#F5C518",
};

export type CodeLine = { text: string; at?: number; mark?: MarkTone };

export type SplitSide = {
  title: string;
  mark?: MarkTone;
  items: { text: string; at?: number }[];
};

export type StackSide = {
  title: string;
  mark?: MarkTone;
  items: string[];
};

export type Visual = (
  | { kind: "code"; lang?: string; caption?: string; lines: CodeLine[] }
  | { kind: "flow"; caption?: string; nodes: { label: string; sub?: string; at?: number; mark?: MarkTone }[] }
  | { kind: "split"; left: SplitSide; right: SplitSide }
  | { kind: "stat"; value: string; label: string; sub?: string; mark?: MarkTone; at?: number }
  | { kind: "layers"; caption?: string; layers: { label: string; sub?: string; at?: number; mark?: MarkTone }[] }
  | { kind: "sequence"; caption?: string; actors: string[]; steps: SeqStep[] }
  | { kind: "table"; caption?: string; headers: string[]; rows: { cells: string[]; mark?: MarkTone }[] }
  | { kind: "timeline"; caption?: string; events: { at: string; label: string; sub?: string; mark?: MarkTone }[] }
  | { kind: "beforeafter"; caption?: string; before: StackSide; after: StackSide }
  | { kind: "map"; caption?: string; lanes: { name: string; mark?: MarkTone; nodes: { label: string; sub?: string }[] }[] }
  | { kind: "still"; src: string; caption?: string }
  | { kind: "broll"; src: string; caption?: string }
  | { kind: "quote"; text: string; attribution?: string }
  | { kind: "proof"; kicker?: string; claim: string; evidence: string }
  | { kind: "checklist"; caption?: string; items: { text: string; at?: number }[] }
  | { kind: "hero"; kicker?: string; title: string; sub?: string }
  | { kind: "cta"; kicker?: string; title: string; next: string }
  | { kind: "sidecar"; claim: string; support?: string }
  | { kind: "screen-in-context"; src: string; caption?: string }
) & { revealFrom?: number };

export type SeqStep = { frm: number; to: number; label: string; mark?: MarkTone };

/** Standard fade+rise. One easing everywhere so the program reads as one hand. */
const rise = (frame: number, fps: number, at: number, dy = 18) => {
  const a = at * fps;
  const o = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const, easing: Easing.bezier(0.16, 1, 0.3, 1) };
  return {
    opacity: interpolate(frame, [a, a + 0.34 * fps], [0, 1], o),
    translate: interpolate(frame, [a, a + 0.44 * fps], [`0px ${dy}px`, "0px 0px"], o),
  };
};

const Caption: FC<{ text?: string; accent: string }> = ({ text, accent }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (!text) return null;
  return (
    <div style={{ ...rise(frame, fps, 0.2, 10), color: accent, fontFamily: SANS, fontSize: 22, fontWeight: 700, letterSpacing: "0.18em", marginBottom: 22 }}>
      {text.toUpperCase()}
    </div>
  );
};

/* ------------------------------------------------------------------ code -- */

const Code: FC<{ v: Extract<Visual, { kind: "code" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div
        style={{
          border: `1px solid ${accent}33`,
          borderRadius: 10,
          background: "linear-gradient(180deg, #131313 0%, #0E0E0E 100%)",
          padding: "26px 30px",
          boxShadow: "0 24px 60px rgba(0,0,0,0.45)",
        }}
      >
        {v.lang ? (
          <div style={{ color: "#6E6A60", fontFamily: MONO, fontSize: 17, marginBottom: 14, letterSpacing: "0.1em" }}>
            {v.lang}
          </div>
        ) : null}
        {v.lines.map((line, i) => {
          const at = line.at ?? phase(i, v.lines.length, d, from);
          const st = rise(frame, fps, at, 8);
          const color = MARK[line.mark ?? "default"];
          const loud = line.mark && line.mark !== "default";
          return (
            <Interactive.Div
              key={i}
              name={`Code line ${i + 1}`}
              style={{
                display: "flex",
                gap: 18,
                alignItems: "baseline",
                ...st,
                // The marked line keeps a faint bar so the eye returns to it
                // after the rest of the block has landed.
                borderLeft: loud ? `3px solid ${color}` : "3px solid transparent",
                paddingLeft: 14,
                marginLeft: -17,
                background: loud ? `${color}0D` : "transparent",
              }}
            >
              <span style={{ color: "#4E4A44", fontFamily: MONO, fontSize: 19, minWidth: 26, textAlign: "right" }}>
                {i + 1}
              </span>
              <span
                style={{
                  color,
                  fontFamily: MONO,
                  fontSize: 26,
                  lineHeight: 1.62,
                  fontWeight: loud ? 700 : 400,
                  whiteSpace: "pre-wrap",
                }}
              >
                {line.text}
              </span>
            </Interactive.Div>
          );
        })}
      </div>
    </div>
  );
};

/* ------------------------------------------------------------------ flow -- */

const Flow: FC<{ v: Extract<Visual, { kind: "flow" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;

  // A flow node is a small box. Measured on a 14.1s five-node scene, one
  // appearing lifted whole-frame luma delta to ~1.1 against a 1.0 threshold,
  // and the 3s gaps between nodes read as frozen. So the node and its caption
  // land as two separate events — the diagram genuinely builds in more steps
  // rather than the frame merely being nudged harder.
  const stagger = Math.max(
    0.35,
    (revealAt(1, v.nodes.length, d) - revealAt(0, v.nodes.length, d)) * 0.45,
  );

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ display: "flex", alignItems: "stretch", gap: 0, flexWrap: "wrap" }}>
        {v.nodes.map((n, i) => {
          const at = n.at ?? phase(i, v.nodes.length, d, from);
          const color = MARK[n.mark ?? "default"];
          const loud = n.mark && n.mark !== "default";
          const a = at * fps;
          const o = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const, easing: Easing.bezier(0.16, 1, 0.3, 1) };
          return (
            <div key={i} style={{ display: "flex", alignItems: "center" }}>
              {i > 0 ? (
                <div
                  style={{
                    height: 2,
                    // Drawn over 0.9s rather than 0.22s. A flow node is a small
                    // box: measured, one appearing moved too few pixels to lift
                    // a whole-frame luma delta above the frozen threshold, so
                    // the connector has to do part of the work.
                    width: interpolate(frame, [a - 0.9 * fps, a], [0, 46], o),
                    background: `${accent}88`,
                    marginBottom: 26,
                  }}
                />
              ) : null}
              <Interactive.Div
                name={`Node ${i + 1}`}
                style={{
                  ...rise(frame, fps, at, 34),
                  scale: interpolate(frame, [a, a + 0.6 * fps], [0.86, 1], o),
                  border: `1.5px solid ${loud ? color : `${accent}55`}`,
                  background: loud ? `${color}14` : "#141414",
                  borderRadius: 10,
                  padding: "18px 22px",
                  minWidth: 168,
                  textAlign: "center",
                }}
              >
                <div style={{ color: loud ? color : "#EFEBE0", fontFamily: SANS, fontSize: 27, fontWeight: 700 }}>
                  {n.label}
                </div>
                {n.sub ? (
                  <div
                    style={{
                      ...rise(frame, fps, at < 0 ? at : at + stagger, 10),
                      color: "#918C80",
                      fontFamily: MONO,
                      fontSize: 18,
                      marginTop: 7,
                    }}
                  >
                    {n.sub}
                  </div>
                ) : null}
              </Interactive.Div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

/* ----------------------------------------------------------------- split -- */

const Split: FC<{ v: Extract<Visual, { kind: "split" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;
  const total = v.left.items.length + v.right.items.length;

  const side = (s: SplitSide, base: number, offset: number) => {
    const color = MARK[s.mark ?? "default"];
    return (
      <div
        style={{
          flex: 1,
          minHeight: 280,
          ...rise(frame, fps, offset === 0 ? base : Math.min(base, phase(offset, total, d, from)), 16),
          border: `1px solid ${color}55`,
          background: `${color}12`,
          borderRadius: 14,
          padding: "28px 30px",
        }}
      >
        <div style={{ color, fontFamily: SANS, fontSize: 34, fontWeight: 800, marginBottom: 22, letterSpacing: "0.04em" }}>{s.title}</div>
        {s.items.map((it, i) => (
          <div
            key={i}
            style={{
              ...rise(frame, fps, it.at ?? base + phase(offset + i, total, d * 0.8, from), 8),
              color: "#F3EFE4",
              fontFamily: SANS,
              fontSize: 28,
              fontWeight: 600,
              lineHeight: 1.65,
            }}
          >
            {it.text}
          </div>
        ))}
      </div>
    );
  };

  return (
    <div style={{ display: "flex", gap: 26, alignItems: "stretch" }}>
      {side(v.left, 0.4, 0)}
      {side(v.right, 0.7, v.left.items.length)}
    </div>
  );
};

/** Split a sentence into readable groups of roughly n words. */
const chunk = (text: string, n: number) => {
  const w = text.split(/\s+/).filter(Boolean);
  const out: string[] = [];
  for (let i = 0; i < w.length; i += n) out.push(w.slice(i, i + n).join(" "));
  return out;
};

/* ------------------------------------------------------------------ stat -- */

const Stat: FC<{ v: Extract<Visual, { kind: "stat" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;
  // The hero number is item 0 and the label item 1; the sub-sentence groups
  // follow. On a continuation scene the number is already up and only the
  // remaining clauses arrive.
  const at = v.at ?? (from > 0 ? -5 : 0.4);
  const color = MARK[v.mark ?? "emphasis"];
  const a = at * fps;
  const o = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const, easing: Easing.bezier(0.16, 1, 0.3, 1) };
  const parts = v.sub ? chunk(v.sub, 6) : [];

  return (
    <div style={{ display: "flex", alignItems: "baseline", gap: 34, flexWrap: "wrap" }}>
      <div
        style={{
          color,
          fontFamily: SANS,
          fontSize: v.value.length > 8 ? 92 : 168,
          fontWeight: 900,
          lineHeight: 0.92,
          letterSpacing: "-0.03em",
          opacity: interpolate(frame, [a, a + 0.3 * fps], [0, 1], o),
          scale: interpolate(frame, [a, a + 0.55 * fps], [0.9, 1], o),
        }}
      >
        {v.value}
      </div>
      <div style={{ ...rise(frame, fps, at + 0.35, 12) }}>
        <div style={{ color: "#EFEBE0", fontFamily: SANS, fontSize: 38, fontWeight: 700 }}>{v.label}</div>
        {v.sub ? (
          // Clause by clause across the scene rather than all at once. A hero
          // number lands in a second; the sentence explaining it is what the
          // remaining fifteen have to be doing.
          <div style={{ color: "#918C80", fontFamily: MONO, fontSize: 23, marginTop: 10, maxWidth: 700, lineHeight: 1.55 }}>
            {parts.map((part, i) => (
              <span
                key={i}
                style={{
                  ...rise(frame, fps, 0.8 + phase(i + 2, parts.length + 2, d * 0.82, from), 6),
                  display: "inline",
                }}
              >
                {part}{" "}
              </span>
            ))}
          </div>
        ) : null}
      </div>
    </div>
  );
};

/* ---------------------------------------------------------------- layers -- */

const Layers: FC<{ v: Extract<Visual, { kind: "layers" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {v.layers.map((l, i) => {
          const at = l.at ?? phase(i, v.layers.length, d, from);
          const color = MARK[l.mark ?? "default"];
          const a = at * fps;
          const o = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const, easing: Easing.bezier(0.16, 1, 0.3, 1) };
          return (
            <Interactive.Div
              key={i}
              name={`Layer ${i + 1}`}
              style={{
                ...rise(frame, fps, at, 12),
                display: "flex",
                alignItems: "center",
                gap: 22,
                border: `1px solid ${color}44`,
                background: `${color}0C`,
                borderRadius: 8,
                padding: "20px 26px",
                // Each layer slides out to its full width, so the stack builds
                // rather than appearing.
                width: interpolate(frame, [a, a + 0.5 * fps], ["62%", "100%"], o),
              }}
            >
              <div style={{ color, fontFamily: MONO, fontSize: 30, fontWeight: 800, minWidth: 46 }}>
                {String(i + 1).padStart(2, "0")}
              </div>
              <div>
                <div style={{ color: "#EFEBE0", fontFamily: SANS, fontSize: 29, fontWeight: 700 }}>{l.label}</div>
                {l.sub ? (
                  <div style={{ color: "#918C80", fontFamily: MONO, fontSize: 20, marginTop: 6 }}>{l.sub}</div>
                ) : null}
              </div>
            </Interactive.Div>
          );
        })}
      </div>
    </div>
  );
};

/* -------------------------------------------------------------- sequence -- */

/**
 * Lifelines with numbered messages. A request path described in prose costs the
 * viewer their whole working memory; the same path drawn costs them nothing and
 * frees the narration to explain *why* each step is in that order.
 */
const Sequence: FC<{ v: Extract<Visual, { kind: "sequence" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;
  const n = v.actors.length;
  const colW = 100 / n;

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ position: "relative" }}>
        {/* actor headers */}
        <div style={{ display: "flex" }}>
          {v.actors.map((a, i) => (
            <div
              key={i}
              style={{
                width: `${colW}%`,
                textAlign: "center",
                ...rise(frame, fps, 0.25 + i * 0.08, 8),
              }}
            >
              <div
                style={{
                  display: "inline-block",
                  border: `1.5px solid ${accent}66`,
                  background: "#151515",
                  borderRadius: 8,
                  padding: "10px 14px",
                  color: "#EFEBE0",
                  fontFamily: SANS,
                  fontSize: 21,
                  fontWeight: 700,
                }}
              >
                {a}
              </div>
            </div>
          ))}
        </div>

        {/* steps */}
        <div style={{ marginTop: 10 }}>
          {v.steps.map((s, i) => {
            const at = phase(i, v.steps.length, d, from);
            const color = MARK[s.mark ?? "default"];
            const self = s.frm === s.to;
            const lo = Math.min(s.frm, s.to);
            const hi = Math.max(s.frm, s.to);
            const left = self ? (s.frm + 0.5) * colW : (lo + 0.5) * colW;
            const width = self ? colW * 0.42 : (hi - lo) * colW;
            const back = s.to < s.frm;
            return (
              <div key={i} style={{ position: "relative", height: 46 }}>
                {/* lifelines pass through every row */}
                {v.actors.map((_, k) => (
                  <div
                    key={k}
                    style={{
                      position: "absolute",
                      left: `${(k + 0.5) * colW}%`,
                      top: 0,
                      bottom: 0,
                      width: 1,
                      background: "#2C2C2C",
                    }}
                  />
                ))}
                <div
                  style={{
                    position: "absolute",
                    left: `${left}%`,
                    width: `${width}%`,
                    top: 24,
                    ...rise(frame, fps, at, 6),
                  }}
                >
                  <div
                    style={{
                      height: 0,
                      borderTop: self ? `2px dashed ${color}` : `2px solid ${color}`,
                    }}
                  />
                  {/* The label is centred on the arrow but free to be wider
                      than it. Constraining it to the arrow width truncated
                      every message longer than one column — measured on the
                      first render, where four of eight steps ended in "…". */}
                  <div
                    style={{
                      position: "absolute",
                      top: -21,
                      left: "50%",
                      translate: "-50% 0",
                      color,
                      fontFamily: MONO,
                      fontSize: 17,
                      whiteSpace: "nowrap",
                      background: "#0B0B0BE6",
                      padding: "0 9px",
                      borderRadius: 4,
                    }}
                  >
                    {self ? "↻ " : back ? "◀ " : ""}{s.label}{self || back ? "" : " ▶"}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

/* ----------------------------------------------------------------- table -- */

const Table: FC<{ v: Extract<Visual, { kind: "table" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ border: `1px solid ${accent}33`, borderRadius: 10, overflow: "hidden" }}>
        <div
          style={{
            display: "flex",
            background: `${accent}18`,
            ...rise(frame, fps, 0.3, 6),
          }}
        >
          {v.headers.map((h, i) => (
            <div
              key={i}
              style={{
                flex: i === 0 ? 1.15 : 1,
                padding: "14px 20px",
                color: accent,
                fontFamily: SANS,
                fontSize: 20,
                fontWeight: 800,
                letterSpacing: "0.08em",
              }}
            >
              {h.toUpperCase()}
            </div>
          ))}
        </div>
        {v.rows.map((r, i) => {
          const at = phase(i, v.rows.length, d, from);
          const color = MARK[r.mark ?? "default"];
          const loud = r.mark && r.mark !== "default";
          return (
            <div
              key={i}
              style={{
                display: "flex",
                ...rise(frame, fps, at, 8),
                borderTop: "1px solid #232323",
                background: loud ? `${color}0C` : "transparent",
              }}
            >
              {r.cells.map((c, k) => (
                <div
                  key={k}
                  style={{
                    flex: k === 0 ? 1.15 : 1,
                    padding: "14px 20px",
                    color: k === 0 ? (loud ? color : "#EFEBE0") : "#B8B3A7",
                    fontFamily: k === 0 ? SANS : MONO,
                    fontSize: k === 0 ? 22 : 20,
                    fontWeight: k === 0 ? 700 : 400,
                    lineHeight: 1.4,
                  }}
                >
                  {c}
                </div>
              ))}
            </div>
          );
        })}
      </div>
    </div>
  );
};

/* -------------------------------------------------------------- timeline -- */

const Timeline: FC<{ v: Extract<Visual, { kind: "timeline" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;
  const o = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const, easing: Easing.bezier(0.16, 1, 0.3, 1) };

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ position: "relative" }}>
        {/* the spine draws itself down the scene */}
        <div
          style={{
            position: "absolute",
            left: 10,
            top: 6,
            width: 2,
            height: `${interpolate(frame, [0.3 * fps, Math.max(0.9, d * 0.7) * fps], [0, 100], o)}%`,
            background: `${accent}77`,
          }}
        />
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          {v.events.map((e, i) => {
            const at = phase(i, v.events.length, d, from);
            const color = MARK[e.mark ?? "default"];
            return (
              <div
                key={i}
                style={{
                  position: "relative",
                  paddingLeft: 42,
                  display: "flex",
                  alignItems: "baseline",
                  gap: 20,
                  ...rise(frame, fps, at, 10),
                }}
              >
                {/* In normal flow the row owns the gutter, so the marker cannot
                    land on top of the time label — which it did on the first
                    render, where every "t0" read as a filled circle. */}
                <div
                  style={{
                    position: "absolute",
                    left: 3,
                    top: 9,
                    width: 16,
                    height: 16,
                    borderRadius: 8,
                    background: color,
                  }}
                />
                <div
                  style={{
                    color,
                    fontFamily: MONO,
                    fontSize: 21,
                    fontWeight: 700,
                    minWidth: 116,
                  }}
                >
                  {e.at}
                </div>
                <div>
                  <div style={{ color: "#EFEBE0", fontFamily: SANS, fontSize: 27, fontWeight: 700 }}>{e.label}</div>
                  {e.sub ? (
                    <div style={{ color: "#918C80", fontFamily: MONO, fontSize: 19, marginTop: 4 }}>{e.sub}</div>
                  ) : null}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

/* ----------------------------------------------------------- beforeafter -- */

/**
 * Two stacked states with a delta between them. Distinct from `split`: split
 * contrasts two things that coexist, this contrasts the same thing at two
 * points in time, so it reads top-to-bottom with an arrow rather than
 * side-by-side.
 */
const BeforeAfter: FC<{ v: Extract<Visual, { kind: "beforeafter" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;
  const total = v.before.items.length + v.after.items.length;

  const stack = (s: StackSide, offset: number) => {
    const color = MARK[s.mark ?? "default"];
    return (
      <div
        style={{
          flex: 1,
          border: `1px solid ${color}44`,
          background: `${color}0A`,
          borderRadius: 10,
          padding: "20px 24px",
        }}
      >
        <div style={{ color, fontFamily: SANS, fontSize: 26, fontWeight: 800, marginBottom: 14 }}>{s.title}</div>
        {s.items.map((t, i) => (
          <div
            key={i}
            style={{
              ...rise(frame, fps, phase(offset + i, total, d, from), 8),
              color: "#DCD7CA",
              fontFamily: MONO,
              fontSize: 21,
              lineHeight: 1.65,
              display: "flex",
              gap: 10,
            }}
          >
            <span style={{ color: `${color}AA` }}>·</span>
            <span>{t}</span>
          </div>
        ))}
      </div>
    );
  };

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ display: "flex", alignItems: "stretch", gap: 18 }}>
        {stack(v.before, 0)}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            color: accent,
            fontFamily: SANS,
            fontSize: 40,
            fontWeight: 900,
            ...rise(frame, fps, 0.5, 0),
          }}
        >
          →
        </div>
        {stack(v.after, v.before.items.length)}
      </div>
    </div>
  );
};

/* ------------------------------------------------------------------- map -- */

/**
 * Grouped lanes. For topology that is a set of named things in categories —
 * thirteen services, twenty-four queues, eleven capability slots — where a flow
 * would imply an ordering that does not exist.
 */
const SystemMap: FC<{ v: Extract<Visual, { kind: "map" }>; accent: string; d: number }> = ({ v, accent, d }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;
  const total = v.lanes.reduce((n, l) => n + l.nodes.length, 0);
  let seen = 0;

  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {v.lanes.map((lane, li) => {
          const color = MARK[lane.mark ?? "default"];
          const base = seen;
          seen += lane.nodes.length;
          return (
            <div
              key={li}
              style={{
                border: `1px solid ${color}33`,
                background: `${color}08`,
                borderRadius: 10,
                padding: "14px 18px",
                ...rise(frame, fps, phase(base, total, d, from), 10),
              }}
            >
              <div
                style={{
                  color,
                  fontFamily: SANS,
                  fontSize: 18,
                  fontWeight: 800,
                  letterSpacing: "0.14em",
                  marginBottom: 10,
                }}
              >
                {lane.name}
              </div>
              <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
                {lane.nodes.map((nd, i) => (
                  <div
                    key={i}
                    style={{
                      ...rise(frame, fps, phase(base + i, total, d, from), 8),
                      border: `1px solid ${color}55`,
                      background: "#141414",
                      borderRadius: 7,
                      padding: "9px 14px",
                    }}
                  >
                    <div style={{ color: "#EFEBE0", fontFamily: MONO, fontSize: 21, fontWeight: 600 }}>
                      {nd.label}
                    </div>
                    {nd.sub ? (
                      <div style={{ color: "#8C8779", fontFamily: MONO, fontSize: 16, marginTop: 3 }}>{nd.sub}</div>
                    ) : null}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

const QuoteCard: FC<{ v: Extract<Visual, { kind: "quote" }>; accent: string; d: number }> = ({
  v,
  accent,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        ...rise(frame, fps, 0.2, 18),
        borderLeft: `6px solid ${accent}`,
        padding: "28px 36px",
        background: "#121212",
      }}
    >
      <div style={{ color: "#F3EFE4", fontFamily: SANS, fontSize: 48, fontWeight: 600, lineHeight: 1.25 }}>
        {v.text}
      </div>
      {v.attribution ? (
        <div style={{ color: accent, fontFamily: SANS, fontSize: 22, fontWeight: 700, marginTop: 22, letterSpacing: "0.12em" }}>
          {v.attribution}
        </div>
      ) : null}
    </div>
  );
};

const ProofCard: FC<{ v: Extract<Visual, { kind: "proof" }>; accent: string; d: number }> = ({
  v,
  accent,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div>
      {v.kicker ? <Caption text={v.kicker} accent={accent} /> : null}
      <div
        style={{
          ...rise(frame, fps, 0.25, 16),
          border: `1px solid ${accent}55`,
          background: `${accent}10`,
          borderRadius: 14,
          padding: "32px 36px",
        }}
      >
        <div style={{ color: "#F3EFE4", fontFamily: SANS, fontSize: 42, fontWeight: 800, lineHeight: 1.2 }}>{v.claim}</div>
        <div style={{ color: "#B7B2A4", fontFamily: MONO, fontSize: 24, marginTop: 18, lineHeight: 1.45 }}>{v.evidence}</div>
      </div>
    </div>
  );
};

const Checklist: FC<{ v: Extract<Visual, { kind: "checklist" }>; accent: string; d: number }> = ({
  v,
  accent,
  d,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = v.revealFrom ?? 0;
  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        {v.items.map((it, i) => {
          const at = it.at ?? phase(i, v.items.length, d, from);
          return (
            <div
              key={i}
              style={{
                ...rise(frame, fps, at, 10),
                display: "flex",
                gap: 18,
                alignItems: "center",
                color: "#F3EFE4",
                fontFamily: SANS,
                fontSize: 32,
                fontWeight: 600,
              }}
            >
              <span style={{ color: accent, fontSize: 28 }}>✓</span>
              <span>{it.text}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
};

const HeroCard: FC<{ v: Extract<Visual, { kind: "hero" }>; accent: string; d: number }> = ({
  v,
  accent,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ textAlign: "center", ...rise(frame, fps, 0.15, 20) }}>
      {v.kicker ? (
        <div style={{ color: accent, letterSpacing: "0.32em", fontWeight: 700, fontSize: 22, marginBottom: 22 }}>{v.kicker}</div>
      ) : null}
      <div style={{ color: "#F3EFE4", fontFamily: SANS, fontSize: 72, fontWeight: 800, lineHeight: 1.08 }}>{v.title}</div>
      {v.sub ? (
        <div style={{ color: "#B7B2A4", fontFamily: SANS, fontSize: 28, marginTop: 24 }}>{v.sub}</div>
      ) : null}
    </div>
  );
};

const CtaCard: FC<{ v: Extract<Visual, { kind: "cta" }>; accent: string; d: number }> = ({
  v,
  accent,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ textAlign: "center", ...rise(frame, fps, 0.2, 16) }}>
      {v.kicker ? (
        <div style={{ color: "#9A9588", letterSpacing: "0.28em", fontWeight: 700, fontSize: 20, marginBottom: 18 }}>{v.kicker}</div>
      ) : null}
      <div style={{ color: "#F3EFE4", fontFamily: SANS, fontSize: 56, fontWeight: 800 }}>{v.title}</div>
      <div
        style={{
          marginTop: 36,
          display: "inline-block",
          border: `1px solid ${accent}`,
          color: accent,
          fontFamily: SANS,
          fontSize: 28,
          fontWeight: 700,
          padding: "14px 28px",
          borderRadius: 8,
        }}
      >
        {v.next}
      </div>
    </div>
  );
};

const Sidecar: FC<{ v: Extract<Visual, { kind: "sidecar" }>; accent: string; d: number }> = ({
  v,
  accent,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ display: "flex", gap: 36, alignItems: "center", ...rise(frame, fps, 0.2, 14) }}>
      <div
        style={{
          width: 280,
          height: 360,
          borderRadius: 16,
          background: "#161616",
          border: `1px solid ${accent}33`,
        }}
      />
      <div>
        <div style={{ color: "#F3EFE4", fontFamily: SANS, fontSize: 40, fontWeight: 800, lineHeight: 1.2 }}>{v.claim}</div>
        {v.support ? (
          <div style={{ color: "#B7B2A4", fontFamily: SANS, fontSize: 24, marginTop: 16 }}>{v.support}</div>
        ) : null}
      </div>
    </div>
  );
};

const Broll: FC<{ v: Extract<Visual, { kind: "broll" | "screen-in-context" }>; accent: string; d: number }> = ({
  v,
  accent,
  d,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const span = Math.max(1, d * fps);
  const framed = v.kind === "screen-in-context";
  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div
        style={{
          height: framed ? 520 : 560,
          overflow: "hidden",
          borderRadius: framed ? 16 : 0,
          border: framed ? `1px solid ${accent}44` : "none",
          boxShadow: framed ? "0 24px 60px rgba(0,0,0,0.45)" : "none",
        }}
      >
        <Img
          src={staticFile(v.src)}
          style={{
            width: "100%",
            height: "100%",
            objectFit: "cover",
            opacity: interpolate(frame, [0, 0.35 * fps], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            }),
            scale: interpolate(frame, [0, span], [1, 1.06], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.linear,
            }),
          }}
        />
      </div>
    </div>
  );
};

const Still: FC<{ v: Extract<Visual, { kind: "still" }>; accent: string; d: number }> = ({
  v,
  accent,
  d,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const span = Math.max(1, d * fps);
  return (
    <div>
      <Caption text={v.caption} accent={accent} />
      <div
        style={{
          height: 500,
          overflow: "hidden",
          borderRadius: 12,
          border: `1px solid ${accent}33`,
          boxShadow: "0 24px 60px rgba(0,0,0,0.45)",
        }}
      >
        <Img
          src={staticFile(v.src)}
          style={{
            width: "100%",
            height: "100%",
            objectFit: "cover",
            opacity: interpolate(frame, [0, 0.35 * fps], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            }),
            scale: interpolate(frame, [0, span], [1, 1.05], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.linear,
            }),
          }}
        />
      </div>
    </div>
  );
};

/* ---------------------------------------------------------------- export -- */

/**
 * Spread n default reveals across the part of the scene that is still being
 * narrated. A 28-second code block that finished appearing at 4s spent 24
 * seconds frozen — the exact defect `atSeconds` was added to the bullet board
 * to cure. `step` is derived from the scene length rather than fixed, so the
 * picture keeps arriving for as long as the voice keeps talking.
 */
export const revealAt = (i: number, n: number, durationSeconds: number) => {
  const start = 0.45;
  // 0.88, not 0.66. Measured: a five-node flow on a 14.1s scene finished its
  // last reveal at 9.3s and then held for 5.0s, which the frozen-run detector
  // called a still — correctly. The reveals have to keep arriving for as long
  // as the voice is talking, not for two-thirds of it.
  const window = Math.max(1.2, durationSeconds * 0.88 - start);
  // Cap raised from 1.9s: on a 33s scene with four items the old cap finished
  // every reveal by ~7s and left 26s of imperceptible creep, which a frozen-run
  // measurement correctly called a held still.
  const step = n > 1 ? Math.min(5.0, Math.max(0.3, window / (n - 1))) : 0;
  return start + i * step;
};

/**
 * Reveal time for item `i` of `n`, where the first `from` items are carried
 * over from the previous scene and are already on screen. A negative time means
 * "was already visible", which `rise` clamps to full opacity at frame 0.
 */
export const phase = (i: number, n: number, durationSeconds: number, from = 0) => {
  if (from <= 0) return revealAt(i, n, durationSeconds);
  if (i < from) return -5;
  return revealAt(i - from, Math.max(1, n - from), durationSeconds);
};

export const VisualBody: FC<{
  visual: Visual;
  accent: string;
  durationSeconds?: number;
}> = ({ visual, accent, durationSeconds = 8 }) => {
  const d = durationSeconds;
  switch (visual.kind) {
    case "code":
      return <Code v={visual} accent={accent} d={d} />;
    case "flow":
      return <Flow v={visual} accent={accent} d={d} />;
    case "split":
      return <Split v={visual} accent={accent} d={d} />;
    case "stat":
      return <Stat v={visual} accent={accent} d={d} />;
    case "layers":
      return <Layers v={visual} accent={accent} d={d} />;
    case "sequence":
      return <Sequence v={visual} accent={accent} d={d} />;
    case "table":
      return <Table v={visual} accent={accent} d={d} />;
    case "timeline":
      return <Timeline v={visual} accent={accent} d={d} />;
    case "beforeafter":
      return <BeforeAfter v={visual} accent={accent} d={d} />;
    case "map":
      return <SystemMap v={visual} accent={accent} d={d} />;
    case "still":
      return <Still v={visual} accent={accent} d={d} />;
    case "broll":
    case "screen-in-context":
      return <Broll v={visual} accent={accent} d={d} />;
    case "quote":
      return <QuoteCard v={visual} accent={accent} d={d} />;
    case "proof":
      return <ProofCard v={visual} accent={accent} d={d} />;
    case "checklist":
      return <Checklist v={visual} accent={accent} d={d} />;
    case "hero":
      return <HeroCard v={visual} accent={accent} d={d} />;
    case "cta":
      return <CtaCard v={visual} accent={accent} d={d} />;
    case "sidecar":
      return <Sidecar v={visual} accent={accent} d={d} />;
    default:
      return null;
  }
};
