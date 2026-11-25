/**
 * A linked diagram: icon boxes on a grid, joined by arrows that name their ends
 * by id. kit/explainer/diagram.mjs places everything; this file only draws it.
 *
 * Every box is outlined from the first frame, so the shape of the idea is on
 * screen before the first word names a part of it. A box fills in on its own
 * word, the arrow into it draws just before, and the newest box carries the
 * light. One dot keeps running along the newest arrow while the line is spoken.
 */
import type { FC } from "react";
import { createElement, useId } from "react";
import { Interactive, useCurrentFrame, useVideoConfig } from "remotion";
import { ICONS, SLIDE_BOX, diagramLayout, flowAsDiagram, pointAlong } from "../explainer/diagram.mjs";
import { enter, progress } from "../explainer/motion.mjs";
import { edgeStart, phase } from "../explainer/reveal.mjs";

const SANS = 'Inter, "Segoe UI", system-ui, sans-serif';
const TONE = { default: "#E8E4D9", good: "#3DDC84", risk: "#E85D5D", emphasis: "#F5C518" } as const;
type Tone = keyof typeof TONE;

export type DiagramNode = {
  id: string;
  label: string;
  sub?: string;
  /** A name from kit/explainer/icons.json. */
  icon?: string;
  col?: number;
  row?: number;
  at?: number;
  mark?: Tone;
};

export type DiagramEdge = { from: string; to: string; label?: string; at?: number; dashed?: boolean };

export type DiagramVisual = { kind: "diagram"; caption?: string; nodes: DiagramNode[]; edges?: DiagramEdge[] };

type FlowLike = { kind: "flow"; caption?: string; nodes: { label: string; sub?: string; at?: number; mark?: Tone }[] };

type Point = { x: number; y: number };
type PlacedNode = {
  id: string; x: number; y: number; w: number; h: number;
  size: number; subSize: number; iconSize: number; iconGap: number; beside: boolean; lines: string[]; subLines: string[];
};
type PlacedEdge = {
  from: string; to: string; points: Point[]; length: number;
  label: { x: number; y: number; w: number; h: number; text: string; size: number } | null;
};
type Layout = { nodes: PlacedNode[]; edges: PlacedEdge[]; captionLines: string[] };
export type DiagramBox = { w: number; h: number };

const ARROW = 15;

/** One icon from the vendored set, drawn in `color`. */
export const Icon: FC<{ name: string; size: number; color: string }> = ({ name, size, color }) => {
  const parts = (ICONS as unknown as Record<string, [string, Record<string, string>][]>)[name];
  if (!parts) return null;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      {parts.map(([tag, attributes], i) => createElement(tag, { key: i, ...attributes }))}
    </svg>
  );
};

const pathOf = (points: Point[]) => points.map((p, i) => `${i ? "L" : "M"}${p.x} ${p.y}`).join(" ");

const headAngle = (points: Point[]) => {
  const tip = points[points.length - 1];
  const from = points[points.length - 2];
  return (Math.atan2(tip.y - from.y, tip.x - from.x) * 180) / Math.PI;
};

const Arrow: FC<{ edge: PlacedEdge; color: string; at: number; dashed?: boolean; live: boolean; id: string }> = ({
  edge, color, at, dashed, live, id,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = progress("draw", frame, fps, at);
  if (p <= 0) return null;
  const tip = edge.points[edge.points.length - 1];
  const d = pathOf(edge.points);
  const loop = live && p >= 1 ? ((frame / fps - at) % 1.8) / 1.8 : -1;
  const dot = loop >= 0 ? (pointAlong(edge.points, loop) as Point) : null;
  return (
    <g>
      {/* A mask draws the line on, so a dashed line keeps its dashes. */}
      <mask id={id} maskUnits="userSpaceOnUse">
        <path d={d} fill="none" stroke="#fff" strokeWidth={12} pathLength={1} strokeDasharray={1} strokeDashoffset={1 - p} />
      </mask>
      <path d={d} fill="none" stroke={color} strokeWidth={4} strokeLinejoin="round" strokeDasharray={dashed ? "4 12" : undefined} strokeLinecap="round" mask={`url(#${id})`} opacity={live ? 1 : 0.62} />
      <polygon
        points={`0,0 ${-ARROW},${-ARROW * 0.6} ${-ARROW},${ARROW * 0.6}`}
        fill={color}
        opacity={(live ? 1 : 0.62) * Math.max(0, (p - 0.7) / 0.3)}
        transform={`translate(${tip.x} ${tip.y}) rotate(${headAngle(edge.points)})`}
      />
      {dot ? <circle cx={dot.x} cy={dot.y} r={7} fill={color} opacity={Math.sin(Math.PI * loop)} /> : null}
    </g>
  );
};

export const Diagram: FC<{ v: DiagramVisual | FlowLike; accent: string; d: number; box?: DiagramBox; revealFrom?: number }> = ({
  v, accent, d, box = SLIDE_BOX, revealFrom = 0,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const uid = useId();
  const flow = v.kind === "flow" ? flowAsDiagram(v, box) : null;
  const diagram = (flow ? flow.diagram : v) as DiagramVisual;
  const layout = (flow ? flow.layout : diagramLayout(v, box)) as Layout;
  const edges = diagram.edges ?? [];
  const count = diagram.nodes.length;
  const starts = new Map(diagram.nodes.map((node, i) => [node.id, node.at ?? phase(i, count, d, revealFrom)]));
  const startOf = (id: string) => starts.get(id) ?? 0;
  const now = frame / fps;
  const landed = diagram.nodes.filter((node) => startOf(node.id) <= now);
  const newest = landed.reduce<string | null>((best, node) => (best === null || startOf(node.id) >= startOf(best) ? node.id : best), null);
  const edgeTimes = layout.edges.map((_, i) => edgeStart(edges[i], startOf) as number);
  const liveEdge = edgeTimes.reduce((best, at, i) => (at <= now && (best < 0 || at >= edgeTimes[best]) ? i : best), -1);

  return (
    <div style={{ position: "relative", width: box.w, height: box.h, fontFamily: SANS }}>
      {layout.captionLines.length ? (
        <div style={{ ...enter("fade", progress("fade", frame, fps, 0.1)), color: accent, fontSize: 22, fontWeight: 700, lineHeight: 1.5, letterSpacing: "0.18em", whiteSpace: "nowrap" }}>
          {layout.captionLines.map((line, i) => (
            <div key={i}>{line}</div>
          ))}
        </div>
      ) : null}
      <svg width={box.w} height={box.h} style={{ position: "absolute", left: 0, top: 0, overflow: "visible" }}>
        {layout.edges.map((edge, i) => (
          <Arrow key={i} id={`${uid}-arrow-${i}`} edge={edge} color={accent} at={edgeTimes[i]} dashed={edges[i].dashed} live={i === liveEdge} />
        ))}
      </svg>
      {layout.edges.map((edge, i) =>
        edge.label ? (
          <div
            key={`label-${i}`}
            style={{
              position: "absolute", left: edge.label.x, top: edge.label.y, width: edge.label.w, height: edge.label.h,
              display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 8, background: "#0B0B0B",
              color: "#E8E4D9", fontSize: edge.label.size, fontWeight: 600, whiteSpace: "nowrap",
              ...enter("fade", progress("fade", frame, fps, edgeTimes[i] + 0.25)),
            }}
          >
            {edge.label.text}
          </div>
        ) : null,
      )}
      {layout.nodes.map((node, i) => {
        const spec = diagram.nodes[i];
        const at = startOf(node.id);
        const p = progress("pop", frame, fps, at);
        const outline = progress("fade", frame, fps, 0.1);
        const lit = node.id === newest;
        const loud = spec.mark && spec.mark !== "default";
        const color = loud ? TONE[spec.mark as Tone] : accent;
        return (
          <div key={node.id}>
            <div
              style={{
                position: "absolute", left: node.x, top: node.y, width: node.w, height: node.h, boxSizing: "border-box",
                borderRadius: 16, border: "2px dashed #E8E4D938", opacity: outline * Math.max(0, 1 - p),
              }}
            />
            <Interactive.Div
              name={`Node ${spec.label}`}
              style={{
                position: "absolute", left: node.x, top: node.y, width: node.w, height: node.h, boxSizing: "border-box",
                display: "flex", flexDirection: node.beside ? "row" : "column", alignItems: "center", justifyContent: "center",
                gap: node.iconGap, borderRadius: 16, textAlign: node.beside && node.iconSize ? "left" : "center",
                border: `${lit ? 3 : 2}px solid ${lit || loud ? color : `${color}77`}`,
                background: loud ? `linear-gradient(180deg, ${color}26 0%, #141414 100%)` : "linear-gradient(180deg, #1B1B1B 0%, #121212 100%)",
                boxShadow: lit ? `0 0 46px ${color}38` : "0 14px 34px rgba(0,0,0,0.4)",
                ...enter("pop", p),
              }}
            >
              {spec.icon ? (
                <div style={{ height: node.iconSize, flexShrink: 0 }}>
                  <Icon name={spec.icon} size={node.iconSize} color={lit || loud ? color : "#C4BFAF"} />
                </div>
              ) : null}
              <div>
                {node.lines.map((line, k) => (
                  <div key={k} style={{ color: loud ? color : "#F3EFE4", fontSize: node.size, fontWeight: 700, lineHeight: 1.18, whiteSpace: "nowrap" }}>{line}</div>
                ))}
                {node.subLines.map((line, k) => (
                  <div key={`s${k}`} style={{ color: "#B7B2A4", fontSize: node.subSize, lineHeight: 1.25, marginTop: k ? 0 : Math.round(node.size * 0.2), whiteSpace: "nowrap" }}>{line}</div>
                ))}
              </div>
            </Interactive.Div>
          </div>
        );
      })}
    </div>
  );
};
