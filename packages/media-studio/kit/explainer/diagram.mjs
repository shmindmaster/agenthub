/**
 * Layout for a linked diagram: icon boxes placed on a grid, joined by arrows
 * that name their ends by id.
 *
 * The result is plain pixels for one box on the canvas. The renderer draws it
 * and the builder refuses its `problems`, so a diagram that would overlap, cut
 * its words or run an arrow through a box never reaches a render.
 */
import iconData from './icons.json' with { type: 'json' };
import { textWidth, wrapText } from './layout.mjs';

export const ICONS = iconData.icons;

/** Bold type runs wider than the regular widths layout.mjs estimates. */
export const BOLD = 1.08;
/** Regular type, with a little room for a font the host substitutes. */
const REGULAR = 1.05;
const MAX_LABEL = 60;
const MIN_LABEL = 20;
const MAX_NODE_W = 430;
const LINE = 1.18;
const PAD = 24;
const EDGE_LABEL = 24;
const MIN_EDGE_LABEL = 18;
/** Room below the last row for an arrow that has to pass under its row. */
const UNDERPASS = 52;
/** A caption is 22 px capitals tracked out, in lines of half again its size. */
const CAPTION_SIZE = 22;
const CAPTION_TRACKING = 0.18;
export const CAPTION_LINE = 33;
/** The size a slide gives a diagram; the explainer passes its own region. */
export const SLIDE_BOX = { w: 1360, h: 560 };

export const boldWidth = (text, size) => Math.ceil(textWidth(text ?? '', size) * BOLD);

export const plainWidth = (text, size) => Math.ceil(textWidth(text ?? '', size) * REGULAR);

export const wrapPlain = (text, width, size) => wrapText(text ?? '', Math.max(1, width) / REGULAR, size);

export const wrapBold = (text, width, size) => wrapText(text ?? '', Math.max(1, width) / BOLD, size);

const captionWidth = (text) => boldWidth(text, CAPTION_SIZE) + Math.ceil(text.length * CAPTION_TRACKING * CAPTION_SIZE);

/** The lines a caption takes at a width, in the capitals it is printed in. */
export const captionLines = (caption, width) => {
  const lines = [];
  let line = '';
  for (const word of String(caption ?? '').toUpperCase().trim().split(/\s+/).filter(Boolean)) {
    const next = line ? `${line} ${word}` : word;
    if (captionWidth(next) <= width || !line) line = next;
    else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
};

/** Icon names that share a part with one the kit does not carry. */
export const suggestIcons = (name, limit = 5) => {
  const parts = String(name).toLowerCase().split(/[^a-z0-9]+/).filter((part) => part.length > 2);
  return Object.keys(ICONS)
    .map((key) => ({
      key,
      score: parts.filter((part) => key.split('-').some((piece) => piece.length > 2 && (piece.startsWith(part) || part.startsWith(piece)))).length,
    }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score || a.key.length - b.key.length || (a.key < b.key ? -1 : 1))
    .slice(0, limit)
    .map((entry) => entry.key);
};

/**
 * Content of one node at a label size: its lines, its icon, the height they need.
 * `beside` puts the icon left of the words, for a box that is wide and short.
 */
const contentOf = (node, width, size, beside) => {
  const subSize = Math.max(18, Math.round(size * 0.6));
  const iconSize = node.icon ? Math.round(size * (beside ? 1.4 : 1.7)) : 0;
  const iconGap = iconSize ? Math.round(size * 0.4) : 0;
  const inner = width - 2 * PAD - (beside ? iconSize + iconGap : 0);
  const lines = wrapBold(node.label, inner, size);
  const subLines = node.sub ? wrapPlain(node.sub, inner, subSize) : [];
  const wide = lines.some((line) => boldWidth(line, size) > inner) || subLines.some((line) => plainWidth(line, subSize) > inner);
  const words =
    Math.ceil(lines.length * size * LINE) +
    (subLines.length ? Math.round(size * 0.2) + Math.ceil(subLines.length * subSize * 1.25) : 0);
  const height = 2 * PAD + (beside ? Math.max(iconSize, words) : iconSize + iconGap + words);
  return { size, subSize, iconSize, iconGap, beside, lines, subLines, height, fits: !wide && lines.length <= 3 && subLines.length <= 3 };
};

const centre = (rect) => ({ x: rect.x + rect.w / 2, y: rect.y + rect.h / 2 });

const inflate = (rect, by) => ({ x: rect.x - by, y: rect.y - by, w: rect.w + 2 * by, h: rect.h + 2 * by });

export const rectsOverlap = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

/** Every arrow segment is horizontal or vertical, so a segment is a thin rect. */
const segmentRect = ({ p, q }) => ({
  x: Math.min(p.x, q.x) - 1,
  y: Math.min(p.y, q.y) - 1,
  w: Math.abs(p.x - q.x) + 2,
  h: Math.abs(p.y - q.y) + 2,
});

const segmentsOf = (points) => points.slice(1).map((q, i) => ({ p: points[i], q }));

const segmentLength = ({ p, q }) => Math.abs(p.x - q.x) + Math.abs(p.y - q.y);

export const routeLength = (points) => segmentsOf(points).reduce((sum, segment) => sum + segmentLength(segment), 0);

/** A point `t` (0..1) of the way along a route. */
export const pointAlong = (points, t) => {
  let left = Math.min(1, Math.max(0, t)) * routeLength(points);
  for (const segment of segmentsOf(points)) {
    const length = segmentLength(segment);
    if (left <= length && length > 0) {
      const k = left / length;
      const { p, q } = segment;
      return { x: p.x + (q.x - p.x) * k, y: p.y + (q.y - p.y) * k };
    }
    left -= length;
  }
  return points[points.length - 1];
};

/**
 * Candidate routes for one arrow, best first. `lanes` are the distances a detour
 * may stand off the boxes, so two detours need not share one line.
 */
const routesFor = (a, b, shift, lanes) => {
  const ca = centre(a);
  const cb = centre(b);
  const right = cb.x > ca.x;
  const down = cb.y > ca.y;
  const sideX = (rect, toRight) => (toRight ? rect.x + rect.w : rect.x);
  const sideY = (rect, toBottom) => (toBottom ? rect.y + rect.h : rect.y);
  // A detour leaves and arrives off centre, on the side that faces the other
  // box, so one that ends at a box does not run along one that starts there.
  const off = (size) => Math.min(40, size / 4);

  if (Math.abs(ca.y - cb.y) < 1) {
    const y = ca.y + shift;
    const detour = (toBottom, lane) => {
      const turn = toBottom ? Math.max(a.y + a.h, b.y + b.h) + lane : Math.min(a.y, b.y) - lane;
      const from = ca.x + (right ? off(a.w) : -off(a.w));
      const to = cb.x + (right ? -off(b.w) : off(b.w));
      return [
        { x: from, y: sideY(a, toBottom) },
        { x: from, y: turn },
        { x: to, y: turn },
        { x: to, y: sideY(b, toBottom) },
      ];
    };
    return [
      [{ x: sideX(a, right), y }, { x: sideX(b, !right), y }],
      ...lanes.map((lane) => detour(true, lane)),
      ...lanes.map((lane) => detour(false, lane)),
    ];
  }
  if (Math.abs(ca.x - cb.x) < 1) {
    const x = ca.x + shift;
    const detour = (toRight, lane) => {
      const turn = toRight ? Math.max(a.x + a.w, b.x + b.w) + lane : Math.min(a.x, b.x) - lane;
      const from = ca.y + (down ? off(a.h) : -off(a.h));
      const to = cb.y + (down ? -off(b.h) : off(b.h));
      return [
        { x: sideX(a, toRight), y: from },
        { x: turn, y: from },
        { x: turn, y: to },
        { x: sideX(b, toRight), y: to },
      ];
    };
    return [
      [{ x, y: sideY(a, down) }, { x, y: sideY(b, !down) }],
      ...lanes.map((lane) => detour(true, lane)),
      ...lanes.map((lane) => detour(false, lane)),
    ];
  }
  const between = (from, to, share) => from + (to - from) * share + shift;
  const shares = [0.5, 0.3, 0.7];
  return [
    ...shares.map((share) => {
      const x = between(sideX(a, right), sideX(b, !right), share);
      return [
        { x: sideX(a, right), y: ca.y + shift },
        { x, y: ca.y + shift },
        { x, y: cb.y + shift },
        { x: sideX(b, !right), y: cb.y + shift },
      ];
    }),
    ...shares.map((share) => {
      const y = between(sideY(a, down), sideY(b, !down), share);
      return [
        { x: ca.x + shift, y: sideY(a, down) },
        { x: ca.x + shift, y },
        { x: cb.x + shift, y },
        { x: cb.x + shift, y: sideY(b, !down) },
      ];
    }),
    [
      { x: sideX(a, right), y: ca.y + shift },
      { x: cb.x + shift, y: ca.y + shift },
      { x: cb.x + shift, y: sideY(b, !down) },
    ],
    [
      { x: ca.x + shift, y: sideY(a, down) },
      { x: ca.x + shift, y: cb.y + shift },
      { x: sideX(b, !right), y: cb.y + shift },
    ],
  ];
};

/**
 * Two arrows that share neither end and run along one line read as one arrow.
 * Arrows into one box, or out of one, may share a run: that is how they join.
 */
const runsAlong = (pointsA, pointsB) =>
  segmentsOf(pointsA).some((s) =>
    segmentsOf(pointsB).some((t) => {
      const flat = (segment) => Math.abs(segment.p.y - segment.q.y) < 1;
      if (flat(s) !== flat(t)) return false;
      const [line, along] = flat(s) ? ['y', 'x'] : ['x', 'y'];
      if (Math.abs(s.p[line] - t.p[line]) > 12) return false;
      const low = Math.max(Math.min(s.p[along], s.q[along]), Math.min(t.p[along], t.q[along]));
      const high = Math.min(Math.max(s.p[along], s.q[along]), Math.max(t.p[along], t.q[along]));
      return high - low > 4;
    }),
  );

/**
 * A label sits on the longest straight run of its arrow. Beside a twin arrow on a
 * vertical run it stands outside the pair, where the two cannot cover each other.
 */
const edgeLabelRect = (points, label, size, shift) => {
  const w = textWidth(label, size) + 20;
  const h = Math.round(size * 1.4);
  const run = segmentsOf(points).reduce((best, segment) => (segmentLength(segment) > segmentLength(best) ? segment : best));
  const middle = { x: (run.p.x + run.q.x) / 2, y: (run.p.y + run.q.y) / 2 - h / 2 };
  const vertical = Math.abs(run.p.x - run.q.x) < 1;
  if (shift && vertical) return { x: shift < 0 ? middle.x - w - 10 : middle.x + 10, y: middle.y, w, h };
  return { x: middle.x - w / 2, y: middle.y, w, h };
};

const readNodes = (visual, fail) => {
  const nodes = Array.isArray(visual.nodes) ? visual.nodes : [];
  const ids = new Map();
  const cells = new Map();
  if (!nodes.length) fail('diagram-empty', 'a diagram needs at least one node');
  for (const node of nodes) {
    const name = node.id ?? `"${node.label ?? ''}"`;
    if (!node.id) fail('diagram-node-id', `node ${name} has no id`);
    else if (ids.has(node.id)) fail('diagram-node-id', `two nodes share the id "${node.id}"`);
    ids.set(node.id, node);
    if (!node.label) fail('diagram-label', `node ${name} has no label`);
    if (node.icon && !Object.hasOwn(ICONS, node.icon)) {
      const near = suggestIcons(node.icon);
      fail('diagram-icon', `node ${name} names icon "${node.icon}", which the kit does not carry${near.length ? `; close names: ${near.join(', ')}` : ''}`);
    }
    for (const key of ['col', 'row']) {
      const value = node[key] ?? 0;
      if (!Number.isInteger(value) || value < 0) fail('diagram-cell', `node ${name} needs a whole ${key} of 0 or more`);
    }
    const cell = `${node.col ?? 0},${node.row ?? 0}`;
    if (cells.has(cell)) fail('diagram-cell', `nodes ${cells.get(cell)} and ${name} share column ${node.col ?? 0}, row ${node.row ?? 0}`);
    else cells.set(cell, name);
  }
  return { nodes, ids };
};

const readEdges = (visual, ids, fail) =>
  (Array.isArray(visual.edges) ? visual.edges : []).filter((edge) => {
    if (edge.from === edge.to) {
      fail('diagram-edge', `an arrow joins ${edge.from} to itself`);
      return false;
    }
    const unknown = [edge.from, edge.to].filter((end) => !ids.has(end));
    for (const end of unknown) fail('diagram-edge', `an arrow names "${end}", which is no node's id`);
    return unknown.length === 0;
  });

/**
 * Place a diagram in a box of canvas pixels. Every rect and point in the result
 * is relative to that box's own top-left corner.
 */
export const diagramLayout = (visual, box) => {
  const problems = [];
  const fail = (code, message) => problems.push({ code, message });
  const { nodes, ids } = readNodes(visual, fail);
  const edges = readEdges(visual, ids, fail);
  if (problems.length) return { nodes: [], edges: [], problems, labelSize: 0, captionLines: [], captionHeight: 0 };

  const cols = Math.max(...nodes.map((node) => node.col ?? 0)) + 1;
  const rows = Math.max(...nodes.map((node) => node.row ?? 0)) + 1;
  const caption = captionLines(visual.caption, box.w);
  const captionHeight = caption.length ? caption.length * CAPTION_LINE + 13 : 0;
  const colOf = (id) => ids.get(id).col ?? 0;
  const rowOf = (id) => ids.get(id).row ?? 0;
  const sameRow = (edge) => rowOf(edge.from) === rowOf(edge.to);
  const skips = (edge) => sameRow(edge) && Math.abs(colOf(edge.from) - colOf(edge.to)) > 1;
  const passes = Math.min(3, edges.filter(skips).length);
  const reserve = passes ? UNDERPASS + (passes - 1) * 34 : 0;
  const area = { x: 0, y: captionHeight, w: box.w, h: box.h - captionHeight - reserve };
  const cellW = area.w / cols;
  const cellH = area.h / rows;

  // A gap has to hold the widest label on an arrow that crosses it.
  const crossing = edges.filter((edge) => edge.label && sameRow(edge) && !skips(edge));
  const gapFor = (size) => Math.max(0, ...crossing.map((edge) => textWidth(edge.label, size) + 20 + 44));
  let edgeLabelSize = EDGE_LABEL;
  while (edgeLabelSize > MIN_EDGE_LABEL && gapFor(edgeLabelSize) > cellW * 0.52) edgeLabelSize -= 1;
  const gapX = cols > 1 ? Math.max(64, Math.min(110, cellW * 0.22), Math.min(cellW * 0.52, gapFor(edgeLabelSize))) : 0;
  // Rows need room between them only when an arrow runs or turns there.
  const climbs = edges.some((edge) => colOf(edge.from) === colOf(edge.to) || skips(edge));
  const gapY = rows > 1 ? (climbs ? Math.max(56, Math.min(96, cellH * 0.26)) : Math.max(28, Math.min(64, cellH * 0.16))) : 0;
  const nodeW = Math.floor(Math.min(MAX_NODE_W, cellW - gapX));
  const maxNodeH = Math.floor(cellH - gapY);

  const fitNodes = (beside) => {
    for (let size = MAX_LABEL; size >= MIN_LABEL; size -= 1) {
      const sized = nodes.map((node) => contentOf(node, nodeW, size, beside));
      if (sized.every((content) => content.fits && content.height <= maxNodeH)) return { size, contents: sized, ok: true };
    }
    return { size: MIN_LABEL, contents: nodes.map((node) => contentOf(node, nodeW, MIN_LABEL, beside)), ok: false };
  };
  // An icon over its words reads first; beside them only where that leaves the
  // words clearly larger.
  const over = fitNodes(false);
  const side = nodes.some((node) => node.icon) ? fitNodes(true) : over;
  const chosen = (side.ok && !over.ok) || side.size > over.size * 1.15 ? side : over;
  const { size: labelSize, contents } = chosen;
  if (!chosen.ok) {
    nodes.forEach((node, i) => {
      if (!contents[i].fits || contents[i].height > maxNodeH) {
        fail('diagram-text', `node ${node.id} does not fit its ${nodeW}x${maxNodeH} box at ${MIN_LABEL}px; shorten the words, or use fewer columns or rows`);
      }
    });
  }
  const tallest = Math.max(...contents.map((content) => content.height));
  const nodeH = Math.min(maxNodeH, Math.max(tallest + 2 * PAD, Math.round(nodeW * 0.6)));

  const placed = nodes.map((node, i) => ({
    ...contents[i],
    id: node.id,
    x: Math.round(area.x + (node.col ?? 0) * cellW + (cellW - nodeW) / 2),
    y: Math.round(area.y + (node.row ?? 0) * cellH + (cellH - nodeH) / 2),
    w: nodeW,
    h: nodeH,
  }));
  const rectOf = new Map(placed.map((rect) => [rect.id, rect]));
  const lanes = rows > 1 ? [gapY * 0.5, gapY * 0.25, gapY * 0.75] : [UNDERPASS * 0.6, UNDERPASS * 0.6 + 34, UNDERPASS * 0.6 + 68];
  const drawnRoutes = [];

  const drawn = edges.map((edge) => {
    const paired = edges.some((other) => other.from === edge.to && other.to === edge.from);
    // Opposite arrows between two boxes sit side by side, not on one line.
    const shift = paired ? (edge.from < edge.to ? -20 : 20) : 0;
    const others = placed.filter((rect) => rect.id !== edge.from && rect.id !== edge.to);
    const isClear = (points) =>
      segmentsOf(points).every((segment) => {
        const thin = segmentRect(segment);
        return (
          thin.x >= -1 && thin.y >= captionHeight - 1 && thin.x + thin.w <= box.w + 1 && thin.y + thin.h <= box.h + 1 &&
          others.every((rect) => !rectsOverlap(thin, inflate(rect, 6)))
        );
      });
    const ownLine = (points) =>
      drawnRoutes.every((other) => other.from === edge.from || other.to === edge.to || !runsAlong(points, other.points));
    const routes = routesFor(rectOf.get(edge.from), rectOf.get(edge.to), shift, lanes);
    const clear = routes.find((points) => isClear(points) && ownLine(points));
    if (!clear) fail('diagram-edge-through', `the arrow ${edge.from} → ${edge.to} has no clear path past the other boxes and arrows; move one of them to another row or column`);
    const points = clear ?? routes[0];
    drawnRoutes.push({ from: edge.from, to: edge.to, points });
    const label = edge.label ? { ...edgeLabelRect(points, edge.label, edgeLabelSize, shift), text: edge.label, size: edgeLabelSize } : null;
    return { from: edge.from, to: edge.to, points, length: routeLength(points), label };
  });

  drawn.forEach((edge, i) => {
    if (!edge.label) return;
    const name = `the label "${edge.label.text}" on ${edge.from} → ${edge.to}`;
    const { x, y, w, h } = edge.label;
    if (x < 0 || x + w > box.w || y < 0 || y + h > box.h) fail('diagram-edge-label', `${name} runs outside the diagram`);
    if (placed.some((rect) => rectsOverlap(edge.label, rect))) fail('diagram-edge-label', `${name} covers a box; shorten it`);
    for (const other of drawn.slice(i + 1)) {
      if (other.label && rectsOverlap(edge.label, other.label)) fail('diagram-edge-label', `${name} covers the label "${other.label.text}"`);
    }
  });

  return { nodes: placed, edges: drawn, problems, labelSize, captionLines: caption, captionHeight };
};

/**
 * A flow as a diagram: the same boxes in reading order, joined one to the next.
 * One row reads best, so it takes another only where that leaves the words a
 * quarter larger, and runs every second row right to left so no arrow has to
 * cross the frame.
 */
export const flowAsDiagram = (visual, box) => {
  const nodes = visual.nodes ?? [];
  const build = (rows) => {
    const cols = Math.ceil(nodes.length / rows);
    return {
      ...visual,
      kind: 'diagram',
      nodes: nodes.map((node, i) => {
        const row = Math.floor(i / cols);
        const along = i % cols;
        return { ...node, id: `n${i + 1}`, row, col: row % 2 ? cols - 1 - along : along };
      }),
      edges: nodes.slice(1).map((_, i) => ({ from: `n${i + 1}`, to: `n${i + 2}` })),
    };
  };
  let best = null;
  for (let rows = 1; rows <= Math.min(3, Math.max(1, nodes.length)); rows += 1) {
    const diagram = build(rows);
    const layout = diagramLayout(diagram, box);
    const score = layout.problems.length ? -1 : layout.labelSize;
    if (!best || score > Math.max(0, best.score) * 1.25) best = { diagram, layout, score };
  }
  return best;
};
