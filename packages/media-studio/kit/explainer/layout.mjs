/**
 * Layout for the explainer composition: where each family puts its parts on
 * the canvas, and how a headline is fitted without measuring the DOM.
 *
 * Everything is a fraction of the canvas, so the same grammar renders at
 * 1600x1000, 1920x1080 or 1280x720. The composition is landscape-only on
 * purpose: the wide families do not degrade to 9:16, and pretending they do
 * is how a vertical cut ends up as a letterboxed slideshow.
 */
import { theme } from './theme.mjs';

const WIDE_MIN_ASPECT = 1.2;

/** Regions as fractions of the canvas. `hero` is the picture the line is about. */
const WIDE = {
  statement: {
    hero: { x: 0.075, y: 0.2, w: 0.85, h: 0.56, align: 'left', valign: 'center' },
    kicker: null,
    title: null,
    sub: null,
  },
  number: {
    hero: { x: 0.075, y: 0.17, w: 0.85, h: 0.6, align: 'center', valign: 'center' },
    kicker: { x: 0.075, y: 0.09, w: 0.85, h: 0.07, align: 'center' },
    title: null,
    sub: { x: 0.15, y: 0.765, w: 0.7, h: 0.13, align: 'center' },
  },
  contrast: {
    hero: { x: 0.06, y: 0.255, w: 0.88, h: 0.6, align: 'left', valign: 'top' },
    kicker: { x: 0.075, y: 0.085, w: 0.85, h: 0.06, align: 'left' },
    title: { x: 0.075, y: 0.14, w: 0.85, h: 0.1, align: 'left' },
    sub: null,
  },
  mechanism: {
    hero: { x: 0.045, y: 0.24, w: 0.91, h: 0.62, align: 'left', valign: 'top' },
    kicker: { x: 0.075, y: 0.075, w: 0.85, h: 0.055, align: 'left' },
    title: { x: 0.075, y: 0.13, w: 0.85, h: 0.095, align: 'left' },
    sub: null,
  },
  layers: {
    hero: { x: 0.15, y: 0.25, w: 0.7, h: 0.6, align: 'left', valign: 'center' },
    kicker: { x: 0.075, y: 0.085, w: 0.85, h: 0.06, align: 'left' },
    title: { x: 0.075, y: 0.135, w: 0.85, h: 0.09, align: 'left' },
    sub: null,
  },
  timeline: {
    hero: { x: 0.06, y: 0.28, w: 0.88, h: 0.56, align: 'left', valign: 'center' },
    kicker: { x: 0.075, y: 0.1, w: 0.85, h: 0.06, align: 'left' },
    title: { x: 0.075, y: 0.155, w: 0.85, h: 0.1, align: 'left' },
    sub: null,
  },
  evidence: {
    hero: { x: 0.075, y: 0.34, w: 0.85, h: 0.51, align: 'left', valign: 'top' },
    kicker: { x: 0.075, y: 0.075, w: 0.6, h: 0.05, align: 'left' },
    title: { x: 0.075, y: 0.13, w: 0.85, h: 0.19, align: 'left' },
    sub: null,
  },
  quote: {
    hero: { x: 0.125, y: 0.22, w: 0.75, h: 0.48, align: 'left', valign: 'center' },
    kicker: null,
    title: null,
    sub: { x: 0.125, y: 0.73, w: 0.6, h: 0.08, align: 'left' },
  },
  checklist: {
    hero: { x: 0.12, y: 0.25, w: 0.78, h: 0.58, align: 'left', valign: 'top' },
    kicker: { x: 0.12, y: 0.08, w: 0.78, h: 0.06, align: 'left' },
    title: { x: 0.12, y: 0.135, w: 0.78, h: 0.095, align: 'left' },
    sub: null,
  },
  media: {
    hero: { x: 0, y: 0, w: 1, h: 1, align: 'left', valign: 'bottom' },
    kicker: null,
    title: { x: 0.075, y: 0.64, w: 0.72, h: 0.14, align: 'left' },
    sub: { x: 0.075, y: 0.79, w: 0.62, h: 0.07, align: 'left' },
  },
  sting: {
    hero: { x: 0.1, y: 0.1, w: 0.8, h: 0.74, align: 'center', valign: 'center' },
    kicker: null,
    title: null,
    sub: null,
  },
  chapter: {
    hero: { x: 0.1, y: 0.26, w: 0.8, h: 0.44, align: 'left', valign: 'center' },
    kicker: null,
    title: null,
    sub: null,
  },
  end: {
    hero: { x: 0.1, y: 0.26, w: 0.8, h: 0.42, align: 'center', valign: 'center' },
    kicker: { x: 0.1, y: 0.16, w: 0.8, h: 0.06, align: 'center' },
    title: null,
    sub: { x: 0.15, y: 0.7, w: 0.7, h: 0.1, align: 'center' },
  },
};

const BOX_KEYS = ['hero', 'kicker', 'title', 'sub'];

const resolveBox = (box, canvas) => {
  if (!box) return null;
  return {
    x: Math.round(box.x * canvas.width),
    y: Math.round(box.y * canvas.height),
    w: Math.round(box.w * canvas.width),
    h: Math.round(box.h * canvas.height),
    align: box.align,
    valign: box.valign,
  };
};

export const aspectOf = (canvas) => canvas.width / canvas.height;

export const isWide = (canvas) => aspectOf(canvas) >= WIDE_MIN_ASPECT;

/** Pixel regions for a family on a canvas. Throws on a ratio it cannot compose. */
export const layoutFor = (family, canvas = theme.canvas) => {
  if (!isWide(canvas)) {
    throw new Error(
      `explainer layout is landscape-only; ${canvas.width}x${canvas.height} is ${aspectOf(canvas).toFixed(2)}:1`,
    );
  }
  const source = WIDE[family];
  if (!source) throw new Error(`unknown family "${family}"`);
  const out = {};
  for (const key of BOX_KEYS) out[key] = resolveBox(source[key], canvas);
  out.safe = {
    x: Math.round(theme.space.safeX * (canvas.width / theme.canvas.width)),
    y: Math.round(theme.space.safeTop * (canvas.height / theme.canvas.height)),
    w: canvas.width - 2 * Math.round(theme.space.safeX * (canvas.width / theme.canvas.width)),
    h:
      canvas.height -
      Math.round(theme.space.safeTop * (canvas.height / theme.canvas.height)) -
      Math.round(theme.space.safeBottom * (canvas.height / theme.canvas.height)),
  };
  return out;
};

/* ------------------------------------------------------------- headline fit -- */

/** Per-character width as a fraction of the font size, Inter-ish. */
const charWidth = (ch) => {
  if ('iljI.,:;!|\'`'.includes(ch)) return 0.28;
  if ('MWmw@%'.includes(ch)) return 0.86;
  if ('ftr'.includes(ch)) return 0.38;
  if (ch >= 'A' && ch <= 'Z') return 0.64;
  if (ch >= '0' && ch <= '9') return 0.58;
  if (ch === ' ') return 0.26;
  return 0.52;
};

/** Deterministic text width: a2e fits type by computing it, never by measuring. */
export const textWidth = (text, size, tracking = 0) =>
  Math.round(
    String(text)
      .split('')
      .reduce((sum, ch) => sum + charWidth(ch) * size, 0) +
      Math.max(0, String(text).length - 1) * tracking * size,
  );

/** Greedy wrap at a pixel width. */
export const wrapText = (text, maxWidth, size, tracking = 0) => {
  const words = String(text).trim().split(/\s+/).filter(Boolean);
  const lines = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (textWidth(candidate, size, tracking) <= maxWidth || !line) line = candidate;
    else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
};

/**
 * Largest size (between `min` and `max`) whose wrap fits `maxLines` and the width.
 * Returns the size and the wrapped lines; the renderer never re-measures.
 */
export const fitHeadline = (text, options) => {
  const {
    maxWidth,
    maxLines = 3,
    maxSize = theme.type.xl,
    minSize = theme.type.s,
    tracking = theme.type.tracking.display,
  } = options;
  // A single word cannot wrap, so a line can still be wider than its row.
  const inRow = (lines, size) => lines.every((line) => textWidth(line, size, tracking) <= maxWidth);
  for (let size = maxSize; size >= minSize; size -= 2) {
    const lines = wrapText(text, maxWidth, size, tracking);
    if (lines.length <= maxLines && inRow(lines, size)) return { size, lines, overflow: false };
  }
  const lines = wrapText(text, maxWidth, minSize, tracking);
  return { size: minSize, lines: lines.slice(0, maxLines), overflow: lines.length > maxLines || !inRow(lines, minSize) };
};
