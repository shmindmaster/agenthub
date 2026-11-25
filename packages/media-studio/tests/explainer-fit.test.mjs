// What a viewer would see go wrong is found before the render: a picture that
// leaves its region, words that are cut, an arrow through a box. These tests
// hold the numbers the renderer and the builder share.
import test from 'node:test';
import assert from 'node:assert/strict';
import { ICONS, captionLines, diagramLayout, flowAsDiagram, pointAlong, rectsOverlap, routeLength, suggestIcons } from '../kit/explainer/diagram.mjs';
import {
  MAX_ZOOM, MIN_ZOOM, canFit, checkShotLayout, checklistLayout, contrastLayout, contrastSides, fitTitle, fitVisual, pictureBox,
  svgLayout, timelineLayout,
} from '../kit/explainer/fit.mjs';
import { FAMILIES } from '../kit/explainer/grammar.mjs';
import { fitHeadline, layoutFor, textWidth } from '../kit/explainer/layout.mjs';
import { build, clone, cueSheet, plan, receipts } from './fixtures/explainer/fixture.mjs';

const canvases = [{ width: 1600, height: 1000 }, { width: 1920, height: 1080 }, { width: 1280, height: 720 }];
const canvas = canvases[0];
const mechanism = pictureBox('mechanism', layoutFor('mechanism', canvas).hero);

const samples = {
  layers: { kind: 'layers', layers: [{ label: 'Edge' }, { label: 'Service', sub: 'two replicas' }, { label: 'Store' }] },
  sequence: { kind: 'sequence', actors: ['Guest', 'Till', 'Oven'], steps: [{ frm: 0, to: 1, label: 'order' }, { frm: 1, to: 2, label: 'bake' }] },
  map: { kind: 'map', lanes: [{ name: 'FRONT', nodes: [{ label: 'till' }, { label: 'counter' }] }, { name: 'BACK', nodes: [{ label: 'oven' }] }] },
  table: { kind: 'table', headers: ['Day', 'Loaves', 'Left'], rows: [{ cells: ['Monday', '120', '6'] }, { cells: ['Tuesday', '96', '2'] }] },
  code: { kind: 'code', lang: 'ts', lines: [{ text: 'const left = baked - sold;' }, { text: 'return left;' }] },
  chart: { kind: 'chart', items: [{ label: 'Rye', value: 12 }, { label: 'White', value: 30 }] },
  proof: { kind: 'proof', claim: 'Two lines moved.', evidence: 'Revision 14 changed the handoff date.' },
  sidecar: { kind: 'sidecar', claim: 'One owner.', support: 'From the first day.' },
};

test('every body the engine zooms can be measured, and a fitted body stays in its region', () => {
  for (const [kind, visual] of Object.entries(samples)) {
    assert.equal(canFit(visual), true, kind);
    for (const size of canvases) {
      const family = Object.keys(FAMILIES).find((name) => FAMILIES[name].kinds.includes(kind));
      const box = pictureBox(family, layoutFor(family, size).hero);
      const fitted = fitVisual(visual, box);
      assert.equal(fitted.overflow, false, `${kind} at ${size.width}`);
      assert.ok(fitted.zoom >= MIN_ZOOM && fitted.zoom <= MAX_ZOOM);
      assert.ok(fitted.height * fitted.zoom <= box.h + 0.01, `${kind} is taller than its region at ${size.width}`);
      assert.ok(Math.abs(fitted.width * fitted.zoom - box.w) < 0.01, `${kind} does not use the region's width`);
    }
  }
});

test('every mechanism, layers and evidence kind is either fitted, drawn to its box or a known exception', () => {
  const drawnToBox = ['flow', 'diagram', 'svg'];
  for (const family of ['mechanism', 'layers', 'evidence']) {
    for (const kind of FAMILIES[family].kinds) assert.ok(drawnToBox.includes(kind) || canFit({ kind }), `${family}: ${kind} has no measure`);
  }
});

test('a small table is enlarged, and visualScale can shrink a body but never push it out', () => {
  const box = pictureBox('evidence', layoutFor('evidence', canvas).hero);
  const natural = fitVisual(samples.table, box);
  assert.ok(natural.zoom > 1.3, `zoom ${natural.zoom}`);
  assert.equal(fitVisual(samples.table, box, 1.6).zoom, natural.zoom);
  assert.ok(fitVisual(samples.table, box, 0.8).zoom < natural.zoom);
});

test('a body too large for its region is reported, not clipped', () => {
  const rows = Array.from({ length: 30 }, (_, i) => ({ cells: [`Row ${i}`, '1', '2'] }));
  assert.equal(fitVisual({ ...samples.table, rows }, mechanism).overflow, true);
  const code = { kind: 'code', lines: [{ text: 'x'.repeat(200) }] };
  assert.equal(fitVisual(code, mechanism).overflow, true);
});

test('a title uses its row: one short line is large, a long one wraps, an endless one is refused', () => {
  const row = layoutFor('mechanism', canvas).title;
  const short = fitTitle('Three commitments break.', row);
  assert.equal(short.size, 64);
  const long = fitTitle('Three commitments break at once and nobody on the floor has been told which of them moved yet', row);
  assert.equal(long.lines.length, 2);
  assert.equal(long.overflow, false);
  assert.equal(fitTitle('word '.repeat(120), row).overflow, true);
});

test('two lines of title have a size on every canvas, and one word too wide for the row is refused', () => {
  for (const size of canvases) {
    const region = layoutFor('mechanism', size).title;
    assert.equal(fitTitle('Where the bread goes after the last customer of the day has left the shop', region).overflow, false, `${size.width}`);
  }
  const wide = fitHeadline('Donaudampfschifffahrtsgesellschaft', { maxWidth: 300, maxSize: 120, minSize: 60, maxLines: 2 });
  assert.equal(wide.overflow, true);
  const fits = fitHeadline('Donaudampfschifffahrt', { maxWidth: 900, maxSize: 120, minSize: 20, maxLines: 2 });
  assert.equal(fits.overflow, false);
  for (const line of fits.lines) assert.ok(textWidth(line, fits.size, -0.02) <= 900);
});

test('contrast fills its panels with large type and refuses a wall of text', () => {
  const hero = layoutFor('contrast', canvas).hero;
  const sides = contrastSides(plan.shots[3].visual);
  const fitted = contrastLayout(sides, hero);
  assert.equal(fitted.itemSize, 68);
  assert.ok(fitted.panelH >= hero.h * 0.7);
  const wall = { left: { title: 'A', items: Array.from({ length: 14 }, () => ({ text: 'a line that is long enough to wrap in its panel' })) }, right: { title: 'B', items: [] } };
  assert.equal(contrastLayout(wall, hero).overflow, true);
  const stacked = contrastSides({ kind: 'beforeafter', before: { title: 'B', items: ['x'] }, after: { title: 'A', items: ['y'] } });
  assert.deepEqual(stacked.left, { title: 'B', items: [{ text: 'x' }] });
});

test('a checklist row grows with the room it has', () => {
  const hero = layoutFor('checklist', canvas).hero;
  const three = checklistLayout(plan.shots[4].visual.items, hero);
  const five = checklistLayout(Array.from({ length: 5 }, () => ({ text: 'short' })), hero);
  assert.ok(three.rowH > five.rowH && three.size >= five.size);
  assert.ok(three.size >= 48);
  assert.equal(checklistLayout([{ text: 'w'.repeat(200) }], hero).overflow, true);
});

test('timeline events are evenly spaced on one rail inside the region', () => {
  const hero = layoutFor('timeline', canvas).hero;
  const events = ['Monday', 'Tuesday', 'Wednesday', 'Thursday'].map((at) => ({ at, label: 'Bake the rye' }));
  const fitted = timelineLayout(events, hero);
  assert.equal(fitted.overflow, false);
  assert.ok(fitted.labelSize >= 40 && fitted.dateSize >= 40);
  const steps = fitted.centres.slice(1).map((x, i) => x - fitted.centres[i]);
  assert.ok(Math.max(...steps) - Math.min(...steps) <= 1);
  assert.ok(fitted.railY > 0 && fitted.railY < hero.h);
  assert.equal(timelineLayout([{ at: 'x'.repeat(140), label: 'y' }], hero).overflow, true);
});

test('a timeline wraps a long date and label while there is height, and refuses when there is not', () => {
  const events = Array.from({ length: 6 }, (_, i) => ({ at: 'Wednesday evening', label: 'The second oven is switched off before closing time', sub: `step ${i + 1}` }));
  const hero = layoutFor('timeline', canvas).hero;
  assert.equal(timelineLayout(events, hero).overflow, false);
  assert.equal(timelineLayout(events, { ...hero, h: 120 }).overflow, true);
  assert.equal(timelineLayout([{ at: 'Donaudampfschifffahrtsgesellschaft', label: 'x' }], { ...hero, w: 260 }).overflow, true);
});

test('an svg scene takes the room it is left and reports its smallest text', () => {
  const svg = { kind: 'svg', viewBox: '0 0 1200 520', groups: [{ svg: '<text font-size="30">a</text><text font-size=\'12\'>b</text>' }] };
  const fitted = svgLayout(svg, mechanism);
  assert.ok(fitted.width <= mechanism.w && fitted.height <= mechanism.h);
  assert.ok(Math.abs(fitted.minType - (12 * fitted.width) / 1200) < 0.1);
  assert.equal(svgLayout({ kind: 'svg', groups: [] }, mechanism).minType, null);
});

/* --------------------------------------------------------------- diagram -- */

const diagram = {
  kind: 'diagram',
  nodes: [
    { id: 'guest', label: 'Guest', icon: 'user', col: 0, row: 0 },
    { id: 'till', label: 'Till', icon: 'store', col: 1, row: 0 },
    { id: 'oven', label: 'Oven', icon: 'flame', col: 2, row: 0 },
    { id: 'shelf', label: 'Shelf', col: 1, row: 1 },
  ],
  edges: [{ from: 'guest', to: 'till', label: 'order' }, { from: 'till', to: 'oven' }, { from: 'oven', to: 'shelf', dashed: true }],
};

const inBox = (rect, box) => rect.x >= 0 && rect.y >= 0 && rect.x + rect.w <= box.w && rect.y + rect.h <= box.h;

test('a diagram places every box inside its region without overlap', () => {
  for (const size of canvases) {
    const box = pictureBox('mechanism', layoutFor('mechanism', size).hero);
    const placed = diagramLayout(diagram, box);
    assert.deepEqual(placed.problems, [], `${size.width}`);
    placed.nodes.forEach((node, i) => {
      assert.ok(inBox(node, box), `${node.id} leaves the region`);
      placed.nodes.slice(i + 1).forEach((other) => assert.equal(rectsOverlap(node, other), false, `${node.id}/${other.id}`));
    });
  }
});

test('an arrow starts and ends on the edges of the boxes it names', () => {
  const placed = diagramLayout(diagram, mechanism);
  const onEdge = (p, r) =>
    (Math.abs(p.x - r.x) < 1 || Math.abs(p.x - r.x - r.w) < 1 || Math.abs(p.y - r.y) < 1 || Math.abs(p.y - r.y - r.h) < 1) &&
    p.x >= r.x - 1 && p.x <= r.x + r.w + 1 && p.y >= r.y - 1 && p.y <= r.y + r.h + 1;
  for (const edge of placed.edges) {
    const rect = (id) => placed.nodes.find((node) => node.id === id);
    assert.ok(onEdge(edge.points[0], rect(edge.from)), `${edge.from} start`);
    assert.ok(onEdge(edge.points.at(-1), rect(edge.to)), `${edge.to} end`);
    for (let i = 1; i < edge.points.length; i += 1) {
      const [p, q] = [edge.points[i - 1], edge.points[i]];
      assert.ok(Math.abs(p.x - q.x) < 1 || Math.abs(p.y - q.y) < 1, 'segments are straight');
    }
  }
});

test('an arrow that skips a box goes round it, and one with no way round is refused', () => {
  const row = { kind: 'diagram', nodes: ['a', 'b', 'c'].map((id, col) => ({ id, label: id, col })), edges: [{ from: 'a', to: 'c' }] };
  const placed = diagramLayout(row, mechanism);
  assert.deepEqual(placed.problems, []);
  assert.equal(placed.edges[0].points.length, 4);
  // Every cell of a 3x3 grid is taken, and the arrow joins opposite corners.
  const full = { kind: 'diagram', nodes: [], edges: [{ from: 'n00', to: 'n22' }] };
  for (let r = 0; r < 3; r += 1) for (let c = 0; c < 3; c += 1) full.nodes.push({ id: `n${c}${r}`, label: 'x', col: c, row: r });
  const through = diagramLayout(full, mechanism);
  assert.deepEqual(through.problems.map((problem) => problem.code), ['diagram-edge-through']);
});

const flatRuns = (points) => points.slice(1).map((q, i) => ({ p: points[i], q })).filter(({ p, q }) => p.y === q.y);

test('two arrows that skip boxes in one row never share a line', () => {
  const nodes = ['a', 'b', 'c', 'd', 'e'].map((id, col) => ({ id, label: id, col }));
  const placed = diagramLayout({ kind: 'diagram', nodes, edges: [{ from: 'a', to: 'c' }, { from: 'b', to: 'd' }, { from: 'c', to: 'e' }] }, mechanism);
  assert.deepEqual(placed.problems, []);
  const runs = placed.edges.map((edge) => flatRuns(edge.points));
  for (let i = 0; i < runs.length; i += 1) {
    for (let j = i + 1; j < runs.length; j += 1) {
      for (const s of runs[i]) for (const t of runs[j]) {
        const shared = Math.min(Math.max(s.p.x, s.q.x), Math.max(t.p.x, t.q.x)) - Math.max(Math.min(s.p.x, s.q.x), Math.min(t.p.x, t.q.x));
        assert.ok(shared <= 4 || Math.abs(s.p.y - t.p.y) > 12, `arrows ${i} and ${j} run along one line`);
      }
    }
  }
  for (const edge of placed.edges) for (const point of edge.points) assert.ok(point.y <= mechanism.h);
  for (const size of canvases) {
    const box = pictureBox('mechanism', layoutFor('mechanism', size).hero);
    assert.deepEqual(diagramLayout({ kind: 'diagram', caption: 'one after the other', nodes, edges: [{ from: 'a', to: 'c' }, { from: 'b', to: 'd' }, { from: 'c', to: 'e' }, { from: 'a', to: 'b' }] }, box).problems, [], `${size.width}`);
  }
});

test('labels on a pair of vertical arrows stand on their own sides', () => {
  const nodes = [{ id: 'a', label: 'Till', col: 0, row: 0 }, { id: 'b', label: 'Oven', col: 0, row: 1 }];
  const placed = diagramLayout({ kind: 'diagram', nodes, edges: [{ from: 'a', to: 'b', label: 'order' }, { from: 'b', to: 'a', label: 'bread' }] }, mechanism);
  assert.deepEqual(placed.problems, []);
  const [one, two] = placed.edges;
  assert.equal(rectsOverlap(one.label, two.label), false);
  for (const [own, other] of [[one, two], [two, one]]) {
    const left = own.points[0].x < other.points[0].x;
    if (left) assert.ok(own.label.x + own.label.w < own.points[0].x);
    else assert.ok(own.label.x > own.points[0].x);
  }
});

test('a label on a vertical detour stands away from the boxes, and a pair of detours nests', () => {
  const nodes = ['a', 'b', 'c'].map((id, row) => ({ id, label: id, col: 0, row }));
  const column = (edges) => diagramLayout({ kind: 'diagram', nodes, edges }, mechanism);
  assert.deepEqual(column([{ from: 'a', to: 'c', label: 'ask' }]).problems, []);
  assert.deepEqual(column([{ from: 'a', to: 'c', label: 'ask' }, { from: 'c', to: 'a', label: 'x' }]).problems, []);
  // A full grid has no room beside the line, so a short label stays on it.
  const grid = { kind: 'diagram', nodes: [], edges: [{ from: 'n00', to: 'n02', label: 'ok' }] };
  for (let r = 0; r < 3; r += 1) for (let c = 0; c < 3; c += 1) grid.nodes.push({ id: `n${c}${r}`, label: 'x', col: c, row: r });
  assert.deepEqual(diagramLayout(grid, pictureBox('mechanism', layoutFor('mechanism', canvases[2]).hero)).problems, []);
  const row = ['a', 'b', 'c'].map((id, col) => ({ id, label: id, col, icon: 'flame' }));
  for (const size of canvases) {
    const box = pictureBox('mechanism', layoutFor('mechanism', size).hero);
    assert.deepEqual(diagramLayout({ kind: 'diagram', caption: 'there and back', nodes: row, edges: [{ from: 'a', to: 'c' }, { from: 'c', to: 'a' }] }, box).problems, [], `${size.width}`);
  }
});

test('a long caption wraps and takes its room from the picture', () => {
  const caption = 'how a day at the bakery turns into the forecast for the next day and the day after that one';
  assert.ok(captionLines(caption, 700).length > 1);
  const tall = diagramLayout({ ...diagram, caption }, { w: 700, h: 700 });
  const short = diagramLayout({ ...diagram, caption: 'how' }, { w: 700, h: 700 });
  assert.ok(tall.captionHeight > short.captionHeight);
  assert.equal(tall.captionLines.join(' '), caption.toUpperCase());
  const size = { w: 700, h: 700 };
  assert.ok(fitVisual({ ...samples.table, caption }, size).zoom <= fitVisual(samples.table, size).zoom);
});

test('two arrows between the same boxes run side by side', () => {
  const pair = { kind: 'diagram', nodes: [{ id: 'a', label: 'A', col: 0 }, { id: 'b', label: 'B', col: 1 }], edges: [{ from: 'a', to: 'b' }, { from: 'b', to: 'a' }] };
  const placed = diagramLayout(pair, mechanism);
  assert.deepEqual(placed.problems, []);
  assert.ok(Math.abs(placed.edges[0].points[0].y - placed.edges[1].points[0].y) >= 30);
});

test('a diagram names what is wrong with it', () => {
  const codes = (visual, box = mechanism) => diagramLayout({ kind: 'diagram', ...visual }, box).problems.map((problem) => problem.code);
  const a = { id: 'a', label: 'A', col: 0 };
  assert.deepEqual(codes({ nodes: [] }), ['diagram-empty']);
  assert.deepEqual(codes({ nodes: [a, { id: 'b', label: 'B', col: 0 }] }), ['diagram-cell']);
  assert.ok(codes({ nodes: [a, { id: 'a', label: 'B', col: 1 }] }).includes('diagram-node-id'));
  assert.deepEqual(codes({ nodes: [a], edges: [{ from: 'a', to: 'z' }] }), ['diagram-edge']);
  assert.deepEqual(codes({ nodes: [a], edges: [{ from: 'a', to: 'a' }] }), ['diagram-edge']);
  assert.deepEqual(codes({ nodes: [{ ...a, col: 0.5 }] }), ['diagram-cell']);
  assert.deepEqual(codes({ nodes: [{ id: 'a', label: 'w'.repeat(80), col: 0 }] }), ['diagram-text']);
  assert.ok(codes({ nodes: [a, { id: 'b', label: 'B', col: 1 }], edges: [{ from: 'a', to: 'b', label: 'a label far too long to sit between two boxes on one row of this frame at any size at all' }] }).includes('diagram-edge-label'));
});

test('an unknown icon is refused with names that are close', () => {
  const layout = diagramLayout({ kind: 'diagram', nodes: [{ id: 'a', label: 'A', icon: 'shopping-kart' }] }, mechanism);
  assert.equal(layout.problems[0].code, 'diagram-icon');
  assert.match(layout.problems[0].message, /shopping-cart/);
  assert.deepEqual(suggestIcons('zzz'), []);
  // A name on Object.prototype is not an icon.
  assert.equal(diagramLayout({ kind: 'diagram', nodes: [{ id: 'a', label: 'A', icon: 'constructor' }] }, mechanism).problems.length, 1);
});

test('the vendored icons are plain shapes the renderer can draw', () => {
  const allowed = new Set(['path', 'circle', 'rect', 'line', 'ellipse', 'polyline', 'polygon']);
  assert.ok(Object.keys(ICONS).length >= 200);
  for (const [name, parts] of Object.entries(ICONS)) {
    for (const [tag, attributes] of parts) {
      assert.ok(allowed.has(tag), `${name}: ${tag}`);
      for (const key of Object.keys(attributes)) assert.ok(!/^on|href|style|-/.test(key), `${name}: ${key}`);
    }
  }
});

test('a flow becomes a diagram in reading order, on the rows that keep it largest', () => {
  const nodes = (n) => Array.from({ length: n }, (_, i) => ({ label: `Step ${i + 1}`, at: i }));
  const three = flowAsDiagram({ kind: 'flow', nodes: nodes(3) }, mechanism);
  assert.deepEqual(three.layout.problems, []);
  assert.equal(three.diagram.edges.length, 2);
  const long = flowAsDiagram({ kind: 'flow', nodes: nodes(8).map((node) => ({ ...node, label: `${node.label} of the long bake` })) }, mechanism);
  assert.deepEqual(long.layout.problems, []);
  const rows = new Set(long.diagram.nodes.map((node) => node.row));
  assert.ok(rows.size >= 2, 'eight steps do not stay on one row');
  const turn = long.diagram.nodes.findIndex((node) => node.row === 1);
  assert.equal(long.diagram.nodes[turn].col, long.diagram.nodes[turn - 1].col, 'the second row starts under the end of the first');
  assert.deepEqual(flowAsDiagram({ kind: 'flow', nodes: [] }, mechanism).layout.problems.map((problem) => problem.code), ['diagram-empty']);
});

test('a point travels the whole of a bent route', () => {
  const route = [{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 30 }];
  assert.equal(routeLength(route), 40);
  assert.deepEqual(pointAlong(route, 0), { x: 0, y: 0 });
  assert.deepEqual(pointAlong(route, 0.5), { x: 10, y: 10 });
  assert.deepEqual(pointAlong(route, 1), { x: 10, y: 30 });
});

/* ------------------------------------------------------------ the builder -- */

const withVisual = (index, visual, extra = {}) => {
  const changed = clone(plan);
  Object.assign(changed.shots[index], extra, { visual });
  return build({ plan: changed });
};

test('the fixture film has no layout problem at any size', () => {
  for (const size of canvases) {
    const result = build(size);
    assert.deepEqual(result.errors, [], `${size.width}`);
  }
});

test('the builder refuses a diagram that names an icon or an arrow end that does not exist', () => {
  const result = withVisual(1, { ...diagram, nodes: diagram.nodes.map((node) => ({ ...node, icon: 'no-such-icon' })) });
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /b: diagram-icon/);
  assert.equal(result.props, null);
});

test('the builder accepts a word-anchored diagram and times its boxes', () => {
  const result = withVisual(1, {
    ...diagram,
    nodes: diagram.nodes.map((node, i) => ({ ...node, at: ['@Three', '@commitments', '@break', '@once'][i] })),
  });
  assert.deepEqual(result.errors, []);
  assert.equal(result.props.shots[1].beats.length, 4);
  assert.equal(result.props.shots[1].family, 'mechanism');
});

test('the builder refuses words that would be cut', () => {
  const title = withVisual(1, plan.shots[1].visual, { title: 'word '.repeat(120) });
  assert.match(title.errors.join('\n'), /b: layout-overflow: the title/);
  const table = withVisual(2, { ...samples.table, rows: Array.from({ length: 40 }, () => ({ cells: ['a', 'b', 'c'] })) });
  assert.match(table.errors.join('\n'), /c: layout-overflow: the table/);
  const headline = clone(plan);
  headline.shots[0].title = 'overlong words here '.repeat(20);
  assert.match(build({ plan: headline }).errors.join('\n'), /a: layout-overflow/);
});

test('small type is advice, never a refusal', () => {
  const result = withVisual(1, { kind: 'svg', groups: [{ at: 1, svg: '<text font-size="8">tiny</text>' }] });
  assert.deepEqual(result.errors, []);
  assert.match(result.report.warnings.join('\n'), /b: layout-small/);
});

test('a sequence step must name actors the sequence has', () => {
  const result = withVisual(1, { ...samples.sequence, steps: [{ frm: 0, to: 5, label: 'lost' }] });
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /b: sequence-step: step 1 names actor 5/);
});

test('a single word may use the whole headline row', () => {
  const small = { width: 1280, height: 720 };
  const word = clone(plan);
  word.shots[0].title = 'order_confirmation_webhook';
  assert.deepEqual(build({ plan: word, ...small }).errors, []);
  word.shots[0].title = 'order_confirmation_webhook_and_then_some_more';
  assert.match(build({ plan: word, ...small }).errors.join('\n'), /a: layout-overflow/);
});

test('a proof shot is checked for the title it opens on', () => {
  const result = withVisual(2, samples.proof, { title: 'an overlong title here '.repeat(20) });
  assert.match(result.errors.join('\n'), /c: layout-overflow: "an overlong title/);
});

test('a visual missing its parts is an error, not a crash', () => {
  const result = withVisual(1, { kind: 'sequence' });
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /b: layout: the sequence cannot be laid out/);
});

test('a timeline event prints its date and lands on its word', () => {
  const visual = {
    kind: 'timeline',
    events: [{ at: 'Monday', label: 'Sold out', beat: '@Three' }, { at: 'Tuesday', label: 'Left over', beat: '@once' }],
  };
  const result = withVisual(1, visual, { archetype: 'timeline' });
  assert.deepEqual(result.errors, []);
  const shot = result.props.shots[1];
  assert.equal(shot.visual.events[0].at, 'Monday');
  assert.equal(typeof shot.visual.events[0].beat, 'number');
  assert.equal(shot.beats.length, 2);
  assert.ok(shot.beats[1].atSeconds > shot.beats[0].atSeconds);
  const bad = withVisual(1, { ...visual, events: [{ at: 'Monday', label: 'x', beat: '@never' }] }, { archetype: 'timeline' });
  assert.match(bad.errors.join('\n'), /events\[0\]\.beat: word "never"/);
});

test('a numeric date on a timeline event is a label, not a time', () => {
  const result = withVisual(1, { kind: 'timeline', events: [{ at: 2019, label: 'Opened' }, { at: 2024, label: 'Moved' }] }, { archetype: 'timeline' });
  assert.deepEqual(result.errors, []);
  assert.equal(result.props.shots[1].beats.length, 0);
});

test('checkShotLayout covers every family without throwing on its own sample', () => {
  for (const shot of build().props.shots) assert.deepEqual(checkShotLayout(shot, canvas).errors, [], shot.id);
  assert.equal(cueSheet.cues.length, Object.keys(receipts).length);
});
