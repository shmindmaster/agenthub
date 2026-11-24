// The explainer picture gate's own evidence: every number it fails a film on is
// measured here on synthetic frames whose answer is known by construction. A
// metric that cannot separate a still frame from a moving one, or light type
// from a dark field, is worse than no gate at all.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import {
  RULES,
  analyzeSequence,
  backgroundLuma,
  components,
  debrisCount,
  frameMetrics,
  glowArea,
  heroOf,
  heroScore,
  inkMask,
  landingHold,
  scoreFilm,
  scoreFrame,
  toGrey,
} from '../kit/explainer/frame-metrics.mjs';
import { PngError, crc32, decodePng, encodePng } from '../kit/explainer/png.mjs';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/* ------------------------------------------------------------- synthetic -- */

const solid = (width, height, [r, g, b, a = 255]) => {
  const rgba = new Uint8Array(width * height * 4);
  for (let i = 0; i < rgba.length; i += 4) {
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }
  return rgba;
};

const paint = (rgba, width, x0, y0, w, h, [r, g, b, a = 255]) => {
  for (let y = y0; y < y0 + h; y += 1) {
    for (let x = x0; x < x0 + w; x += 1) {
      const i = (y * width + x) * 4;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = a;
    }
  }
  return rgba;
};

/* -------------------------------------------------------------- png build -- */

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const chunk = (type, data) => {
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([head, body, crc]);
};

const pngFrom = ({ width, height, bitDepth = 8, colourType = 6, interlace = 0, data }) => {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = bitDepth;
  ihdr[9] = colourType;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = interlace;
  return Buffer.concat([SIGNATURE, chunk('IHDR', ihdr), chunk('IDAT', deflateSync(data)), chunk('IEND', Buffer.alloc(0))]);
};

const paeth = (a, b, c) => {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
};

/** The encoder side of one PNG filter, so a filtered file can be built by hand. */
const filterRow = (type, row, prior, bpp) => {
  const out = Buffer.alloc(row.length);
  for (let i = 0; i < row.length; i += 1) {
    const a = i >= bpp ? row[i - bpp] : 0;
    const b = prior ? prior[i] : 0;
    const c = prior && i >= bpp ? prior[i - bpp] : 0;
    let predicted = 0;
    if (type === 1) predicted = a;
    else if (type === 2) predicted = b;
    else if (type === 3) predicted = (a + b) >> 1;
    else if (type === 4) predicted = paeth(a, b, c);
    out[i] = (row[i] - predicted) & 0xff;
  }
  return out;
};

/* ------------------------------------------------------------------- png -- */

test('PNG round-trips RGBA through encode and decode', () => {
  const width = 7;
  const height = 5;
  const rgba = new Uint8Array(width * height * 4);
  for (let i = 0; i < rgba.length; i += 1) rgba[i] = (i * 37 + 11) & 0xff;
  const back = decodePng(encodePng({ width, height, rgba }));
  assert.equal(back.width, width);
  assert.equal(back.height, height);
  assert.deepEqual([...back.rgba], [...rgba]);
});

test('all five scanline filters decode to the pixels that were filtered', () => {
  const width = 4;
  const height = 5;
  const bpp = 4;
  const stride = width * bpp;
  const rgba = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      rgba[i] = (x * 40 + y * 7) & 0xff;
      rgba[i + 1] = (y * 29 + x * 13 + 60) & 0xff;
      rgba[i + 2] = (x * y * 31 + 90) & 0xff;
      rgba[i + 3] = 255 - y * 9;
    }
  }
  const parts = [];
  let prior = null;
  const filters = [];
  for (let y = 0; y < height; y += 1) {
    const row = Buffer.from(rgba.buffer, rgba.byteOffset + y * stride, stride);
    const type = y % 5;
    filters.push(type);
    parts.push(Buffer.from([type]), filterRow(type, row, prior, bpp));
    prior = row;
  }
  assert.deepEqual(filters, [0, 1, 2, 3, 4], 'the fixture must exercise every filter path');
  const back = decodePng(pngFrom({ width, height, data: Buffer.concat(parts) }));
  assert.deepEqual([...back.rgba], [...rgba]);
});

test('an RGB PNG decodes with an opaque alpha channel', () => {
  const width = 3;
  const height = 2;
  const rgb = Buffer.from([
    10, 20, 30, 40, 50, 60, 70, 80, 90,
    1, 2, 3, 4, 5, 6, 7, 8, 9,
  ]);
  const raw = Buffer.concat([Buffer.from([0]), rgb.subarray(0, 9), Buffer.from([0]), rgb.subarray(9)]);
  const back = decodePng(pngFrom({ width, height, colourType: 2, data: raw }));
  assert.equal(back.rgba[0], 10);
  assert.equal(back.rgba[3], 255);
  assert.equal(back.rgba[4], 40);
  assert.equal(back.rgba[19], 255);
});

test('the reader refuses 16-bit, palette and interlaced PNGs by name instead of guessing', () => {
  const data = Buffer.alloc(8);
  assert.throws(
    () => decodePng(pngFrom({ width: 2, height: 2, bitDepth: 16, data })),
    (error) => error instanceof PngError && error.name === 'PngError' && error.code === 'unsupported-bit-depth',
  );
  assert.throws(
    () => decodePng(pngFrom({ width: 2, height: 2, colourType: 3, data })),
    (error) => error.code === 'unsupported-colour-type',
  );
  assert.throws(
    () => decodePng(pngFrom({ width: 2, height: 2, interlace: 1, data })),
    (error) => error.code === 'unsupported-interlace',
  );
  assert.throws(() => decodePng(Buffer.from('not a png at all')), (error) => error.code === 'not-png');
});

/* --------------------------------------------------------------- luma/ink -- */

test('light type on a dark field is ink, and so is dark type on a light field', () => {
  const width = 120;
  const height = 80;
  const dark = solid(width, height, [11, 11, 11]);
  paint(dark, width, 20, 30, 40, 14, [232, 228, 217]);
  const grid = toGrey(dark, width, height);
  assert.ok(Math.abs(backgroundLuma(grid) - 11) < 0.6);
  const mask = inkMask(grid);
  assert.equal(mask[30 * width + 20], 1);
  assert.equal(mask[5 * width + 5], 0);
  assert.equal(mask.reduce((sum, v) => sum + v, 0), 40 * 14);

  const light = solid(width, height, [235, 235, 235]);
  paint(light, width, 20, 30, 40, 14, [10, 10, 10]);
  const inverted = inkMask(toGrey(light, width, height));
  assert.equal(inverted[30 * width + 20], 1);
  assert.equal(inverted[5 * width + 5], 0);
  assert.equal(inverted.reduce((sum, v) => sum + v, 0), 40 * 14);
});

/* ------------------------------------------------------------- components -- */

test('dilation joins the characters of one line and leaves the next line alone', () => {
  const width = 40;
  const height = 30;
  const mask = new Uint8Array(width * height);
  const fill = (x0, y0, w, h) => {
    for (let y = y0; y < y0 + h; y += 1) for (let x = x0; x < x0 + w; x += 1) mask[y * width + x] = 1;
  };
  fill(4, 4, 3, 6);
  fill(10, 4, 3, 6);
  fill(4, 16, 3, 6);

  const found = components(mask, width, height, { dilateX: 2, dilateY: 0, minPixels: 1 });
  assert.equal(found.length, 2);
  assert.deepEqual(found[0], { x: 4, y: 4, w: 9, h: 6, area: 36 });
  assert.deepEqual(found[1], { x: 4, y: 16, w: 3, h: 6, area: 18 });

  const all = components(mask, width, height, { dilateX: 2, dilateY: 2, minPixels: 1 });
  assert.equal(all.length, 2, 'a vertically mean dilation cannot jump the 6-cell gap between the lines');
  const merged = components(mask, width, height, { dilateX: 2, dilateY: 10, minPixels: 1 });
  assert.equal(merged.length, 1, 'which is exactly the mistake a reach over the line gap would make');
  const wide = components(mask, width, height, { dilateX: 2, dilateY: 0, minPixels: 19 });
  assert.deepEqual(wide.map((c) => c.area), [36], 'minPixels counts ink, not box area');
});

/* ------------------------------------------------------------------- hero -- */

test('a wide flat object does not outscore a picture by width alone', () => {
  const rule = { x: 0, y: 0, w: 300, h: 4, area: 1200 };
  const picture = { x: 10, y: 10, w: 100, h: 40, area: 4000 };
  const square = { x: 50, y: 50, w: 30, h: 20, area: 600 };
  assert.ok(Math.abs(heroScore(rule) - 6.4) < 1e-9, 'a 300x4 rule scores 6.4, not 300');
  assert.equal(heroScore(picture), 40);
  assert.equal(heroScore(square), 20);

  const hero = heroOf([rule, picture, square]);
  assert.equal(hero.w, 100);
  assert.equal(hero.height, 40);
  assert.equal(heroOf([]), null);
  assert.equal(heroOf([rule]).height, heroScore(rule), 'the only component is still the hero, however flat');
  assert.throws(() => heroOf([{ w: Number.NaN, h: 4 }]), /finite/);
});

test('debris counts small fragments and never the hero', () => {
  const hero = { x: 0, y: 0, w: 120, h: 80, area: 9600 };
  const specks = Array.from({ length: 12 }, (_, i) => ({ x: i * 10, y: 200, w: 6, h: 6, area: 36 }));
  assert.equal(debrisCount([hero, ...specks], { maxW: 40, maxH: 40, minPixels: 20 }), 12);
  assert.equal(debrisCount([hero, ...specks], { maxW: 40, maxH: 40, minPixels: 40 }), 0);
  const secondPicture = { x: 0, y: 0, w: 200, h: 150, area: 30000 };
  assert.equal(debrisCount([hero, secondPicture], { maxW: 40, maxH: 40, minPixels: 20 }), 0);
});

/* ------------------------------------------------------------------- glow -- */

test('glow counts a saturated dim patch and ignores bright or grey ones', () => {
  const width = 400;
  const height = 300;
  const rgba = solid(width, height, [8, 8, 8]);
  paint(rgba, width, 20, 20, 40, 40, [46, 91, 255]); // saturated, luma 96
  paint(rgba, width, 150, 20, 40, 40, [255, 220, 40]); // saturated, luma 209
  paint(rgba, width, 280, 20, 40, 40, [90, 90, 90]); // mid luma, no saturation

  assert.equal(glowArea(rgba, width, height, { x: 20, y: 20, w: 40, h: 40 }), 1600);
  assert.equal(glowArea(rgba, width, height, { x: 150, y: 20, w: 40, h: 40 }), 0);
  assert.equal(glowArea(rgba, width, height, { x: 280, y: 20, w: 40, h: 40 }), 0);
  assert.equal(glowArea(rgba, width, height, null), 1600, 'no box measures the whole frame');
  assert.equal(glowArea(rgba, width, height, { x: 20, y: 20, w: 40, h: 40 }, { satMin: 0.95 }), 0);
});

/* ------------------------------------------------------------ frame score -- */

const CANVAS = { width: 200, height: 120 };

const emptyFrame = () => solid(CANVAS.width, CANVAS.height, [8, 8, 8]);

const pictureFrame = () => {
  const rgba = emptyFrame();
  paint(rgba, CANVAS.width, 70, 40, 60, 40, [250, 250, 250]);
  return rgba;
};

const litFrame = () => {
  const rgba = pictureFrame();
  paint(rgba, CANVAS.width, 94, 54, 12, 12, [46, 91, 255]);
  return rgba;
};

const smallHeroFrame = () => {
  const rgba = emptyFrame();
  paint(rgba, CANVAS.width, 20, 40, 40, 15, [220, 220, 220]);
  return rgba;
};

test('an empty frame is high on all three emptiness rules', () => {
  const verdict = scoreFrame(frameMetrics(emptyFrame(), CANVAS.width, CANVAS.height), CANVAS);
  assert.equal(verdict.level, 'high');
  assert.deepEqual(verdict.flags.map((f) => f.rule).sort(), ['empty-frame', 'flat-frame', 'hero-empty', 'hero-unlit']);
  assert.equal(verdict.flags.find((f) => f.rule === 'hero-empty').level, 'high');
});

test('a low-contrast frame is flat even with ink on it', () => {
  const rgba = solid(CANVAS.width, CANVAS.height, [100, 100, 100]);
  paint(rgba, CANVAS.width, 70, 40, 60, 40, [130, 130, 130]);
  const metrics = frameMetrics(rgba, CANVAS.width, CANVAS.height);
  assert.ok(metrics.lumaStd < RULES.minLumaStd);
  const verdict = scoreFrame(metrics, CANVAS);
  const flat = verdict.flags.find((f) => f.rule === 'flat-frame');
  assert.ok(flat, JSON.stringify(verdict.flags));
  assert.equal(flat.level, 'high');
  assert.equal(verdict.level, 'high');
});

test('a small hero is medium, and a chapter card is exempt from that flag only', () => {
  const metrics = frameMetrics(smallHeroFrame(), CANVAS.width, CANVAS.height);
  const plain = scoreFrame(metrics, CANVAS, { family: 'statement' });
  const small = plain.flags.find((f) => f.rule === 'hero-small');
  assert.ok(small, JSON.stringify(plain.flags));
  assert.equal(small.level, 'medium');
  assert.equal(plain.level, 'medium');

  for (const rules of [{ family: 'chapter' }, { family: 'end' }, { archetype: 'chapter-card' }, { exemptFamilies: ['statement'], family: 'statement' }]) {
    const verdict = scoreFrame(metrics, CANVAS, rules);
    assert.equal(verdict.flags.some((f) => f.rule === 'hero-small'), false, JSON.stringify(rules));
    assert.equal(verdict.flags.some((f) => f.rule === 'hero-unlit'), true, 'only hero-small is exempt');
  }
});

test('a hero without a glow is medium; a lit hero and a clean frame pass', () => {
  const unlit = scoreFrame(frameMetrics(pictureFrame(), CANVAS.width, CANVAS.height), CANVAS);
  const flag = unlit.flags.find((f) => f.rule === 'hero-unlit');
  assert.ok(flag, JSON.stringify(unlit.flags));
  assert.equal(flag.level, 'medium');

  const litMetrics = frameMetrics(litFrame(), CANVAS.width, CANVAS.height);
  assert.ok(litMetrics.glow > RULES.minGlowFraction);
  const clean = scoreFrame(litMetrics, CANVAS);
  assert.deepEqual(clean, { level: 'ok', flags: [] });
  assert.ok(litMetrics.hero.height >= RULES.heroSmall * CANVAS.height);
});

test('a sampled grid reports the hero back in source pixels', () => {
  const metrics = frameMetrics(litFrame(), CANVAS.width, CANVAS.height, { step: 2 });
  assert.equal(metrics.step, 2);
  assert.deepEqual(metrics.hero, { x: 70, y: 40, w: 60, h: 40, height: 40 });
  assert.equal(scoreFrame(metrics, CANVAS).level, 'ok');
});

test('thresholds are fractions of canvas height, so a 720p and a 1000p frame agree', () => {
  assert.ok(Math.abs(RULES.heroStrong - 170 / 720) < 1e-12);
  assert.ok(Math.abs(RULES.heroSmall - 110 / 720) < 1e-12);
  assert.ok(Math.abs(RULES.heroEmpty - 80 / 720) < 1e-12);
  const metrics = frameMetrics(litFrame(), CANVAS.width, CANVAS.height);
  assert.equal(scoreFrame(metrics, { width: 200, height: 120 }).level, 'ok');
  assert.equal(scoreFrame(metrics, { width: 450, height: 270 }).level, 'medium', 'the same hero is small on a bigger canvas');
  assert.throws(() => scoreFrame(metrics, { width: 200, height: 0 }), /canvas.height/);
});

/* --------------------------------------------------------------- sequence -- */

const barFrame = (width, height, x) => {
  const rgba = solid(width, height, [128, 128, 128]);
  paint(rgba, width, x, 8, 8, 24, [30, 30, 30]);
  return rgba;
};

test('identical frames are one still run; a moving bar is not; a flash is a cut', () => {
  const width = 64;
  const height = 40;
  const still = solid(width, height, [128, 128, 128]);
  const frames = Array.from({ length: 12 }, (_, i) => ({ index: i + 1, width, height, rgba: still }));
  const sequence = analyzeSequence(frames, { width, height }, { fps: 30, step: 1 });
  assert.equal(sequence.staticRuns.length, 1);
  assert.equal(sequence.staticRuns[0].startFrame, 1);
  assert.equal(sequence.staticRuns[0].endFrame, 12);
  assert.ok(Math.abs(sequence.longestStaticSeconds - 11 / 30) < 1e-9);
  assert.equal(sequence.cuts.length, 0);

  const moving = Array.from({ length: 12 }, (_, i) => ({ index: i + 1, width, height, rgba: barFrame(width, height, 4 + i * 4) }));
  const movingSequence = analyzeSequence(moving, { width, height }, { fps: 30, step: 1 });
  assert.equal(movingSequence.staticRuns.length, 0);
  assert.equal(movingSequence.cuts.length, 0, 'a 4 px step is motion, not a cut');

  const flash = frames.map((frame, i) => ({ ...frame, rgba: i === 6 ? solid(width, height, [250, 250, 250]) : still }));
  const flashed = analyzeSequence(flash, { width, height }, { fps: 30, step: 1 });
  assert.deepEqual(flashed.cuts.map((cut) => cut.frame), [7, 8]);
});

test('an empty run needs 45 frames at 30 fps, and a set-piece opening is exempt', () => {
  const width = 64;
  const height = 40;
  const blank = solid(width, height, [128, 128, 128]);
  const frames = Array.from({ length: 60 }, (_, i) => ({ index: i + 1, width, height, rgba: blank }));
  const shots = [{ id: 'S1', family: 'mechanism', startFrame: 0, durationFrames: 60 }];

  const bare = analyzeSequence(frames, { width, height }, { fps: 30, step: 1, shots });
  assert.equal(bare.emptyRuns.length, 1);
  assert.equal(bare.emptyRuns[0].frames, 60);

  const graced = analyzeSequence(frames, { width, height }, { fps: 30, step: 1, shots, setPieceShots: ['S1'] });
  assert.equal(graced.emptyRuns.length, 0, 'the first 40 frames of a set piece are the build, not an empty stretch');
  assert.equal(graced.perFrame[39].setPieceGrace, true);
  assert.equal(graced.perFrame[40].setPieceGrace, false);
});

test('landing hold measures the tail the picture actually rests on', () => {
  const width = 64;
  const height = 40;
  const frames = [];
  for (let i = 0; i < 30; i += 1) frames.push({ index: i + 1, width, height, rgba: barFrame(width, height, 4 + i * 2) });
  for (let i = 0; i < 14; i += 1) frames.push({ index: 31 + i, width, height, rgba: barFrame(width, height, 40) });

  const hold = landingHold(frames, { fps: 30, step: 1 });
  assert.equal(hold.heldFrames, 13);
  assert.equal(hold.frames, 7);
  assert.ok(Math.abs(hold.seconds - 7 / 30) < 1e-9);
  assert.equal(landingHold(frames.slice(0, 1), { fps: 30 }).frames, 0);
});

test('the film aggregate fails on a high flag and only warns on a drift', () => {
  const report = {
    perFrame: [{ index: 5, flags: [{ rule: 'empty-frame', level: 'high', message: 'nothing on screen' }] }],
    staticRuns: [{ startFrame: 1, endFrame: 100, frames: 100, seconds: 4 }],
    emptyRuns: [{ startFrame: 1, endFrame: 60, frames: 60, seconds: 2 }],
    landingHold: { frames: 10, seconds: 0.33 },
  };
  const verdict = scoreFilm(report);
  assert.equal(verdict.ok, false);
  assert.equal(verdict.high, 2);
  assert.ok(verdict.flags.some((f) => f.rule === 'static-run' && f.level === 'medium'));
  assert.ok(verdict.flags.some((f) => f.rule === 'landing-hold' && f.level === 'medium'));

  const driftOnly = scoreFilm({
    perFrame: [],
    staticRuns: [{ startFrame: 1, endFrame: 90, frames: 90, seconds: 3.5 }],
    emptyRuns: [],
    landingHold: { frames: 45, seconds: 1.5 },
  });
  assert.equal(driftOnly.ok, true);
  assert.equal(driftOnly.medium, 1);
});

test('metrics refuse a buffer that does not match its dimensions', () => {
  assert.throws(() => toGrey(new Uint8Array(10), 4, 4), /does not match/);
  assert.throws(() => toGrey(new Uint8Array(64), 0, 4), /width/);
  assert.throws(() => toGrey(new Uint8Array(64), 4, 4, { step: 0 }), /step/);
  assert.throws(() => components(new Uint8Array(8), 3, 3), /does not match/);
  assert.throws(() => analyzeSequence([], { width: 4, height: 4 }), /non-empty/);
  assert.throws(() => analyzeSequence([{ index: 0, width: 4, height: 4, rgba: new Uint8Array(64) }], { width: 4, height: 4 }), /1-based/);
  assert.throws(() => frameMetrics(new Uint8Array(3), 4, 4), /rgba length/);
});

/* -------------------------------------------------------------------- cli -- */

const ppm = (width, height, rgba) => {
  const header = Buffer.from(`P6\n${width} ${height}\n255\n`, 'latin1');
  const body = Buffer.alloc(width * height * 3);
  for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    body[j] = rgba[i];
    body[j + 1] = rgba[i + 1];
    body[j + 2] = rgba[i + 2];
  }
  return Buffer.concat([header, body]);
};

const frameName = (index) => {
  if (index % 3 === 0) return `f_${String(index).padStart(4, '0')}.png`;
  if (index % 3 === 1) return `frame-${String(index).padStart(6, '0')}.png`;
  return `frame-${String(index).padStart(6, '0')}.ppm`;
};

const runCli = (args) => {
  const result = spawnSync(process.execPath, [join(pkg, 'kit', 'explainer', 'measure-explainer-frames.mjs'), ...args], {
    encoding: 'utf8',
    windowsHide: true,
  });
  return { code: result.status, out: `${result.stdout}${result.stderr}`, stdout: result.stdout };
};

test('the CLI writes a report bound to the props, keeps a mixed frame set, and exits 2 when it has no frames', () => {
  const root = mkdtempSync(join(tmpdir(), 'explainer-metrics-'));
  try {
    const job = join(root, 'job');
    const frames = join(job, 'frames');
    mkdirSync(join(job, 'story'), { recursive: true });
    mkdirSync(frames, { recursive: true });

    const width = 200;
    const height = 120;
    const props = {
      film: {
        id: 'synthetic',
        title: 'Synthetic',
        backdrop: 'none',
        width,
        height,
        fps: 30,
        chapters: [{ id: 'c1', label: 'One', startSeconds: 0, endSeconds: 0.5, startFrame: 0, endFrame: 15 }],
      },
      shots: [
        { id: 'S1', archetype: 'kinetic-statement', family: 'statement', chapterId: 'c1', startSeconds: 0, durationSeconds: 0.33, startFrame: 0, durationFrames: 10, beats: [], holdSeconds: 0 },
        { id: 'S2', archetype: 'chapter-card', family: 'chapter', chapterId: 'c1', startSeconds: 0.33, durationSeconds: 0.17, startFrame: 10, durationFrames: 5, beats: [], holdSeconds: 0 },
      ],
      totalSeconds: 0.5,
    };
    const propsPath = join(job, 'story', 'explainer-props.json');
    writeFileSync(propsPath, `${JSON.stringify(props, null, 2)}\n`);

    for (let index = 1; index <= 15; index += 1) {
      const shotTwo = index > 10;
      const rgba = solid(width, height, [8, 8, 8]);
      if (index === 8) {
        // A blank frame mid-film: the gate must see it.
        paint(rgba, width, 0, 0, width, height, [250, 250, 250]);
      } else if (shotTwo) {
        paint(rgba, width, 80, 45, 20, 15, [250, 250, 250]);
      } else {
        paint(rgba, width, 40 + index, 40, 60, 40, [250, 250, 250]);
      }
      const body = frameName(index).endsWith('.ppm') ? ppm(width, height, rgba) : encodePng({ width, height, rgba });
      writeFileSync(join(frames, frameName(index)), body);
    }

    const empty = join(root, 'empty');
    mkdirSync(empty);
    const none = runCli(['--props', propsPath, '--frames', empty]);
    assert.equal(none.code, 2, none.out);
    assert.match(none.out, /no frame files/);

    const args = ['--props', propsPath, '--frames', frames, '--step', '1'];
    const strict = runCli([...args, '--strict']);
    assert.equal(strict.code, 0, strict.out);
    const summary = JSON.parse(strict.stdout.trim());
    assert.equal(summary.frames, 15);
    assert.equal(summary.sampled, 15);
    assert.ok(summary.high >= 1);

    const reportPath = join(job, 'qa', 'explainer-frame-metrics.json');
    const report = JSON.parse(readFileSync(reportPath, 'utf8'));
    assert.match(report.propsSha256, /^[0-9a-f]{64}$/);
    assert.equal(report.propsSha256, createHash('sha256').update(readFileSync(propsPath)).digest('hex'));
    assert.equal(report.frames, 15);
    assert.equal(report.canvas.width, width);
    assert.equal(report.perShot.length, 2);
    assert.ok(report.perShot[0].heroMedianPx >= RULES.heroSmall * height);
    assert.ok(report.film.high >= 1);
    assert.equal(report.film.ok, false);
    // The release gate reads these fields by name; a report without them binds
    // to a gate that cannot see the finding.
    for (const field of ['longestStaticSeconds', 'longestEmptyRunFrames', 'longestEmptyRunSeconds', 'heroMedianPx', 'debrisMedian', 'cuts']) {
      assert.equal(typeof report.film[field], 'number', field);
    }
    assert.equal(report.fps, 30);

    const lenient = runCli(args);
    assert.equal(lenient.code, 0, lenient.out);
    assert.equal(JSON.parse(lenient.stdout.trim()).high, report.film.high, 'without --strict the finding is reported, not enforced');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
