// Screen stage: a captured product page filled edge to edge, a camera that springs toward the next action, a cursor drawn from the
// recorded pointer positions, and real motion blur on fast camera or cursor moves. Everything is a pure function of the plan
// (kit/screencast/stage-plan.mjs) and film time, through kit/screencast/stage-math.mjs, so the encoded-film gate can measure this
// render against the same plan. Contract: skills/studio/references/screen-stage.md.
import type { FC } from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
// @ts-ignore plain ES module shared with the node tools
import { CURSOR_SHAPES, STAGE, cameraSpeed, cursorHeightFor, projectPoint, stateAt } from "../screencast/stage-math.mjs";

export type ScreenStageProps = {
  plan: any;
  // Public-dir relative folder holding <clipId>/frames/*.jpg
  framesBase?: string;
  background?: string;
};

const Cursor: FC<{ plan: any; st: any }> = ({ plan, st }) => {
  const c = st.cursor;
  if (!c || c.visible <= 0 || c.hidden >= 1) return null;
  const g = plan.geometry;
  const p = projectPoint(st.camera, g, { x: c.x, y: c.y });
  if (plan.cursor.mode === "touch") return null;
  const shape = CURSOR_SHAPES[c.kind] || CURSOR_SHAPES.arrow;
  const sc = (cursorHeightFor(st.camera.z, g) / shape.height) * st.press;
  const alpha = c.visible * (1 - c.hidden);
  return (
    <svg
      width={g.W}
      height={g.H}
      style={{ position: "absolute", left: 0, top: 0, opacity: alpha, overflow: "visible", pointerEvents: "none", filter: "drop-shadow(0px 3px 5px rgba(0,0,0,0.38))" }}
    >
      <g transform={`translate(${p.x} ${p.y}) scale(${sc}) translate(${-shape.hot[0]} ${-shape.hot[1]})`}>
        <polygon
          points={shape.points.map((q: number[]) => q.join(",")).join(" ")}
          fill="#000"
          stroke="#fff"
          strokeWidth={1.7}
          strokeLinejoin="round"
          paintOrder="stroke fill"
        />
      </g>
    </svg>
  );
};

const Touch: FC<{ plan: any; st: any }> = ({ plan, st }) => {
  if (plan.cursor.mode !== "touch") return null;
  const g = plan.geometry;
  const nodes: any[] = [];
  for (const [i, tap] of plan.cursor.clicks.entries()) {
    const u = (st.t - tap.t) / 0.45;
    if (u < -0.02 || u > 1) continue;
    const p = projectPoint(st.camera, g, { x: tap.x, y: tap.y });
    const r = g.unit * (22 + 34 * Math.min(1, Math.max(0, u)));
    nodes.push(
      <circle key={`ring${i}`} cx={p.x} cy={p.y} r={r} fill="none" stroke="rgba(255,255,255,0.9)" strokeWidth={3 * g.unit} opacity={1 - Math.max(0, u)} />,
      <circle key={`dot${i}`} cx={p.x} cy={p.y} r={g.unit * 20 * (u < 0.25 ? 1 : 0.9)} fill="rgba(20,20,20,0.5)" stroke="rgba(255,255,255,0.85)" strokeWidth={2.5 * g.unit} opacity={u < 0.5 ? 1 : 1 - (u - 0.5) * 2} />,
    );
  }
  return (
    <svg width={g.W} height={g.H} style={{ position: "absolute", left: 0, top: 0, pointerEvents: "none" }}>
      {nodes}
    </svg>
  );
};

const Layer: FC<{ plan: any; t: number; framesBase: string }> = ({ plan, t, framesBase }) => {
  const st = stateAt(plan, t);
  const g = plan.geometry;
  const cam = st.camera;
  const transform = `translate(${g.W / 2 - cam.cx * cam.z}px, ${g.H / 2 - cam.cy * cam.z}px) scale(${cam.z})`;
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 0, top: 0, width: g.W, height: g.H, transformOrigin: "0 0", transform }}>
        {st.frame ? <Img src={staticFile([framesBase, st.frame].filter(Boolean).join("/"))} style={{ width: g.W, height: g.H, display: "block" }} /> : null}
      </div>
      <Cursor plan={plan} st={st} />
      <Touch plan={plan} st={st} />
    </AbsoluteFill>
  );
};

/** Sub-frame accumulation: the same stage at several times across the shutter, averaged. Only while something moves fast. */
export const ScreenStage: FC<ScreenStageProps> = ({ plan, framesBase = "" }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const st = stateAt(plan, t);
  const cursorScreenSpeed = st.cursor ? Math.hypot(st.cursor.vx, st.cursor.vy) * st.camera.z : 0;
  const moving = cameraSpeed(st.camera) > STAGE.blur.cameraSpeed || cursorScreenSpeed > STAGE.blur.cursorSpeed;
  const base = framesBase.replace(/\/$/, "");
  if (!moving) {
    return (
      <AbsoluteFill style={{ backgroundColor: "#000" }}>
        <Layer plan={plan} t={t} framesBase={base} />
      </AbsoluteFill>
    );
  }
  const n = STAGE.blur.samples;
  const shutter = STAGE.blur.shutterAngle / 360 / fps;
  return (
    <AbsoluteFill style={{ backgroundColor: "#000" }}>
      <AbsoluteFill style={{ isolation: "isolate" }}>
        {Array.from({ length: n }, (_, j) => (
          <AbsoluteFill key={j} style={{ mixBlendMode: "plus-lighter", filter: `opacity(${1 / n})` }}>
            <Layer plan={plan} t={Math.max(0, t + (j / (n - 1) - 0.5) * shutter)} framesBase={base} />
          </AbsoluteFill>
        ))}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
