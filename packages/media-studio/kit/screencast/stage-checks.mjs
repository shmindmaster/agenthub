// Screen stage: checks that need only the plan, shared by the encoded-film gate (scripts/validate-screen-stage.mjs) and the tests.
// Each returns a list of problem strings; an empty list passes. Every rule here has a number from the owner's motion review of
// core-v1 and a test that fails on a core-v1 style plan. Contract: skills/studio/references/screen-stage.md.
import { STAGE, cameraAt, cursorAt, buildCursorTrack } from './stage-math.mjs';

const r2 = (v) => Math.round(v * 100) / 100;

/** Time a pointer approach starts for each camera move: the first cursor movement after the previous press (or the run start). */
export function approachStarts(plan) {
  const s = plan.cursor.samples, clicks = plan.cursor.clicks.map((c) => c.t).sort((a, b) => a - b);
  const out = [];
  for (const c of clicks) {
    const prev = clicks.filter((x) => x < c - 1e-6).pop() ?? -Infinity;
    const within = s.filter((p) => p.t > prev + 1e-6 && p.t <= c + 1e-6);
    let start = null;
    for (let i = 1; i < within.length; i++) if (Math.hypot(within[i].x - within[i - 1].x, within[i].y - within[i - 1].y) > 2) { start = within[i - 1].t; break; }
    out.push({ press: c, start });
  }
  return out;
}

/** Time of peak speed of a camera move (analytic spring from rest: tau = 1/omega). */
export const cameraPeakAfter = (seg) => seg.t0 + 1 / STAGE.omega;

/** 1.5 by default; above that only a tiny target together with a tiny result in the same view (owner review of core-v1, item 5). */
export function zoomProblems(plan) {
  const g = plan.geometry, out = [];
  for (const r of plan.regions || []) {
    const area = r.region ? (r.region.w * r.region.h) / (g.W * g.H) : 1;
    if (r.zoom > g.zoom.default + 0.02 && !r.declared && !(r.withResult && area <= 0.06)) out.push(`the view at ${r.firstT}s is zoomed ${r2(r.zoom)}x: only a tiny target with a tiny result in view may exceed ${g.zoom.default}x`);
  }
  return out;
}

/** The camera starts a little before the pointer starts to move, and the film opens on a clean full page (items 3 and 7). */
export function leadProblems(plan) {
  const out = [], segs = plan.camera.segments;
  if (segs.length && segs[0].t0 < 0.35 - 1e-6) out.push(`the first camera move starts at ${segs[0].t0}s: the film must hold the clean full page for at least 0.35 s first`);
  const starts = approachStarts(plan);
  for (const seg of segs) {
    if (!['open', 'region'].includes(seg.reason) || seg.declared || seg.delayedForResult) continue;
    const press = starts.find((a) => a.press >= seg.t0 - 1e-6);
    if (!press || press.start === null) continue;
    const lead = press.start - seg.t0;
    if (lead < STAGE.cameraLeadSeconds - 0.05 - 1e-6) out.push(`the camera move at ${seg.t0}s starts ${r2(lead)} s before the pointer (${r2(press.start)}s): it must lead by about ${STAGE.cameraLeadSeconds} s so the two are not at peak speed together`);
  }
  return out;
}

/** A result that appears elsewhere on the page is reached within resultLeadSeconds + 0.05 of the press (item 4). */
export function resultProblems(plan) {
  const out = [];
  for (const res of plan.results || []) {
    if (res.carried) continue; // shown in the next region, checked on the film at the next press
    const seg = plan.camera.segments.find((s) => s.reason === 'result' && s.t0 >= res.t - 1e-6 && s.t0 - res.t <= 0.3);
    if (!seg) out.push(`the result of "${res.label || 'press'}" at ${res.t}s has no camera move within 0.25 s`);
    else if (seg.t0 - res.t > STAGE.resultLeadSeconds + 0.05 + 1e-6) out.push(`the camera reaches the result of "${res.label || 'press'}" ${r2(seg.t0 - res.t)} s after the press, not within 0.25 s`);
  }
  return out;
}

/** A result the plan could not show (dropped for the next move, and not carried into it) is a result the viewer never sees. */
export function unseenResultProblems(plan) {
  return (plan.warnings || []).filter((w) => /is not followed/.test(w)).map((w) => `${w}: the result is never shown`);
}

/** A highlight is over (fully faded) before the click on or inside its element and before any other press, so the result is never dimmed. */
export function highlightProblems(plan) {
  const out = [], ease = STAGE.highlight.easeSeconds;
  const presses = (plan.cursor.clicks || []).map((c) => c.t);
  for (const h of plan.highlights || []) {
    const p = presses.filter((t) => t >= h.t0 - 1e-6 && t < h.t1 + ease + 1e-6);
    if (p.length) out.push(`the highlight on "${h.label}" (${h.t0}-${h.t1}s) is still on at the press at ${p[0]}s: it must be fully faded before the click, or the result is dimmed`);
  }
  return out;
}

/**
 * Between the first and the last action at least STAGE.zoomCoverageMin of the film time is zoomed (1.3x on wide frames, 1.12x on the others),
 * not counting the intervals the plan records a reason for (a region that cannot fit zoomed, a result shown once). Returns the numbers.
 */
export function zoomCoverage(plan) {
  const g = plan.geometry, acts = plan.planned || [];
  if (!acts.length || plan.zoomMode === 'off') return { applicable: false };
  const from = Math.min(...acts.map((a) => a.t)), to = Math.max(...acts.map((a) => a.tEnd ?? a.t));
  const thr = g.W / g.H > 1.2 ? 1.3 : 1.12;
  const notes = plan.zoomNotes || [];
  let total = 0, zoomed = 0;
  const step = 0.05;
  for (let t = from; t < to; t += step) {
    if (notes.some((n) => t >= n.from && t < n.to)) continue;
    total += step;
    if (cameraAt(plan.camera, t, g).z >= thr - 0.005) zoomed += step;
  }
  return { applicable: true, from, to, threshold: thr, seconds: Math.round(total * 100) / 100, zoomedSeconds: Math.round(zoomed * 100) / 100, fraction: total > 0 ? Math.round((zoomed / total) * 1000) / 1000 : 1 };
}

export function zoomCoverageProblems(plan) {
  const c = zoomCoverage(plan);
  if (!c.applicable || c.fraction >= STAGE.zoomCoverageMin) return [];
  return [`only ${Math.round(c.fraction * 100)}% of the film time between the first action (${c.from}s) and the last (${c.to}s) is zoomed to ${c.threshold}x or more, under ${Math.round(STAGE.zoomCoverageMin * 100)}%: the camera must stay on the action, and a region that cannot zoom must be recorded with its reason`];
}

/** A result shown elsewhere is held at least resultMinViewSeconds, and the camera leaves it within resultHoldMaxSeconds. */
export function resultHoldProblems(plan) {
  const out = [], segs = plan.camera.segments;
  for (const res of plan.results || []) {
    const i = segs.findIndex((s) => s.reason === 'result' && Math.abs(s.t0 - res.at) < 0.06);
    if (i < 0) continue;
    const next = segs[i + 1];
    if (!next) continue;
    const held = next.t0 - segs[i].t0;
    if (held < STAGE.resultMinViewSeconds - 0.02) out.push(`the result of "${res.label || 'press'}" is shown ${r2(held)} s, under ${STAGE.resultMinViewSeconds} s: it must be seen unobstructed`);
    if (next.reason === 'region' && held > STAGE.resultHoldMaxSeconds + 0.02) out.push(`the camera holds the result of "${res.label || 'press'}" ${r2(held)} s, over ${STAGE.resultHoldMaxSeconds} s: it goes on to the next target`);
  }
  return out;
}

export const planProblems = (plan) => [...zoomProblems(plan), ...leadProblems(plan), ...resultProblems(plan), ...resultHoldProblems(plan), ...unseenResultProblems(plan), ...highlightProblems(plan), ...zoomCoverageProblems(plan)];

export { cameraAt, cursorAt, buildCursorTrack };
