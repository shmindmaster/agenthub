#!/usr/bin/env node
// Draw single frames of an explainer film and one contact sheet, without
// rendering the film.
//
//   node still-explainer.mjs <jobRoot> [--props picture/explainer-props.json]
//        [--out picture/explainer-stills] [--shots S02,S03] [--at open,beats,hold]
//        [--public-dir public]
//
// Moments, per shot: `open` is one second in, or as soon as the opening line has
// landed; `beats` is each beat after its entrance; `hold` is the end of the
// shot. The default is open,hold.
//
// Writes one PNG per frame, sheet.png (one row per shot) and stills.json. A
// frame caught while something is still entering is named in stills.json and
// framed in red on the sheet, so a half-drawn word is not read as a defect.
//
// Needs the kit's own install (npm ci in the kit). No network, no spend.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { framesOf, staggerFrames } from './motion.mjs';
import { decodePng, encodePng } from './png.mjs';
import { revealParts } from './reveal.mjs';

export const MOMENTS = ['open', 'beats', 'hold'];
const OPENING_SECONDS = 0.1;

/** The longest entrance a beat starts; a frame inside it is mid-move. */
const entranceFrames = (fps) => framesOf('draw', fps);

/** Families whose opening line lands one word at a time. */
const WORD_BY_WORD = ['statement', 'quote', 'evidence'];

const openingFrames = (shot, fps) => {
  const line = shot.visual?.text ?? (shot.visual?.kind === 'hero' ? shot.visual.title : shot.title || shot.visual?.claim) ?? '';
  const words = WORD_BY_WORD.includes(shot.family) ? String(line).split(/\s+/).filter(Boolean).length : 1;
  // The second line of a words-only shot starts this many frames after the first.
  const { visual } = shot;
  const second = { statement: (shot.sub ?? visual?.sub) ? 14 : 0, quote: (visual?.attribution ?? shot.sub) ? 20 : 0, end: 10, media: 6 }[shot.family] ?? 0;
  return Math.round(OPENING_SECONDS * fps) + Math.max(second, staggerFrames(Math.max(0, words - 1))) + framesOf('rise', fps);
};

/** What is still entering at a shot-local frame. Empty means the frame is settled. */
export const movingAt = (shot, localFrame, fps) => {
  const span = entranceFrames(fps);
  const moving = [];
  if (localFrame < openingFrames(shot, fps)) moving.push('opening');
  for (const beat of shot.beats ?? []) {
    if (localFrame >= beat.frame && localFrame < beat.frame + span) moving.push(beat.target);
  }
  // A part the plan gave no time arrives on the kit's own curve and makes no
  // beat, and some parts move for longer than the beat they land on.
  const told = new Set((shot.beats ?? []).filter((beat) => localFrame < beat.frame + span).map((beat) => beat.frame));
  revealParts(shot.visual, shot.durationSeconds).forEach(({ at: start, seconds }, i) => {
    const at = Math.round(start * fps);
    const until = at + Math.max(span, Math.ceil(seconds * fps));
    if (!told.has(at) && localFrame >= at && localFrame < until) moving.push(`visual part ${i + 1}`);
  });
  return moving;
};

/** The frames to draw, in film order. Local frames are kept inside the shot. */
export const pickFrames = (props, { shots: only = null, moments = ['open', 'hold'] } = {}) => {
  const unknown = moments.filter((moment) => !MOMENTS.includes(moment));
  if (unknown.length) throw new Error(`unknown moment ${unknown.join(', ')}; use ${MOMENTS.join(', ')}`);
  const ids = props.shots.map((shot) => shot.id);
  const missing = (only ?? []).filter((id) => !ids.includes(id));
  if (missing.length) throw new Error(`no shot ${missing.join(', ')}; the film has ${ids.join(', ')}`);
  const fps = props.film.fps;
  const picked = [];
  for (const shot of props.shots) {
    if (only && !only.includes(shot.id)) continue;
    const last = shot.durationFrames - 1;
    const inside = (frame) => Math.min(last, Math.max(0, Math.round(frame)));
    const wanted = [];
    if (moments.includes('open')) wanted.push(['open', inside(Math.max(fps, openingFrames(shot, fps)))]);
    if (moments.includes('beats')) {
      (shot.beats ?? []).forEach((beat, i) => {
        // The beat's own last settled frame: after its entrance, before the next.
        const next = shot.beats[i + 1]?.frame ?? Infinity;
        wanted.push([`beat${i + 1}`, inside(Math.min(beat.frame + entranceFrames(fps), Math.max(beat.frame, next - 1)))]);
      });
    }
    if (moments.includes('hold')) wanted.push(['hold', inside(last - 1)]);
    const seen = new Set();
    for (const [moment, local] of wanted.sort((a, b) => a[1] - b[1])) {
      if (seen.has(local)) continue;
      seen.add(local);
      picked.push({
        shot: shot.id,
        family: shot.family,
        moment,
        frame: shot.startFrame + local,
        seconds: +((shot.startFrame + local) / fps).toFixed(3),
        moving: movingAt(shot, local, fps),
        file: `${shot.id}-${moment}.png`,
      });
    }
  }
  if (!picked.length) throw new Error(`nothing to draw: no chosen shot has a frame for ${moments.join(', ')}`);
  return picked;
};

export const TILE_WIDTH = 480;

/** Box-filter a decoded frame down to a tile width. */
export const shrink = (image, width) => {
  const height = Math.max(1, Math.round((image.height * width) / image.width));
  const rgba = Buffer.alloc(width * height * 4, 255);
  for (let y = 0; y < height; y += 1) {
    const y0 = Math.floor((y * image.height) / height);
    const y1 = Math.max(y0 + 1, Math.floor(((y + 1) * image.height) / height));
    for (let x = 0; x < width; x += 1) {
      const x0 = Math.floor((x * image.width) / width);
      const x1 = Math.max(x0 + 1, Math.floor(((x + 1) * image.width) / width));
      const total = [0, 0, 0];
      for (let sy = y0; sy < y1; sy += 1) {
        for (let sx = x0; sx < x1; sx += 1) {
          const at = (sy * image.width + sx) * 4;
          for (let c = 0; c < 3; c += 1) total[c] += image.rgba[at + c];
        }
      }
      const count = (y1 - y0) * (x1 - x0);
      const to = (y * width + x) * 4;
      for (let c = 0; c < 3; c += 1) rgba[to + c] = Math.round(total[c] / count);
    }
  }
  return { width, height, rgba };
};

const STEADY = [70, 70, 70];
const MOVING = [232, 93, 93];

/**
 * One sheet from rows of `{ image, moving }`. Every tile is framed: red when
 * something on it is still entering, grey when it is settled.
 */
export const contactSheet = (rows, { tileWidth = TILE_WIDTH, border = 4, gap = 8 } = {}) => {
  const tiles = rows.map((row) => row.map(({ image, moving }) => ({ tile: shrink(image, tileWidth), moving })));
  const tileHeight = Math.max(...tiles.flat().map(({ tile }) => tile.height));
  const cellW = tileWidth + 2 * border + gap;
  const cellH = tileHeight + 2 * border + gap;
  const width = Math.max(...tiles.map((row) => row.length)) * cellW + gap;
  const height = tiles.length * cellH + gap;
  const rgba = Buffer.alloc(width * height * 4);
  for (let i = 0; i < rgba.length; i += 4) rgba.set([24, 24, 24, 255], i);
  tiles.forEach((row, r) =>
    row.forEach(({ tile, moving }, c) => {
      const left = gap + c * cellW;
      const top = gap + r * cellH;
      const edge = moving ? MOVING : STEADY;
      for (let y = 0; y < tile.height + 2 * border; y += 1) {
        for (let x = 0; x < tileWidth + 2 * border; x += 1) {
          const to = ((top + y) * width + left + x) * 4;
          const sx = x - border;
          const sy = y - border;
          if (sx < 0 || sy < 0 || sx >= tileWidth || sy >= tile.height) rgba.set(edge, to);
          else tile.rgba.copy(rgba, to, (sy * tileWidth + sx) * 4, (sy * tileWidth + sx) * 4 + 4);
        }
      }
    }),
  );
  return { width, height, rgba };
};

const flag = (argv, name, fallback = null) => {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : fallback;
};

const list = (value) => (value ? value.split(',').map((part) => part.trim()).filter(Boolean) : null);

/** Bundle the kit once with its own config, then draw every frame in one browser. */
const drawFrames = async ({ kitRoot, props, frames, outDir, publicDir }) => {
  const require = createRequire(join(kitRoot, 'package.json'));
  let renderer;
  let cli;
  try {
    renderer = await import(pathToFileURL(require.resolve('@remotion/renderer')).href);
    cli = join(dirname(require.resolve('@remotion/cli/package.json')), 'remotion-cli.js');
  } catch {
    throw new Error(`Remotion is not installed in ${kitRoot}; run npm ci there first`);
  }
  const api = renderer.renderStill ? renderer : renderer.default;
  const serveUrl = mkdtempSync(join(tmpdir(), 'explainer-stills-'));
  let browser = null;
  try {
    const bundled = spawnSync(
      process.execPath,
      [cli, 'bundle', 'src/index.ts', `--out-dir=${serveUrl}`, ...(publicDir ? [`--public-dir=${publicDir}`] : [])],
      { cwd: kitRoot, encoding: 'utf8', windowsHide: true },
    );
    if (bundled.status !== 0) throw new Error(`remotion bundle failed:\n${bundled.stdout ?? ''}${bundled.stderr ?? ''}`);
    browser = await api.openBrowser('chrome');
    const composition = await api.selectComposition({ serveUrl, id: 'Explainer', inputProps: props, puppeteerInstance: browser });
    for (const still of frames) {
      await api.renderStill({
        serveUrl,
        composition,
        inputProps: props,
        frame: still.frame,
        output: join(outDir, still.file),
        imageFormat: 'png',
        overwrite: true,
        puppeteerInstance: browser,
      });
    }
  } finally {
    if (browser) await browser.close({ silent: true });
    rmSync(serveUrl, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
};

const main = async (argv) => {
  const jobRoot = argv[0] && !argv[0].startsWith('--') ? resolve(argv[0]) : null;
  if (!jobRoot) {
    console.error('Usage: node still-explainer.mjs <jobRoot> [--props P] [--out P] [--shots a,b] [--at open,beats,hold] [--public-dir P]');
    return 1;
  }
  const propsPath = resolve(jobRoot, flag(argv, '--props', 'picture/explainer-props.json'));
  if (!existsSync(propsPath)) throw new Error(`no props at ${propsPath}; run build-explainer.mjs first`);
  const props = JSON.parse(readFileSync(propsPath, 'utf8').replace(/^﻿/, ''));
  const frames = pickFrames(props, { shots: list(flag(argv, '--shots')), moments: list(flag(argv, '--at')) ?? ['open', 'hold'] });
  const outDir = resolve(jobRoot, flag(argv, '--out', 'picture/explainer-stills'));
  const publicDir = flag(argv, '--public-dir');
  mkdirSync(outDir, { recursive: true });
  await drawFrames({
    kitRoot: resolve(dirname(fileURLToPath(import.meta.url)), '..'),
    props,
    frames,
    outDir,
    publicDir: publicDir ? resolve(jobRoot, publicDir) : null,
  });

  const rows = [];
  for (const still of frames) {
    // Shrunk as it is read: a full frame is six megabytes and a film has hundreds.
    const tile = { image: shrink(decodePng(readFileSync(join(outDir, still.file))), TILE_WIDTH), moving: still.moving.length > 0 };
    const last = rows[rows.length - 1];
    if (last && last.shot === still.shot) last.tiles.push(tile);
    else rows.push({ shot: still.shot, tiles: [tile] });
  }
  writeFileSync(join(outDir, 'sheet.png'), encodePng(contactSheet(rows.map((row) => row.tiles))));
  const report = {
    schema: 'media-studio/explainer-stills/1',
    props: propsPath,
    sheet: 'sheet.png',
    stills: frames,
    moving: frames.filter((still) => still.moving.length).map((still) => still.file),
  };
  writeFileSync(join(outDir, 'stills.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ ok: true, out: outDir, stills: frames.length, moving: report.moving.length }));
  return 0;
};

const isMain = Boolean(process.argv[1]) && resolve(process.argv[1]).replace(/\\/g, '/').endsWith('still-explainer.mjs');
if (isMain) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error) => {
      console.error(`[explainer-stills] ${error.message}`);
      process.exit(1);
    },
  );
}
