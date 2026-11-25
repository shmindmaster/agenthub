/**
 * Fit: how large a picture can be drawn inside its region, worked out before the
 * render and without measuring the DOM.
 *
 * The table, chart, code and layer bodies in kit/src are drawn at fixed pixel
 * sizes for a slide. Here their natural size is estimated from those same sizes
 * and the renderer zooms the body to fill the region it was given. The builder
 * runs the same numbers and refuses a shot whose words would be cut or whose
 * parts would run past the region.
 *
 * The estimates repeat the sizes in kit/src/Visuals.tsx and RichVisuals.tsx.
 * Change a size there and change it here.
 */
import { CAPTION_LINE, boldWidth, captionLines, diagramLayout, flowAsDiagram, plainWidth, wrapBold, wrapPlain } from './diagram.mjs';
import { fitHeadline, layoutFor, textWidth, wrapText } from './layout.mjs';
import { theme } from './theme.mjs';

const MONO_CHAR = 0.6;
/** Tailwind's base sheet (kit/src/index.css) sets this where a body sets no line height. */
const LINE = 1.5;

export const MAX_ZOOM = 2.6;
/** Below this nothing on a body is readable, whatever the frame. */
export const MIN_ZOOM = 0.55;
/** The smallest type a viewer should have to read, on a 1000 px high frame. */
export const MIN_READABLE = 22;

const monoWidth = (text, size) => Math.ceil(String(text ?? '').length * size * MONO_CHAR);

const widestWord = (text, size, measure) =>
  Math.max(0, ...String(text ?? '').split(/\s+/).map((word) => measure(word, size)));

const wrapMono = (text, width, size) => {
  const room = Math.max(1, Math.floor(width / (size * MONO_CHAR)));
  const lines = [];
  let line = '';
  for (const word of String(text ?? '').trim().split(/\s+/).filter(Boolean)) {
    const next = line ? `${line} ${word}` : word;
    if (next.length <= room || !line) line = next;
    else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
};

/** The caption a body prints above itself, wrapped at the width it is drawn. */
const captionHeight = (text, width) => {
  const lines = text ? captionLines(text, width).length : 0;
  return lines ? lines * CAPTION_LINE + 22 : 0;
};

const sum = (values) => values.reduce((total, value) => total + value, 0);

const gaps = (count, gap) => Math.max(0, count - 1) * gap;

/**
 * Natural size of a body drawn `width` px wide: the height it needs (`h`), the
 * narrowest width that does not cut a part (`minW`) and its smallest type.
 */
const MEASURES = {
  layers(v, width) {
    const inner = width - 54 - 46 - 22;
    const heights = v.layers.map((layer) => {
      const label = wrapBold(layer.label, inner, 29).length * 29 * LINE;
      const sub = layer.sub ? wrapMono(layer.sub, inner, 20).length * 20 * LINE + 6 : 0;
      return Math.max(30 * LINE, label + sub) + 42;
    });
    return {
      h: captionHeight(v.caption, width) + sum(heights) + gaps(heights.length, 14),
      minW: 122 + Math.max(0, ...v.layers.map((layer) => Math.max(widestWord(layer.label, 29, boldWidth), widestWord(layer.sub, 20, monoWidth)))),
      type: v.layers.some((layer) => layer.sub) ? 20 : 29,
      bands: heights,
    };
  },

  sequence(v, width) {
    const col = width / Math.max(1, v.actors.length);
    let minW = Math.max(0, ...v.actors.map((actor) => (boldWidth(actor, 21) + 34) * v.actors.length));
    for (const step of v.steps) {
      const middle = step.frm === step.to ? (step.frm + 0.71) * col : ((step.frm + step.to) / 2 + 0.5) * col;
      const need = monoWidth(`${step.label} ▶`, 17) + 18;
      // A label is centred on its arrow, so the nearer frame edge limits it.
      const room = 2 * Math.min(middle, width - middle);
      if (room > 0 && need > room) minW = Math.max(minW, (width * need) / room);
    }
    return { h: captionHeight(v.caption, width) + 21 * LINE + 23 + 10 + 46 * v.steps.length, minW, type: 17 };
  },

  map(v, width) {
    const inner = width - 38;
    let minW = 0;
    const lanes = v.lanes.map((lane) => {
      let x = 0;
      let rowH = 0;
      let height = 0;
      for (const node of lane.nodes) {
        const w = Math.max(monoWidth(node.label, 21), monoWidth(node.sub, 16)) + 30;
        const h = 21 * LINE + 20 + (node.sub ? 16 * LINE + 3 : 0);
        minW = Math.max(minW, w + 38);
        if (x && x + w > inner) {
          height += rowH + 10;
          x = 0;
          rowH = 0;
        }
        x += w + 10;
        rowH = Math.max(rowH, h);
      }
      return 30 + 18 * LINE + 10 + height + rowH;
    });
    const hasSub = v.lanes.some((lane) => lane.nodes.some((node) => node.sub));
    return { h: captionHeight(v.caption, width) + sum(lanes) + gaps(lanes.length, 14), minW, type: hasSub ? 16 : 18 };
  },

  table(v, width) {
    const weightOf = (k) => (k === 0 ? 1.15 : 1);
    const total = sum(v.headers.map((_, k) => weightOf(k)));
    const inner = (k) => (weightOf(k) / total) * (width - 2) - 40;
    const headerWidth = (word) => boldWidth(word.toUpperCase(), 20) + word.length * 1.6;
    const rowHeight = (cells, linesOf, lineOf) => Math.max(0, ...cells.map((cell, k) => linesOf(cell, k).length * lineOf(k))) + 28;
    const header = rowHeight(v.headers, (text, k) => wrapBold(String(text).toUpperCase(), inner(k) * 0.9, 20), () => 20 * LINE);
    const rows = v.rows.map((row) =>
      1 + rowHeight(row.cells, (text, k) => (k === 0 ? wrapBold(text, inner(k), 22) : wrapMono(text, inner(k), 20)), (k) => (k === 0 ? 22 : 20) * 1.4),
    );
    const need = (k, text, measure) => ((Math.max(0, ...String(text ?? '').split(/\s+/).map(measure)) + 40) * total) / weightOf(k) + 2;
    return {
      h: captionHeight(v.caption, width) + 2 + header + sum(rows),
      minW: Math.max(
        ...v.headers.map((text, k) => need(k, text, headerWidth)),
        ...v.rows.flatMap((row) => row.cells.map((text, k) => need(k, text, (word) => (k === 0 ? boldWidth(word, 22) : monoWidth(word, 20))))),
      ),
      type: 20,
    };
  },

  code(v, width) {
    return {
      h: captionHeight(v.caption, width) + 54 + (v.lang ? 17 * LINE + 14 : 0) + v.lines.length * 26 * 1.62,
      // A code line that wraps reads as two lines, so the block is fitted unwrapped.
      minW: 108 + Math.max(0, ...v.lines.map((line) => monoWidth(line.text, 26))),
      type: 26,
    };
  },

  chart(v, width) {
    if (v.form === 'waffle') {
      const notes = v.notes ?? [];
      const inner = Math.min(560, width - 394 - 56);
      const label = wrapBold(v.items[0]?.label, inner, 36).length * 36 * LINE;
      const text = captionHeight(v.caption, inner) + 150 * 0.95 + 10 + label + (notes.length ? 26 + notes.length * 32 * LINE + gaps(notes.length, 12) : 0);
      const textW = Math.max(4 * 150 * 0.62, widestWord(v.items[0]?.label, 36, boldWidth), ...notes.map((note) => boldWidth(note.text, 32) + 36));
      return { h: Math.max(394, text), minW: 394 + 56 + textW, type: 32 };
    }
    const rows = v.items.map((item) => wrapBold(item.label, width, 30).length * 30 * LINE + 8 + 34 * LINE);
    return {
      h: captionHeight(v.caption, width) + sum(rows) + gaps(rows.length, 22),
      minW: Math.max(420, ...v.items.map((item) => widestWord(item.label, 30, boldWidth))),
      type: 30,
    };
  },

  proof(v, width) {
    const inner = width - 74;
    return {
      h: captionHeight(v.kicker, width) + 66 + wrapBold(v.claim, inner, 42).length * 42 * 1.2 + 18 + wrapMono(v.evidence, inner, 24).length * 24 * 1.45,
      minW: 74 + Math.max(widestWord(v.claim, 42, boldWidth), widestWord(v.evidence, 24, monoWidth)),
      type: 24,
    };
  },

  sidecar(v, width) {
    const inner = width - 316;
    const support = v.support ? 16 + wrapPlain(v.support, inner, 24).length * 24 * LINE : 0;
    return {
      h: Math.max(362, wrapBold(v.claim, inner, 40).length * 40 * 1.2 + support),
      minW: 316 + Math.max(widestWord(v.claim, 40, boldWidth), widestWord(v.support, 24, plainWidth)),
      type: v.support ? 24 : 40,
    };
  },
};

export const canFit = (visual) => Boolean(visual && Object.hasOwn(MEASURES, visual.kind));

/**
 * The largest zoom that keeps a body inside `box`. `scale` (a shot's
 * visualScale) can only make it smaller: the body already fills its region, and
 * a larger one would leave it.
 */
export const fitVisual = (visual, box, scale = 1) => {
  if (!canFit(visual)) return { zoom: 1, width: box.w, height: box.h, overflow: false, minType: null };
  const at = (zoom) => {
    const width = box.w / zoom;
    const { h, minW, type, bands = [] } = MEASURES[visual.kind](visual, width);
    return { zoom, width, height: h, bands, minType: type * zoom, fits: h * zoom <= box.h && minW <= width };
  };
  let fitted = null;
  for (let step = Math.round(MAX_ZOOM * 50); step >= Math.round(MIN_ZOOM * 50) && !fitted; step -= 1) {
    const tried = at(step / 50);
    if (tried.fits) fitted = tried;
  }
  const overflow = !fitted;
  let chosen = fitted ?? at(MIN_ZOOM);
  if (fitted && scale > 0 && scale < 1) chosen = at(Math.max(MIN_ZOOM, fitted.zoom * scale));
  return { zoom: chosen.zoom, width: chosen.width, height: chosen.height, bands: chosen.bands, overflow, minType: chosen.minType };
};

/* -------------------------------------------------------- native layouts -- */

const fitsBold = (lines, size, width) => lines.every((line) => boldWidth(line, size) <= width);

/** The line a shot is about, as large as its title row allows. */
export const fitTitle = (text, region, maxSize = 64) => {
  // Two lines always have a size on a row, however short the frame.
  const floor = Math.min(34, Math.floor(region.h / 2.04));
  for (let size = maxSize; size >= floor; size -= 1) {
    const lines = wrapBold(text, region.w, size);
    if (lines.length * size * 1.02 <= region.h && fitsBold(lines, size, region.w)) return { size, lines, overflow: false };
  }
  return { size: floor, lines: wrapBold(text, region.w, floor), overflow: true };
};

/** Two panels either side of the seam, type as large as the fuller one allows. */
export const contrastLayout = (sides, hero) => {
  const gap = 44;
  const pad = 36;
  const bullet = 34;
  const panelW = Math.floor((hero.w - gap) / 2);
  const inner = panelW - 2 * pad;
  const at = (itemSize) => {
    const titleSize = Math.min(76, Math.round(itemSize * 1.16));
    const panels = [sides.left, sides.right].map((side) => {
      const title = wrapBold(side.title, inner, titleSize);
      const items = side.items.map((item) => wrapBold(item.text, inner - bullet, itemSize));
      return {
        height:
          2 * pad + title.length * titleSize * 1.1 + (items.length ? 28 : 0) +
          sum(items.map((lines) => lines.length * itemSize * 1.24)) + gaps(items.length, itemSize * 0.5),
        wide: !fitsBold(title, titleSize, inner) || items.some((lines) => !fitsBold(lines, itemSize, inner - bullet)),
      };
    });
    const height = Math.ceil(Math.max(...panels.map((panel) => panel.height)));
    return { itemSize, titleSize, height, fits: height <= hero.h && !panels.some((panel) => panel.wide) };
  };
  let chosen = at(68);
  while (!chosen.fits && chosen.itemSize > 24) chosen = at(chosen.itemSize - 1);
  return {
    gap, pad, bullet, panelW,
    itemSize: chosen.itemSize,
    titleSize: chosen.titleSize,
    panelH: Math.min(hero.h, Math.max(chosen.height, Math.round(hero.h * 0.72))),
    overflow: !chosen.fits,
  };
};

export const CHECKLIST_VISIBLE = 5;

/** Rows a checklist shows at once and the type that fits one row. */
export const checklistLayout = (items, hero) => {
  const visible = Math.min(CHECKLIST_VISIBLE, Math.max(1, items.length));
  const rowH = Math.floor(Math.min(190, hero.h / visible));
  const gap = 28;
  for (let size = Math.min(64, Math.floor(rowH * 0.5)); size >= 24; size -= 1) {
    const boxSize = Math.round(size * 1.05);
    const inner = hero.w - boxSize - gap;
    const fits = items.every((item) => {
      const lines = wrapBold(item.text, inner, size);
      return lines.length * size * 1.2 <= rowH * 0.92 && fitsBold(lines, size, inner);
    });
    if (fits) return { visible, rowH, size, boxSize, gap, overflow: false };
  }
  return { visible, rowH, size: 24, boxSize: 25, gap, overflow: true };
};

/** One horizontal rail with the events evenly spaced along it. */
export const timelineLayout = (events, hero) => {
  const colW = hero.w / Math.max(1, events.length);
  const inner = colW - 36;
  const BOLD_ROW = { wrap: wrapBold, width: boldWidth };
  const PLAIN_ROW = { wrap: wrapPlain, width: plainWidth };
  // The largest size whose words fit the column in `limit` lines. At the floor
  // any number of lines will do, as long as no word is wider than the column.
  const row = (texts, { wrap, width }, max, min, limit) => {
    const linesAt = (size) => texts.map((text) => wrap(text, inner, size));
    const inside = (all, size) => all.every((lines) => lines.every((line) => width(line, size) <= inner));
    let size = Math.max(min, max);
    while (size > min && !(inside(linesAt(size), size) && linesAt(size).every((lines) => lines.length <= limit))) size -= 1;
    const all = linesAt(size);
    return { size, lines: Math.max(0, ...all.map((lines) => lines.length)), overflow: !inside(all, size) };
  };
  const texts = (key) => events.map((event) => event[key]).filter((text) => text !== undefined && text !== '').map(String);
  // Each row takes the width it has; all three come down together when the
  // stack of them is taller than the region.
  const at = (share) => {
    // A date stays on one line down to 36 px; below that two lines read better.
    const short = row(texts('at'), BOLD_ROW, Math.round(84 * share), 36, 1);
    const date = !short.overflow && short.lines <= 1 ? short : row(texts('at'), BOLD_ROW, 44, 24, 2);
    const label = row(texts('label'), BOLD_ROW, Math.round(56 * share), 22, 3);
    const sub = row(texts('sub'), PLAIN_ROW, Math.round(36 * share), 18, 3);
    const above = Math.round(Math.max(1, date.lines) * date.size * 1.1) + 48;
    const below = 44 + Math.ceil(Math.max(1, label.lines) * label.size * 1.16) + (sub.lines ? 14 + Math.ceil(sub.lines * sub.size * 1.3) : 0);
    return { date, label, sub, above, below, fits: above + below <= hero.h };
  };
  let chosen = at(1);
  for (let step = 19; step >= 9 && !chosen.fits; step -= 1) chosen = at(step / 20);
  const { date, label, sub, above, below } = chosen;
  return {
    colW, inner,
    dateSize: date.size, labelSize: label.size, subSize: sub.size,
    railY: Math.round(Math.max(0, (hero.h - above - below) / 2) + above),
    centres: events.map((_, i) => Math.round((i + 0.5) * colW)),
    overflow: date.overflow || label.overflow || sub.overflow || !chosen.fits,
  };
};

/** An SVG scene is drawn to its viewBox; it takes whatever room it is left. */
export const svgLayout = (visual, box) => {
  const numbers = String(visual.viewBox ?? '0 0 1200 520').trim().split(/[\s,]+/).map(Number);
  const usable = numbers.length === 4 && numbers.every(Number.isFinite) && numbers[2] > 0 && numbers[3] > 0;
  const [, , vw, vh] = usable ? numbers : [0, 0, 1200, 520];
  const scale = Math.min(box.w / vw, (box.h - captionHeight(visual.caption, box.w)) / vh);
  const sizes = (visual.groups ?? []).flatMap((group) =>
    [...String(group.svg ?? '').matchAll(/font-size\s*[=:]\s*['"]?\s*(\d+(?:\.\d+)?)/g)].map((match) => Number(match[1])),
  );
  return { width: Math.round(vw * scale), height: Math.round(vh * scale), minType: sizes.length ? Math.min(...sizes) * scale : null };
};

/** The number shot's type size: fitted to the final string. */
export const numberSize = (value, maxWidth) => {
  for (let size = theme.type.number; size > 160; size -= 8) {
    if (textWidth(value, size, -0.03) <= maxWidth) return size;
  }
  return 160;
};

/** The words under a number: full size where there is room, smaller on a short frame. */
export const numberWords = (label, extra, region) => {
  const at = (scale) => {
    const labelSize = Math.round(theme.type.caption * scale);
    const extraSize = Math.round(28 * scale);
    const height =
      wrapBold(label, region.w, labelSize).length * labelSize * LINE +
      (extra ? 12 + wrapPlain(extra, region.w * 0.8, extraSize).length * extraSize * 1.3 : 0);
    return { labelSize, extraSize, height, overflow: height > region.h };
  };
  for (let step = 20; step >= 13; step -= 1) {
    const fitted = at(step / 20);
    if (!fitted.overflow) return fitted;
  }
  return at(13 / 20);
};

/** Both states of a contrast, from either visual that can carry one. */
export const contrastSides = (visual) => {
  if (visual?.kind === 'split') {
    return {
      left: { title: visual.left.title, items: visual.left.items ?? [] },
      right: { title: visual.right.title, items: visual.right.items ?? [] },
    };
  }
  if (visual?.kind === 'beforeafter') {
    const side = (stack) => ({ title: stack.title, items: (stack.items ?? []).map((text) => ({ text })) });
    return { left: side(visual.before), right: side(visual.after) };
  }
  return null;
};

const INSET = { mechanism: 28, evidence: 24 };

/** The box a family draws its picture in, inside the hero region's frame. */
export const pictureBox = (family, hero) => {
  const by = INSET[family] ?? 0;
  return { x: hero.x + by, y: hero.y + by, w: hero.w - 2 * by, h: hero.h - 2 * by };
};

/* -------------------------------------------------------------- the check -- */

/**
 * What a viewer would see go wrong in this shot, found before it is rendered.
 * `errors` are words cut or parts outside their region. `warnings` are type too
 * small to read comfortably.
 */
export const checkShotLayout = (shot, canvas = theme.canvas) => {
  const errors = [];
  const warnings = [];
  const r = layoutFor(shot.family, canvas);
  const visual = shot.visual;
  const floor = Math.round((MIN_READABLE * canvas.height) / 1000);
  const over = (message) => errors.push(`layout-overflow: ${message}`);
  const small = (size, what) => {
    if (size !== null && size < floor) warnings.push(`layout-small: ${what} is drawn at ${Math.round(size)} px; keep it at ${floor} px or more on this frame`);
  };
  const title = () => {
    if (r.title && shot.title && fitTitle(shot.title, r.title).overflow) over(`the title "${shot.title}" does not fit its row; shorten it`);
  };
  // The renderer wraps a headline at 88% of its row. A single word may use the rest.
  const headline = (text, options) => {
    const fitted = text && fitHeadline(text, { ...options, maxWidth: Math.floor(options.maxWidth * 0.88) });
    const { tracking = theme.type.tracking.display, maxLines, minSize } = options;
    if (!fitted || !fitted.overflow) return;
    const lines = wrapText(text, Math.floor(options.maxWidth * 0.88), minSize, tracking);
    if (lines.length > maxLines || lines.some((line) => textWidth(line, minSize, tracking) > options.maxWidth)) over(`"${text}" is cut at the smallest headline size; shorten it`);
  };

  switch (shot.family) {
    case 'statement':
      headline(visual?.kind === 'hero' ? visual.title : shot.title, { maxWidth: r.hero.w, maxLines: 3, minSize: 84 });
      break;
    case 'quote':
      headline(visual?.text ?? shot.title, { maxWidth: r.hero.w, maxLines: 4, maxSize: 88, minSize: 64 });
      break;
    case 'number': {
      const value = visual?.value ?? shot.title ?? '';
      if (textWidth(value, numberSize(value, r.hero.w), -0.03) > r.hero.w) over(`the number "${value}" is wider than the frame`);
      const words = numberWords(visual?.label ?? shot.sub ?? '', visual?.sub, r.sub);
      if (words.overflow) over(`the words under the number need ${Math.ceil(words.height)} px and have ${r.sub.h} px`);
      break;
    }
    case 'contrast': {
      title();
      const sides = contrastSides(visual);
      if (sides && contrastLayout(sides, r.hero).overflow) over('the two sides do not fit their panels at 24 px; use fewer or shorter lines');
      break;
    }
    case 'checklist':
      title();
      if (visual?.kind === 'checklist' && checklistLayout(visual.items, r.hero).overflow) over('a checklist line does not fit its row at 24 px; shorten it');
      break;
    case 'timeline':
      title();
      if (visual?.kind === 'timeline') {
        const fitted = timelineLayout(visual.events, r.hero);
        if (fitted.overflow) over('the timeline does not fit its rail; use fewer events or shorter words');
        else small(visual.events.some((event) => event.sub) ? Math.min(fitted.labelSize, fitted.subSize) : fitted.labelSize, 'the smallest text on the rail');
      }
      break;
    case 'mechanism':
    case 'layers':
    case 'evidence': {
      if (shot.family === 'evidence') {
        const claim = shot.title || visual?.claim;
        headline(claim, { maxWidth: r.title.w, maxLines: 2, maxSize: 64, minSize: 52 });
      } else title();
      const box = pictureBox(shot.family, r.hero);
      if (visual?.kind === 'diagram' || visual?.kind === 'flow') {
        const layout = visual.kind === 'flow' ? flowAsDiagram(visual, box).layout : diagramLayout(visual, box);
        for (const problem of layout.problems) errors.push(`${problem.code}: ${problem.message}`);
        if (!layout.problems.length) small(Math.min(layout.labelSize, ...layout.nodes.filter((node) => node.subLines.length).map((node) => node.subSize)), 'the smallest text in the boxes');
      } else if (visual?.kind === 'svg') {
        small(svgLayout(visual, box).minType, 'the smallest text in the drawing');
      } else if (canFit(visual)) {
        if (visual.kind === 'sequence') {
          const actors = visual.actors.length;
          visual.steps.forEach((step, i) => {
            for (const end of [step.frm, step.to]) {
              if (!Number.isInteger(end) || end < 0 || end >= actors) errors.push(`sequence-step: step ${i + 1} names actor ${end}; the sequence has actors 0 to ${actors - 1}`);
            }
          });
        }
        const fitted = fitVisual(visual, box, shot.visualScale);
        if (fitted.overflow) over(`the ${visual.kind} is larger than its ${box.w}x${box.h} region at its smallest size; split it or shorten it`);
        else small(fitted.minType, `the smallest text in the ${visual.kind}`);
      }
      break;
    }
    default:
      break;
  }
  return { errors, warnings };
};
