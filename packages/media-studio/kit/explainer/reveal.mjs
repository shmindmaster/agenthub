/**
 * When a part with no time of its own arrives. One curve, used by the bodies in
 * kit/src, by the explainer's shells and by the stills command, so none of them
 * can disagree about which parts are on screen at a frame.
 */

/**
 * Spread n default reveals across the part of the scene that is still being
 * narrated. A 28-second code block that finished appearing at 4s spent 24
 * seconds frozen — the exact defect `atSeconds` was added to the bullet board
 * to cure. `step` is derived from the scene length rather than fixed, so the
 * picture keeps arriving for as long as the voice keeps talking.
 */
export const revealAt = (i, n, durationSeconds) => {
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
export const phase = (i, n, durationSeconds, from = 0) => {
  if (from <= 0) return revealAt(i, n, durationSeconds);
  if (i < from) return -5;
  return revealAt(i - from, Math.max(1, n - from), durationSeconds);
};

/** The default start of chart bars and svg groups, which use their own spacing. */
export const spreadAt = (i, n, durationSeconds) => 0.4 + (i * Math.max(0.5, durationSeconds * 0.8 - 0.4)) / Math.max(1, n);

/** How long an arrow takes to draw. */
export const DRAW_SECONDS = 0.5;

/** When an arrow starts: it finishes as its box lands, and never starts before its source. */
export const edgeStart = (edge, startOf) =>
  edge.at ?? Math.max(startOf(edge.from), startOf(edge.to) - (startOf(edge.to) > startOf(edge.from) ? DRAW_SECONDS : 0));

/**
 * Every part of a shot's picture that arrives: when, and for how long it moves
 * where that is longer than an ordinary entrance.
 */
export const revealParts = (visual, durationSeconds) => {
  const parts = revealStarts(visual, durationSeconds).map((at) => ({ at, seconds: 0 }));
  if (visual?.kind === 'chart') {
    const bars = visual.form === 'waffle' ? 1 : (visual.items ?? []).length;
    parts.slice(0, bars).forEach((part) => Object.assign(part, { seconds: visual.form === 'waffle' ? 1.6 : 0.9 }));
  }
  if (visual?.kind === 'svg') {
    parts.forEach((part, i) => Object.assign(part, { seconds: visual.groups[i].trace ? visual.groups[i].trace.durationSeconds ?? 0.65 : 0.45 }));
  }
  if (visual?.kind === 'diagram' || visual?.kind === 'flow') {
    const key = (node, i) => node.id ?? i;
    const starts = new Map((visual.nodes ?? []).map((node, i) => [key(node, i), parts[i].at]));
    const edges = visual.kind === 'diagram' ? visual.edges ?? [] : (visual.nodes ?? []).slice(1).map((node, i) => ({ from: key(visual.nodes[i], i), to: key(node, i + 1) }));
    for (const edge of edges) parts.push({ at: edgeStart(edge, (id) => starts.get(id) ?? 0), seconds: DRAW_SECONDS });
  }
  return parts;
};

const revealStarts = (visual, durationSeconds) => {
  if (!visual) return [];
  const from = visual.revealFrom ?? 0;
  const curve = (items) => (items ?? []).map((item, i, all) => item?.beat ?? (typeof item?.at === 'number' ? item.at : phase(i, all.length, durationSeconds, from)));
  const spread = (items) => (items ?? []).map((item, i, all) => item?.at ?? spreadAt(i, all.length, durationSeconds));
  const bare = (items) => (items ?? []).map((_, i, all) => phase(i, all.length, durationSeconds, from));
  switch (visual.kind) {
    case 'flow':
    case 'diagram':
      return curve(visual.nodes);
    case 'layers':
      return curve(visual.layers);
    case 'code':
      return curve(visual.lines);
    case 'checklist':
      return curve(visual.items);
    case 'timeline':
      return (visual.events ?? []).map((event, i, all) => event.beat ?? phase(i, all.length, durationSeconds, from));
    case 'sequence':
      return bare(visual.steps);
    case 'table':
      return bare(visual.rows);
    case 'map':
      return bare((visual.lanes ?? []).flatMap((lane) => lane.nodes ?? []));
    case 'split':
      return [...curve(visual.left?.items), ...curve(visual.right?.items)];
    case 'beforeafter':
      return [...bare(visual.before?.items), ...bare(visual.after?.items)];
    case 'chart':
      return [...spread(visual.items), ...(visual.notes ?? []).map((note, i) => note.at ?? (visual.items?.[0]?.at ?? 0.4) + 1.2 + i * 1.4)];
    case 'svg':
      return spread(visual.groups);
    default:
      return typeof visual.at === 'number' ? [visual.at] : [];
  }
};
