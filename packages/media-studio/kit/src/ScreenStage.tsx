// Screen stage: a captured product page filled edge to edge, a camera that springs toward the next action, a cursor drawn from the
// recorded pointer positions, and real motion blur on fast camera or cursor moves. Everything is a pure function of the plan
// (kit/screencast/stage-plan.mjs) and film time, through kit/screencast/stage-math.mjs, so the encoded-film gate can measure this
// render against the same plan. Contract: skills/studio/references/screen-stage.md.
//
// One WebGL2 pass per frame. The page frame is an sRGB texture (the GPU linearises it), every output pixel averages N jittered
// samples taken at times spread across the shutter (camera at each time), in float and in LINEAR light, then converts back to sRGB
// once. The cursor is blurred separately: its own samples at its own on-screen positions, composited over the page in linear light.
// A still view uses a fixed 4x4 box filter for anti-aliasing only, so a hold is exactly the same picture every frame.
import { useEffect, useMemo, useRef } from "react";
import type { FC } from "react";
import { AbsoluteFill, cancelRender, continueRender, delayRender, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
// @ts-ignore plain ES module shared with the node tools
import { CURSOR_SHAPES, STAGE, buildCursorTrack, cameraAt, cursorAt, cursorHeightFor, pressScale, projectPoint, stateAt } from "../screencast/stage-math.mjs";

export type ScreenStageProps = {
  plan: any;
  // Public-dir relative folder holding <clipId>/frames/*.jpg
  framesBase?: string;
  background?: string;
};

const MAX_N = 64;
const MAX_POLY = 32;

const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
uniform sampler2D uTex;
uniform vec2 uStage;
uniform int uN;
uniform int uMoving;
uniform vec4 uCam[${MAX_N}];
uniform int uNc;
uniform vec4 uCur[${MAX_N}];
uniform vec2 uPoly[${MAX_POLY}];
uniform int uPolyN;
uniform vec2 uHot;
uniform vec4 uCurBox;
uniform float uUnit;
uniform float uSeed;
uniform vec4 uHi;      // highlight cutout: centre x, centre y, half width, half height (screen px)
uniform vec2 uHiAmt;   // dim amount, outline amount
uniform float uHiOutline;
uniform vec4 uPlace;    // a phone screen inside a wide frame: x, y, w, h (stage px); w = 0 means full bleed
uniform float uRadius;
uniform vec3 uBg0;
uniform vec3 uBg1;
uniform vec2 uBgDir;
out vec4 outColor;

float sdRound(vec2 q, vec2 half_, float r) { vec2 d = abs(q) - half_ + vec2(r); return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r; }
vec3 backdrop(vec2 p) {
  vec2 n = p / uStage - 0.5;
  float t = clamp(dot(n, uBgDir) + 0.5, 0.0, 1.0);
  vec3 c = mix(uBg0, uBg1, t * t * (3.0 - 2.0 * t));
  c *= 1.0 - 0.25 * pow(clamp(length(n) * 1.4, 0.0, 1.0), 2.0);
  vec2 ctr = uPlace.xy + 0.5 * uPlace.zw;
  float ds = sdRound(p - ctr - vec2(0.0, 22.0 * uUnit), 0.5 * uPlace.zw, uRadius);
  return c * (1.0 - 0.38 * (1.0 - smoothstep(-8.0 * uUnit, 70.0 * uUnit, ds)));
}

float h12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec3 toSrgb(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

float polySD(vec2 q) {
  float d = 1e9; bool inside = false;
  for (int i = 0; i < ${MAX_POLY}; i++) {
    if (i >= uPolyN) break;
    vec2 a = uPoly[i]; vec2 b = uPoly[(i + 1) % uPolyN];
    vec2 e = b - a; vec2 w = q - a;
    float t = clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, length(w - e * t));
    if ((a.y > q.y) != (b.y > q.y) && q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside ? -d : d;
}

void main() {
  vec2 s0 = vec2(gl_FragCoord.x, uStage.y - gl_FragCoord.y);
  vec2 rnd = vec2(h12(gl_FragCoord.xy + uSeed), h12(gl_FragCoord.yx * 1.7 + uSeed * 3.1));
  vec3 acc = vec3(0.0);
  for (int j = 0; j < ${MAX_N}; j++) {
    if (j >= uN) break;
    vec2 jit;
    if (uMoving == 0) jit = vec2((float(j - (j / 4) * 4) + 0.5) / 4.0, (float(j / 4) + 0.5) / 4.0) - 0.5;
    else jit = fract(vec2(0.7548776662, 0.5698402910) * float(j + 1) + rnd) - 0.5;
    vec4 c = uCam[j];
    vec2 p = (s0 + jit - 0.5 * uStage) / c.z + c.xy;
    if (uPlace.z > 0.0) {
      vec2 ctr = uPlace.xy + 0.5 * uPlace.zw;
      float d = sdRound(p - ctr, 0.5 * uPlace.zw, uRadius);
      float m = 1.0 - smoothstep(-0.5 / c.z, 0.5 / c.z, d);
      acc += mix(backdrop(p), texture(uTex, (p - uPlace.xy) / uPlace.zw).rgb, m);
    } else acc += texture(uTex, p / uStage).rgb;
  }
  vec3 page = acc / float(uN);

  float ca = 0.0; vec3 cc = vec3(0.0);
  if (uNc > 0 && s0.x >= uCurBox.x && s0.x <= uCurBox.z && s0.y >= uCurBox.y && s0.y <= uCurBox.w) {
    for (int k = 0; k < ${MAX_N}; k++) {
      if (k >= uNc) break;
      vec4 u = uCur[k];
      if (u.w <= 0.0) continue;
      vec2 q = (s0 - u.xy) / u.z + uHot;
      float sd = polySD(q) * u.z;
      float fill = clamp(0.5 - sd, 0.0, 1.0);
      float wh = clamp(0.5 - (sd - 0.85 * u.z), 0.0, 1.0);
      float sdS = polySD((s0 - vec2(0.0, 3.0 * uUnit) - u.xy) / u.z + uHot) * u.z;
      float sa = 0.38 * (1.0 - smoothstep(-2.5 * uUnit, 5.0 * uUnit, sdS));
      float a = fill + wh * (1.0 - fill);
      ca += (a + sa * (1.0 - a)) * u.w;
      cc += vec3(wh * (1.0 - fill)) * u.w;
    }
    ca /= float(uNc); cc /= float(uNc);
  }
  // The one highlight: the page outside a rounded cutout is dimmed, a thin outline runs round the cutout. Eased by the plan.
  if (uHiAmt.x > 0.0) {
    vec2 q = abs(s0 - uHi.xy) - uHi.zw + vec2(8.0 * uUnit);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 8.0 * uUnit;
    float outside = smoothstep(-0.5, 0.5, d);
    page *= 1.0 - uHiAmt.x * outside;
    float ring = (1.0 - smoothstep(0.0, 1.0, abs(d) - 0.5 * uHiOutline)) * uHiAmt.y;
    page = mix(page, vec3(1.0), ring * 0.9);
  }
  vec3 lin = page * (1.0 - ca) + cc;
  vec3 srgb = toSrgb(lin);
  if (uMoving == 1) srgb += (h12(gl_FragCoord.xy * 0.91 + uSeed * 7.0) - 0.5) / 255.0;
  outColor = vec4(srgb, 1.0);
}`;

type GL = {
  gl: WebGL2RenderingContext;
  prog: WebGLProgram;
  u: Record<string, WebGLUniformLocation | null>;
  tex: Map<string, WebGLTexture>;
  order: string[];
};

function compile(gl: WebGL2RenderingContext, type: number, src: string) {
  const s = gl.createShader(type)!;
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(`screen stage shader: ${gl.getShaderInfoLog(s)}`);
  return s;
}

function makeGL(canvas: HTMLCanvasElement): GL {
  const gl = canvas.getContext("webgl2", { alpha: false, antialias: false, preserveDrawingBuffer: true, premultipliedAlpha: false, powerPreference: "high-performance" }) as WebGL2RenderingContext | null;
  if (!gl) throw new Error("screen stage: WebGL2 is not available (render with --gl=swangle on a box with no GPU)");
  const prog = gl.createProgram()!;
  gl.attachShader(prog, compile(gl, gl.VERTEX_SHADER, VERT));
  gl.attachShader(prog, compile(gl, gl.FRAGMENT_SHADER, FRAG));
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(`screen stage program: ${gl.getProgramInfoLog(prog)}`);
  gl.useProgram(prog);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(prog, "aPos");
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  const names = ["uTex", "uStage", "uN", "uMoving", "uCam", "uNc", "uCur", "uPoly", "uPolyN", "uHot", "uCurBox", "uUnit", "uSeed", "uHi", "uHiAmt", "uHiOutline", "uPlace", "uRadius", "uBg0", "uBg1", "uBgDir"];
  const u: Record<string, WebGLUniformLocation | null> = {};
  for (const n of names) u[n] = gl.getUniformLocation(prog, n);
  return { gl, prog, u, tex: new Map(), order: [] };
}

async function loadTexture(G: GL, url: string): Promise<WebGLTexture> {
  const hit = G.tex.get(url);
  if (hit) return hit;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`screen stage: frame ${url} -> HTTP ${res.status}`);
  // No colour conversion: the texture holds the JPEG's own values and the GPU linearises them as sRGB.
  const bmp = await createImageBitmap(await res.blob(), { colorSpaceConversion: "none", premultiplyAlpha: "none", imageOrientation: "none" });
  const { gl } = G;
  const tex = gl.createTexture()!;
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.SRGB8_ALPHA8, gl.RGBA, gl.UNSIGNED_BYTE, bmp as any);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  bmp.close();
  G.tex.set(url, tex);
  G.order.push(url);
  while (G.order.length > 3) { const old = G.order.shift()!; gl.deleteTexture(G.tex.get(old)!); G.tex.delete(old); }
  return tex;
}

/** Largest on-screen displacement, in px, of any point of the view between two camera states: the blur length. */
function blurPx(c0: any, c1: any, g: any) {
  const pts = [[0, 0], [g.W, 0], [0, g.H], [g.W, g.H], [g.W / 2, g.H / 2]];
  let m = 0;
  for (const [sx, sy] of pts) {
    const px = (sx - g.W / 2) / c1.z + c1.cx, py = (sy - g.H / 2) / c1.z + c1.cy; // stage point under the middle camera
    const ax = (px - c0.cx) * c0.z, ay = (py - c0.cy) * c0.z, bx = (px - c1.cx) * c1.z, by = (py - c1.cy) * c1.z;
    m = Math.max(m, Math.hypot(ax - bx, ay - by));
  }
  return m;
}

/** Everything the shader needs for one film frame: page samples, cursor samples, and whether anything moves. */
function frameSetup(plan: any, track: any, t: number, fps: number) {
  const g = plan.geometry;
  const shutter = (STAGE.blur.shutterAngle / 360) / fps;
  const tA = Math.max(0, t - shutter / 2), tB = t + shutter / 2;
  const st = stateAt(plan, t);
  const cA = cameraAt(plan.camera, tA, g), cB = cameraAt(plan.camera, tB, g);
  const pageBlur = blurPx(cA, cB, g);
  const hasCursor = plan.cursor.mode !== "touch" && plan.cursor.samples.length > 0;
  let curBlur = 0;
  if (hasCursor) {
    const a = cursorAt(track, tA, plan.cursor.hidden), b = cursorAt(track, tB, plan.cursor.hidden);
    const pa = projectPoint(cA, g, a), pb = projectPoint(cB, g, b);
    curBlur = Math.hypot(pa.x - pb.x, pa.y - pb.y);
  }
  const moving = pageBlur > STAGE.blur.minPx;
  const N = moving ? Math.min(MAX_N, Math.max(32, Math.ceil(pageBlur * 2))) : 16;
  const cam = new Float32Array(MAX_N * 4);
  for (let j = 0; j < N; j++) {
    const tj = moving ? Math.max(0, t + ((j + 0.5) / N - 0.5) * shutter) : t;
    const c = moving ? cameraAt(plan.camera, tj, g) : st.camera;
    cam[j * 4] = c.cx; cam[j * 4 + 1] = c.cy; cam[j * 4 + 2] = c.z;
  }
  const kind = st.cursor?.kind || "arrow";
  const shape = (CURSOR_SHAPES as any)[kind] || CURSOR_SHAPES.arrow;
  const Nc = hasCursor ? (curBlur > STAGE.blur.minPx ? Math.min(MAX_N, Math.max(24, Math.ceil(curBlur * 2))) : 1) : 0;
  const cur = new Float32Array(MAX_N * 4);
  let box = [1e9, 1e9, -1e9, -1e9];
  for (let k = 0; k < Nc; k++) {
    const tk = Nc > 1 ? Math.max(0, t + ((k + 0.5) / Nc - 0.5) * shutter) : t;
    const c = cameraAt(plan.camera, tk, g);
    const cu = cursorAt(track, tk, plan.cursor.hidden);
    if (!cu) continue;
    const p = projectPoint(c, g, cu);
    const scale = (cursorHeightFor(c.z, g) / shape.height) * pressScale(plan.cursor.clicks, tk);
    const alpha = cu.visible * (1 - cu.hidden);
    cur[k * 4] = p.x; cur[k * 4 + 1] = p.y; cur[k * 4 + 2] = scale; cur[k * 4 + 3] = alpha;
    const r = 30 * scale * 1.2 + 14 * g.unit;
    box = [Math.min(box[0], p.x - r), Math.min(box[1], p.y - r), Math.max(box[2], p.x + r), Math.max(box[3], p.y + r)];
  }
  return { st, N, moving, cam, Nc, cur, box, shape };
}

const Touch: FC<{ plan: any; t: number; camera: any }> = ({ plan, t, camera }) => {
  if (plan.cursor.mode !== "touch") return null;
  const g = plan.geometry;
  const nodes: any[] = [];
  for (const [i, tap] of plan.cursor.clicks.entries()) {
    const u = (t - tap.t) / 0.45;
    if (u < -0.02 || u > 1) continue;
    const p = projectPoint(camera, g, { x: tap.x, y: tap.y });
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

export const ScreenStage: FC<ScreenStageProps> = ({ plan, framesBase = "" }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const canvas = useRef<HTMLCanvasElement | null>(null);
  const glRef = useRef<GL | null>(null);
  const g = plan.geometry;
  const t = frame / fps;
  const base = framesBase.replace(/\/$/, "");
  const track = useMemo(() => buildCursorTrack(plan.cursor.samples), [plan]);

  useEffect(() => {
    const handle = delayRender(`screen stage frame ${frame}`);
    (async () => {
      try {
        const setup = frameSetup(plan, track, t, fps);
        const G = glRef.current ?? (glRef.current = makeGL(canvas.current!));
        const { gl, u } = G;
        const url = setup.st.frame ? staticFile([base, setup.st.frame].filter(Boolean).join("/")) : null;
        gl.viewport(0, 0, g.W, g.H);
        if (url) {
          const tex = await loadTexture(G, url);
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, tex);
        }
        gl.uniform1i(u.uTex, 0);
        gl.uniform2f(u.uStage, g.W, g.H);
        gl.uniform1i(u.uN, setup.N);
        gl.uniform1i(u.uMoving, setup.moving ? 1 : 0);
        gl.uniform4fv(u.uCam, setup.cam);
        gl.uniform1i(u.uNc, setup.Nc);
        gl.uniform4fv(u.uCur, setup.cur);
        const poly = new Float32Array(MAX_POLY * 2);
        setup.shape.points.forEach((p: number[], i: number) => { poly[i * 2] = p[0]; poly[i * 2 + 1] = p[1]; });
        gl.uniform2fv(u.uPoly, poly);
        gl.uniform1i(u.uPolyN, setup.shape.points.length);
        gl.uniform2f(u.uHot, setup.shape.hot[0], setup.shape.hot[1]);
        gl.uniform4f(u.uCurBox, setup.box[0], setup.box[1], setup.box[2], setup.box[3]);
        gl.uniform1f(u.uUnit, g.unit);
        if (g.placement) {
          const lin = (v: number) => { const c = v / 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
          const [c0, c1] = plan.background.colors;
          const a = (plan.background.angle * Math.PI) / 180, k = Math.abs(Math.cos(a)) + Math.abs(Math.sin(a));
          gl.uniform4f(u.uPlace, g.placement.x, g.placement.y, g.placement.w, g.placement.h);
          gl.uniform1f(u.uRadius, g.placement.radius);
          gl.uniform3f(u.uBg0, lin(c0[0]), lin(c0[1]), lin(c0[2]));
          gl.uniform3f(u.uBg1, lin(c1[0]), lin(c1[1]), lin(c1[2]));
          gl.uniform2f(u.uBgDir, Math.cos(a) / k, Math.sin(a) / k);
        } else gl.uniform4f(u.uPlace, 0, 0, 0, 0);
        const hi = setup.st.highlight;
        if (hi) {
          const b0 = projectPoint(setup.st.camera, g, { x: hi.box.x, y: hi.box.y }), b1 = projectPoint(setup.st.camera, g, { x: hi.box.x + hi.box.w, y: hi.box.y + hi.box.h });
          gl.uniform4f(u.uHi, (b0.x + b1.x) / 2, (b0.y + b1.y) / 2, Math.abs(b1.x - b0.x) / 2, Math.abs(b1.y - b0.y) / 2);
          gl.uniform2f(u.uHiAmt, hi.dim * hi.amount, hi.amount);
        } else gl.uniform2f(u.uHiAmt, 0, 0);
        gl.uniform1f(u.uHiOutline, STAGE.highlight.outline * g.unit);
        gl.uniform1f(u.uSeed, setup.moving ? (frame % 97) + 1 : 0);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        gl.finish();
        continueRender(handle);
      } catch (e) {
        cancelRender(e);
      }
    })();
  }, [frame]);

  // The camera for the touch overlay; the page itself is drawn by the canvas.
  const camera = cameraAt(plan.camera, t, g);
  return (
    <AbsoluteFill style={{ backgroundColor: "#000" }}>
      <canvas ref={canvas} width={g.W} height={g.H} style={{ position: "absolute", left: 0, top: 0, width: g.W, height: g.H }} />
      <Touch plan={plan} t={t} camera={camera} />
    </AbsoluteFill>
  );
};
