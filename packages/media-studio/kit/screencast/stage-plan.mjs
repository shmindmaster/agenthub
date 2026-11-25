// Screen stage plan: the camera, cursor and frame lookup for one run of contiguous screen slots, as a PURE function of the capture
// receipt events, the compose edit list (headHold, speed, skip, trim) and the frame geometry. No rendering, no filesystem: the same
// input always gives the same plan, and the plan is what the renderer draws and what validate-screen-stage.mjs measures the encoded
// film against. Contract: skills/studio/references/screen-stage.md.
import { STAGE, buildCursorTrack, cameraForBox, cameraAt, boxInView, clamp, cursorKind, stageGeometry, toStageBox, unionBox, viewRect, wideCamera, zoomForBox } from './stage-math.mjs';
import { clipToSlot } from './sync-lib.mjs';

export const PLAN_SCHEMA = 'media-studio/screen-stage-plan/1';
export const PRESS = new Set(['click', 'tap', 'type', 'fill', 'select', 'point', 'upload']);
const ESTIMATED_BOX = { w: 120, h: 44 }; // CSS px, for an old receipt press with no recorded target box
const r3 = (v) => Math.round(v * 1000) / 1000;

/** The press's recorded target box in CSS px, or an estimate around its point (flagged) when the receipt has none. */
function pressBox(ev) {
  const b = ev.targetBox;
  if (b && [b.x, b.y, b.w, b.h].every(Number.isFinite) && b.w > 0 && b.h > 0) return { box: { x: b.x, y: b.y, w: b.w, h: b.h }, estimated: false };
  if (Number.isFinite(ev.x) && Number.isFinite(ev.y)) return { box: { x: ev.x - ESTIMATED_BOX.w / 2, y: ev.y - ESTIMATED_BOX.h / 2, w: ESTIMATED_BOX.w, h: ESTIMATED_BOX.h }, estimated: true };
  return null;
}

/**
 * Receipt events of one slot in film seconds. `edit` is the compose edit of the slot; an event the edit drops (inside a skip) has no
 * film time and is left out. Typing is merged into the click that focused its field: one target, held until the typing ends.
 */
export function slotEvents(slot, clip) {
  const at = (ts) => { const s = clipToSlot(slot.edit, ts); return s === null ? null : r3(slot.startSeconds + s); };
  const out = { moves: [], presses: [], results: [] };
  let lastKind = 'arrow';
  let approachStart = null; // film time of the first pointer move since the previous press: the camera leads this
  const actions = clip.actions || [];
  const changesAt = (ts) => (clip.changes || []).find((c) => Math.abs(c.t - ts) < 0.02)?.boxes || [];
  for (const ev of actions) {
    if (ev.type === 'move' && Number.isFinite(ev.x) && Number.isFinite(ev.y)) {
      const t = at(ev.t);
      if (ev.cursor) lastKind = cursorKind(ev.cursor);
      if (t !== null) { out.moves.push({ t, x: ev.x, y: ev.y, kind: lastKind }); if (approachStart === null) approachStart = t; }
    } else if (PRESS.has(ev.type)) {
      const tp = ev.tStart ?? ev.t;
      const t = at(tp);
      if (ev.cursor) lastKind = cursorKind(ev.cursor);
      if (t === null) continue;
      const b = pressBox(ev);
      const press = { type: ev.type, label: ev.label || null, t, tEnd: ev.tEnd !== undefined ? at(ev.tEnd) ?? t : t, x: ev.x ?? null, y: ev.y ?? null, kind: lastKind, box: b?.box || null, estimated: b?.estimated ?? null, approachStart, changes: changesAt(tp) };
      approachStart = null;
      out.presses.push(press);
    }
  }
  // A typing burst continues the press that focused its field.
  const merged = [];
  for (const p of out.presses) {
    const prev = merged[merged.length - 1];
    if (p.type === 'type' && prev && (prev.type === 'click' || prev.type === 'tap') && p.t - prev.t <= 2) { prev.tEnd = Math.max(prev.tEnd, p.t + Math.max(0.3, (p.tEnd ?? p.t) - p.t)); prev.typed = true; continue; }
    if (p.type === 'type' && Number.isFinite(p.tEnd) && p.tEnd <= p.t) p.tEnd = p.t + 0.6;
    merged.push(p);
  }
  out.presses = merged.filter((p) => p.box);
  for (const e of clip.expectations || []) {
    if (!e.observed || !e.targetBox) continue;
    const t = at(e.observedAt ?? e.at);
    if (t !== null) out.results.push({ label: e.label, t, box: e.targetBox });
  }
  return out;
}

/** Joint bounding box clustering of presses into zoom regions (typing counts as a target, not only clicks). */
function clusterPresses(presses, g) {
  const clusters = [];
  for (const p of presses) {
    const sb = toStageBox(g, p.box);
    const cur = clusters[clusters.length - 1];
    if (cur && p.t - cur.lastEnd <= STAGE.clusterGapSeconds && p.t - cur.firstT <= STAGE.clusterSpanSeconds && zoomForBox(unionBox([...cur.boxes, sb]), g) > 1) {
      cur.boxes.push(sb); cur.presses.push(p); cur.lastEnd = Math.max(cur.lastEnd, p.tEnd);
    } else clusters.push({ firstT: p.t, lastEnd: p.tEnd, boxes: [sb], presses: [p], approachStart: p.approachStart });
  }
  return clusters;
}

/** Build the plan. See the file header for the input; `slots` are contiguous from 0 and `runSeconds` is their total. */
export function buildStagePlan({ frame, viewport, dsf = STAGE.deviceScaleFactor, slots, clips, options = {} }) {
  const g = stageGeometry(frame, viewport);
  const runSeconds = r3(slots.reduce((n, s) => Math.max(n, s.startSeconds + s.durationSeconds), 0));
  const warnings = [];

  // ---- events in film time
  const moves = [], presses = [], results = [];
  for (const slot of slots) {
    const clip = clips[slot.clipId];
    if (!clip) throw new Error(`screen stage: slot at ${slot.startSeconds}s names clip ${slot.clipId}, which has no receipt entry`);
    if (slot.hold) continue; // a hold repeats the previous clip's last frame: its events were already placed by the slot that played it
    const ev = slotEvents(slot, clip);
    moves.push(...ev.moves); presses.push(...ev.presses); results.push(...ev.results);
  }
  presses.sort((a, b) => a.t - b.t);

  // ---- zoom regions
  const clusters = clusterPresses(presses, g);
  clusters.forEach((c, i) => {
    const next = clusters[i + 1];
    const limit = next ? next.firstT : Infinity;
    const resp = results.filter((r) => r.t >= c.firstT - 1e-6 && r.t < limit).map((r) => toStageBox(g, r.box));
    const act = unionBox(c.boxes);
    let box = act;
    // The action and its result both stay in frame when they fit together; otherwise the result is dropped before the action is.
    let joined = false;
    if (resp.length) { const both = unionBox([act, ...resp]); if (zoomForBox(both, g) > 1) { box = both; joined = true; } }
    // What changed on the page within about a second of the last press (measured from the captured frames). When it lies outside the
    // action it must be seen: it joins the region if both fit, otherwise the camera goes to it within resultLeadSeconds of the press.
    const lastPress = c.presses[c.presses.length - 1];
    const near = unionBox([act]), pad = 40;
    const outside = (lastPress.changes || []).map((b) => toStageBox(g, b)).filter((b) => b.x > near.x + near.w + pad || b.x + b.w < near.x - pad || b.y > near.y + near.h + pad || b.y + b.h < near.y - pad);
    c.resultBox = outside.length ? unionBox(outside) : null;
    c.resultCamera = null;
    if (c.resultBox) {
      const both = unionBox([box, c.resultBox]);
      if (zoomForBox(both, g) > 1) { box = both; joined = true; }
      else { c.resultCamera = cameraForBox(c.resultBox, g, { bias: false }); c.resultAt = lastPress.t + STAGE.resultLeadSeconds; }
    }
    c.action = act; c.region = box;
    // The 1.8 ceiling is for a tiny target together with a tiny result in the same view; anything else stays at the 1.5 default.
    c.zoom = joined ? zoomForBox(box, g) : Math.min(zoomForBox(box, g), g.zoom.default);
    c.camera = cameraForBox(box, g, { bias: c.presses.length === 1 && box === act, zoom: c.zoom });
    c.resultEnd = Math.max(c.lastEnd, ...results.filter((r) => r.t >= c.firstT && r.t < limit).map((r) => r.t));
  });

  // ---- camera track: wide, spring to each region just before its first press, wide again at the end
  const initial = wideCamera(g);
  const segments = [];
  let cur = initial;
  const lastSegT0 = () => (segments.length ? segments[segments.length - 1].t0 : -Infinity);
  clusters.forEach((c, i) => {
    const prev = clusters[i - 1];
    if (prev && c.firstT - prev.resultEnd >= STAGE.contextGapSeconds && cur.z > 1) {
      const t0 = prev.resultEnd + STAGE.closeHoldSeconds;
      segments.push({ t0: r3(t0), to: initial, reason: 'context' }); cur = initial;
    }
    const seen = c.zoom > 1 && cur.z > 1 && Math.abs(cur.z - c.camera.z) < 0.05 + 0.2 && boxInView(cur, g, c.action, STAGE.mergeInset) && boxInView(cur, g, c.region, 0);
    c.merged = seen;
    if (seen) return;
    if (c.zoom <= 1 && cur.z <= 1) { c.merged = true; return; }
    const earliest = i === 0 ? STAGE.openWideSeconds : lastSegT0() + 0.35;
    // The camera starts a little before the pointer starts to move (so the two are not at peak speed together) and lands by the press.
    const lead = c.approachStart != null ? c.approachStart - STAGE.cameraLeadSeconds : c.firstT - STAGE.leadSeconds;
    const t0 = Math.max(earliest, Math.min(lead, c.firstT - STAGE.leadSeconds));
    if (i === 0 && Math.min(lead, c.firstT - STAGE.leadSeconds) < STAGE.openWideSeconds) warnings.push(`the first move would start before ${STAGE.openWideSeconds}s of clean full page: it starts at ${r3(t0)}s`);
    segments.push({ t0: r3(t0), to: c.camera, reason: i === 0 ? 'open' : 'region' });
    cur = c.camera;
    if (c.resultCamera) { segments.push({ t0: r3(Math.max(c.resultAt, lastSegT0() + 0.35)), to: c.resultCamera, reason: 'result' }); cur = c.resultCamera; }
  });
  if (cur.z > 1) {
    const lastEnd = clusters.length ? clusters[clusters.length - 1].resultEnd : 0;
    let t0 = Math.max(lastEnd + STAGE.closeHoldSeconds, runSeconds - STAGE.closeWideSeconds);
    if (t0 > runSeconds - STAGE.settleSeconds) { t0 = runSeconds - STAGE.settleSeconds; warnings.push(`the run ends ${r3(runSeconds - lastEnd)}s after its last action: the pull back to the full page starts at ${r3(t0)}s and may not settle before the end`); }
    segments.push({ t0: r3(Math.max(t0, lastSegT0() + 0.35)), to: initial, reason: 'close' });
  }
  const camera = { initial, segments };

  // ---- cursor
  const samples = [...moves];
  for (const p of presses) if (Number.isFinite(p.x) && Number.isFinite(p.y)) samples.push({ t: p.t, x: p.x, y: p.y, kind: p.kind });
  let stageSamples = debounceKinds(samples.map((s) => ({ t: s.t, x: r3(s.x * g.k), y: r3(s.y * g.k), kind: s.kind })).sort((a, b) => a.t - b.t));
  const clicks = presses.filter((p) => ['click', 'tap'].includes(p.type) && Number.isFinite(p.x)).map((p) => ({ t: p.t, x: r3(p.x * g.k), y: r3(p.y * g.k), label: p.label }));
  // The cursor stops moving for the last half second of the run, unless a press lands there (a press is never moved).
  const rest = runSeconds - STAGE.restSeconds;
  if (!clicks.some((c) => c.t > rest) && stageSamples.some((s) => s.t > rest)) {
    const before = stageSamples.filter((s) => s.t <= rest);
    if (before.length) stageSamples = [...before, { ...before[before.length - 1], t: r3(rest) }];
  }
  const touch = slots.some((s) => clips[s.clipId]?.touch);
  const hidden = [...(options.hideCursor || [])];
  if (options.idleHide !== false && !touch) hidden.push(...idleHideRanges({ samples: stageSamples, presses, runSeconds }));
  const cursor = { mode: touch ? 'touch' : 'pointer', samples: stageSamples, clicks, hidden: hidden.map(([a, b]) => [r3(a), r3(b)]) };

  // ---- what the gate measures against
  const track = buildCursorTrack(stageSamples);
  const planned = presses.map((p) => {
    const c = clusters.find((cl) => cl.presses.includes(p));
    const cam = cameraAt(camera, p.t, g);
    return { t: p.t, tEnd: p.tEnd, type: p.type, label: p.label, boxCss: p.box, boxStage: toStageBox(g, p.box), estimated: p.estimated, pointStage: Number.isFinite(p.x) ? { x: r3(p.x * g.k), y: r3(p.y * g.k) } : null,
      cluster: clusters.indexOf(c), cameraAtPress: { cx: r3(cam.cx), cy: r3(cam.cy), z: r3(cam.z) }, zoomed: cam.z > 1.05, inView: boxInView(cam, g, toStageBox(g, p.box)) };
  });
  const moveList = segments.map((s, i) => ({ t0: s.t0, settledBy: r3(s.t0 + STAGE.settleSeconds), reason: s.reason, to: { cx: r3(s.to.cx), cy: r3(s.to.cy), z: r3(s.to.z) }, nextStart: segments[i + 1]?.t0 ?? null }));

  for (const p of planned) {
    if (!p.inView) warnings.push(`the target of "${p.label || p.type}" at ${p.t}s is not inside the planned view`);
    if (p.estimated) warnings.push(`"${p.label || p.type}" at ${p.t}s has no recorded target box: framed from its point (re-record with the current kit)`);
  }

  return {
    schema: PLAN_SCHEMA,
    frame: { width: frame.width, height: frame.height, fps: frame.fps ?? STAGE.fps },
    viewport: { width: viewport.width, height: viewport.height }, deviceScaleFactor: dsf,
    geometry: g,
    runSeconds,
    slots: slots.map((s) => ({ clipId: s.clipId, startSeconds: r3(s.startSeconds), durationSeconds: r3(s.durationSeconds), edit: s.edit, hold: !!s.hold })),
    frames: Object.fromEntries([...new Set(slots.map((s) => s.clipId))].map((id) => [id, clips[id].frames])),
    camera, cursor, planned, moves: moveList, warnings,
    regions: clusters.map((c) => ({ firstT: c.firstT, resultEnd: r3(c.resultEnd), zoom: r3(c.zoom), merged: !!c.merged, labels: c.presses.map((p) => p.label || p.type), region: c.region })),
    results: clusters.filter((c) => c.resultBox).map((c) => ({ t: c.presses[c.presses.length - 1].t, label: c.presses[c.presses.length - 1].label, boxStage: c.resultBox, mustBeSeenBy: r3(c.presses[c.presses.length - 1].t + STAGE.resultLeadSeconds + 0.7) })),
  };
}

/** A cursor-type change that lasts under STAGE.kindDebounceSeconds is not drawn: the previous type holds. */
export function debounceKinds(samples) {
  const out = samples.map((s) => ({ ...s }));
  const runs = [];
  for (const s of out) { const r = runs[runs.length - 1]; if (r && r.kind === s.kind) r.items.push(s); else runs.push({ kind: s.kind, start: s.t, items: [s] }); }
  for (let i = 1; i + 1 < runs.length; i++) if (runs[i + 1].start - runs[i].start < STAGE.kindDebounceSeconds) for (const s of runs[i].items) s.kind = runs[i - 1].items[0].kind;
  return out;
}

/** Hide ranges for a cursor that has sat still: [[from, to], ...] in film seconds. Never across a pointAt (the dwell is the point). */
export function idleHideRanges({ samples, presses, runSeconds }) {
  const marks = [...samples.map((s) => s.t), ...presses.flatMap((p) => [p.t, p.tEnd])].filter(Number.isFinite).sort((a, b) => a - b);
  const keep = presses.filter((p) => p.type === 'point').map((p) => [p.t, p.tEnd + 0.9]);
  const out = [];
  for (let i = 0; i < marks.length; i++) {
    const a = marks[i], b = i + 1 < marks.length ? marks[i + 1] : runSeconds + 0.3;
    const from = a + STAGE.idleHideSeconds + STAGE.hideFadeSeconds, to = b - 0.3;
    if (to - from < 0.1) continue;
    if (keep.some(([x, y]) => x < to && y > a)) continue;
    out.push([from, to]);
  }
  return out;
}

/**
 * Idle source time inside a clip: no recorded input AND no new frame (frames arrive only when the page changes, so a gap between
 * frames is frozen pixels). Only idle time may be cut or sped up without a declared reason: a playing animation, a spinner or a real
 * product wait changes frames and is never idle. Returns [[a, b], ...] in clip seconds, each at least `minSeconds` long.
 */
export function idleRanges({ actions = [], frameTimes = [], clipSeconds, minSeconds = 0.8 }) {
  const marks = [0, clipSeconds];
  for (const e of actions) for (const t of [e.t, e.tStart, e.tEnd]) if (Number.isFinite(t)) marks.push(t);
  for (const t of frameTimes) marks.push(t);
  marks.sort((a, b) => a - b);
  const out = [];
  for (let i = 0; i + 1 < marks.length; i++) if (marks[i + 1] - marks[i] >= minSeconds) out.push([r3(marks[i]), r3(marks[i + 1])]);
  return out;
}

/** Edit hints that compress real activity: a skip over time that is not idle, or a speed-up with no declared reason. */
export function compressionProblems({ edit, idle, speedReason, label = 'clip' }) {
  const problems = [];
  for (const [a, b] of edit.skip || []) {
    const inside = idle.some(([x, y]) => a >= x - 0.05 && b <= y + 0.05);
    if (!inside && !(typeof speedReason === 'string' && speedReason.trim())) problems.push(`${label}: skip [${a}, ${b}] cuts time with input or changing pixels; only idle time (no input and frozen pixels) may be cut, or declare speedReason`);
  }
  if (Number(edit.speed || 1) > 1 && !(typeof speedReason === 'string' && speedReason.trim())) problems.push(`${label}: speed ${edit.speed} needs a speedReason`);
  return problems;
}

export { viewRect, clamp };
