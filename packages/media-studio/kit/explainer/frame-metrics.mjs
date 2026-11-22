/**
 * Measured frame properties for the explainer: the numbers a picture gate can
 * fail on.
 *
 * The older gates admit their own limit — check_visual_variety "proves variety,
 * not quality" and check_picture_relevance "does not judge design" — because a
 * weak film and a strong one share almost the same motion total (the reference
 * pair measured 0.47 vs 0.56 mean frame change). What separated them was
 * measurable: hero size, a lit hero, empty stretches, background debris and a
 * landing hold. This file turns those five things into numbers so a gate can
 * refuse a film instead of describing it.
 *
 * Why the thresholds are fractions of the canvas: they were measured on a
 * 1280x720 reference film and we render at 1600x1000. A pixel threshold would
 * silently loosen at the bigger canvas, so every rule is expressed against the
 * reference height (see RULES) and multiplied by the canvas height at scoring
 * time.
 *
 * Raw RGBA8 in, plain numbers out: no fs, no dependencies, no clock.
 */

/** The film the reference thresholds were measured on. */
export const REFERENCE_HEIGHT = 720;

/** Downscale the static/cut comparison runs on: small enough to be cheap, big enough to see a bar move. */
export const PROFILE_WIDTH = 320;
export const PROFILE_HEIGHT = 180;

/** Chrome lives in the top and bottom bands; a clock or a progress bar must not read as picture change. */
const CONTENT_TOP = 0.08;
const CONTENT_BOTTOM = 0.12;

const WIDE_FLAT_DIVISOR = 2.5;
const GLOW_PAD_PX = 30;

/**
 * Every threshold the explainer gate uses, in reference units. Exported as one
 * object so the CLI report can print the numbers it actually judged with.
 */
export const RULES = {
  // 170/720 is a hero that owns the frame; 110/720 is the smallest hero that
  // still reads as the picture; 80/720 is furniture.
  heroStrong: 170 / REFERENCE_HEIGHT,
  heroSmall: 110 / REFERENCE_HEIGHT,
  heroEmpty: 80 / REFERENCE_HEIGHT,
  minLumaStd: 14,
  minInkCoverage: 0.02,
  maxDebris: 10,
  // 800 saturated pixels of a 1280x720 frame: a glow behind the hero, not a
  // coloured headline.
  minGlowFraction: 0.000868,
  // Mean absolute grey difference per sampled frame, 0-255 scale.
  staticChange: 0.35,
  cutChange: 12,
  maxStaticRunSeconds: 3,
  emptyRunFrames: 45,
  landingHoldFrames: 30,
  glowOffFrames: 6,
};

/** Type-only families whose "hero" is deliberately small: a chapter card is two lines. */
export const EXEMPT_FAMILIES = Object.freeze(['chapter', 'end']);
const EXEMPT_ARCHETYPE = 'chapter-card';

/* ---------------------------------------------------------------- guards -- */

const bad = (message) => {
  throw new Error(`frame-metrics: ${message}`);
};

const isBytes = (value) => value instanceof Uint8Array || value instanceof Uint8ClampedArray;

const finite = (value, name) => {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    bad(`${name} must be a finite number, got ${value}`);
  }
  return value;
};

const positive = (value, name) => {
  finite(value, name);
  if (value <= 0) bad(`${name} must be greater than zero, got ${value}`);
  return value;
};

const count = (value, name, { min = 1 } = {}) => {
  if (!Number.isInteger(value) || value < min) {
    bad(`${name} must be an integer >= ${min}, got ${value}`);
  }
  return value;
};

const fraction = (value, name) => {
  finite(value, name);
  if (value < 0 || value > 1) bad(`${name} must be between 0 and 1, got ${value}`);
  return value;
};

const requireRgba = (rgba, width, height) => {
  count(width, 'width');
  count(height, 'height');
  if (!isBytes(rgba)) bad('rgba must be a Uint8Array of RGBA bytes (4 per pixel, row-major)');
  const needed = width * height * 4;
  if (rgba.length !== needed) {
    bad(`rgba length ${rgba.length} does not match ${width}x${height}x4 = ${needed}`);
  }
  return needed;
};

/** Accept either the Float32Array or the object toGrey returns, so callers cannot pass the wrong one by accident. */
const greyOf = (input, name = 'grey') => {
  if (input instanceof Float32Array) {
    if (!input.length) bad(`${name} is an empty buffer`);
    return input;
  }
  if (input && input.grey instanceof Float32Array) {
    if (!input.grey.length) bad(`${name}.grey is an empty buffer`);
    return input.grey;
  }
  bad(`${name} must be the object toGrey() returns, or its .grey buffer`);
  return null;
};

/* ------------------------------------------------------------------ luma -- */

/**
 * Rec.601 luma on the sampled grid. `width`/`height` in the result are the
 * sampled grid, not the source frame: multiply a cell coordinate by `step` to
 * get back to source pixels (frameMetrics does exactly that for the hero box).
 */
export const toGrey = (rgba, width, height, options = {}) => {
  requireRgba(rgba, width, height);
  const step = count(options.step ?? 1, 'step');
  const gridW = Math.ceil(width / step);
  const gridH = Math.ceil(height / step);
  const grey = new Float32Array(gridW * gridH);
  let out = 0;
  for (let gy = 0; gy < gridH; gy += 1) {
    const row = gy * step * width * 4;
    for (let gx = 0; gx < gridW; gx += 1) {
      const i = row + gx * step * 4;
      grey[out] = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
      out += 1;
    }
  }
  return { grey, width: gridW, height: gridH, step, sourceWidth: width, sourceHeight: height };
};

/**
 * Median, not mean: a frame of light type on a dark field is mostly ink by
 * area, and the mean would drift with the amount of type. The median is the
 * backdrop whatever is written on it.
 */
export const backgroundLuma = (input) => {
  const grey = greyOf(input);
  const sorted = grey.slice().sort();
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

/**
 * A contrast mask, not a brightness mask: |luma - backdrop| above the floor.
 * Written the other way round it would call light type on a dark field
 * background and quietly measure nothing.
 */
export const inkMask = (input, options = {}) => {
  const grey = greyOf(input);
  const floor = finite(options.floor ?? 18, 'floor');
  if (floor < 0) bad(`floor must not be negative, got ${floor}`);
  const background = backgroundLuma(grey);
  const mask = new Uint8Array(grey.length);
  for (let i = 0; i < grey.length; i += 1) {
    if (Math.abs(grey[i] - background) > floor) mask[i] = 1;
  }
  return mask;
};

/* ------------------------------------------------------------ components -- */

/**
 * Extend every ink run by `reach` cells in both directions along one axis.
 * Two directional passes over the source, so a cell can never chain off a cell
 * this pass just wrote: dilation must not creep across the frame.
 */
const spread = (src, width, height, reach, horizontal) => {
  const out = new Uint8Array(src.length);
  const outer = horizontal ? height : width;
  const inner = horizontal ? width : height;
  const stride = horizontal ? 1 : width;
  const baseStep = horizontal ? width : 1;
  const far = reach + 1;
  for (let o = 0; o < outer; o += 1) {
    const base = o * baseStep;
    let distance = far;
    for (let i = 0; i < inner; i += 1) {
      const p = base + i * stride;
      if (src[p]) distance = 0;
      else if (distance <= reach) distance += 1;
      else continue;
      if (distance <= reach) out[p] = 1;
    }
    distance = far;
    for (let i = inner - 1; i >= 0; i -= 1) {
      const p = base + i * stride;
      if (src[p]) distance = 0;
      else if (distance <= reach) distance += 1;
      else continue;
      if (distance <= reach) out[p] = 1;
    }
  }
  return out;
};

const dilate = (mask, width, height, dx, dy) => {
  let out = mask;
  if (dx > 0) out = spread(out, width, height, dx, true);
  if (dy > 0) out = spread(out, width, height, dy, false);
  return out;
};

/**
 * Ink components. Dilation exists so the letters of one line become one
 * object: a headline measured letter by letter is always "small". Dilation is
 * generous horizontally and mean vertically, because joining two lines is how
 * a gate stops seeing the line it was supposed to measure.
 *
 * Boxes and `area` are measured on the undilated ink; dilation only decides
 * which ink belongs together.
 */
export const components = (mask, width, height, options = {}) => {
  count(width, 'width');
  count(height, 'height');
  if (!(mask instanceof Uint8Array)) bad('mask must be the Uint8Array inkMask() returns');
  const total = width * height;
  if (mask.length !== total) bad(`mask length ${mask.length} does not match ${width}x${height} = ${total}`);
  const dilateX = count(options.dilateX ?? 6, 'dilateX', { min: 0 });
  const dilateY = count(options.dilateY ?? 1, 'dilateY', { min: 0 });
  const minPixels = count(options.minPixels ?? 24, 'minPixels', { min: 0 });

  const joined = dilate(mask, width, height, dilateX, dilateY);
  const labels = new Int32Array(total).fill(-1);
  const stack = new Int32Array(total);
  let labelCount = 0;

  for (let start = 0; start < total; start += 1) {
    if (!joined[start] || labels[start] >= 0) continue;
    const id = labelCount;
    labelCount += 1;
    let top = 0;
    labels[start] = id;
    stack[top] = start;
    top += 1;
    while (top > 0) {
      top -= 1;
      const p = stack[top];
      const x = p % width;
      const y = (p - x) / width;
      if (x > 0 && joined[p - 1] && labels[p - 1] < 0) {
        labels[p - 1] = id;
        stack[top] = p - 1;
        top += 1;
      }
      if (x + 1 < width && joined[p + 1] && labels[p + 1] < 0) {
        labels[p + 1] = id;
        stack[top] = p + 1;
        top += 1;
      }
      if (y > 0 && joined[p - width] && labels[p - width] < 0) {
        labels[p - width] = id;
        stack[top] = p - width;
        top += 1;
      }
      if (y + 1 < height && joined[p + width] && labels[p + width] < 0) {
        labels[p + width] = id;
        stack[top] = p + width;
        top += 1;
      }
    }
  }

  const area = new Int32Array(labelCount);
  const ink = Array.from({ length: labelCount }, () => ({ x0: width, y0: height, x1: -1, y1: -1 }));
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const p = y * width + x;
      if (!mask[p]) continue;
      const id = labels[p];
      if (id < 0) continue;
      area[id] += 1;
      const box = ink[id];
      if (x < box.x0) box.x0 = x;
      if (x > box.x1) box.x1 = x;
      if (y < box.y0) box.y0 = y;
      if (y > box.y1) box.y1 = y;
    }
  }

  const out = [];
  for (let id = 0; id < labelCount; id += 1) {
    if (area[id] < minPixels || area[id] === 0) continue;
    const box = ink[id];
    out.push({ x: box.x0, y: box.y0, w: box.x1 - box.x0 + 1, h: box.y1 - box.y0 + 1, area: area[id] });
  }
  return out;
};

/**
 * Visual mass, not height. A wide flat object — a rule, a headline, a strip
 * diagram — carries more weight than its height suggests, so width counts up
 * to `wideFlatRatio` x height; past that cap it is chrome and the height is
 * the honest measure. The divisor turns a capped width into the equivalent
 * type height the hero would need to fill the frame the same way.
 */
export const heroScore = (component, wideFlatRatio = 4) => {
  if (!component || typeof component !== 'object') bad('component must be an object with w and h');
  const w = finite(component.w, 'component.w');
  const h = finite(component.h, 'component.h');
  if (w < 0 || h < 0) bad(`component.w and component.h must not be negative, got ${w}x${h}`);
  return Math.max(h, Math.min(w, wideFlatRatio * h) / WIDE_FLAT_DIVISOR);
};

const heroIndexOf = (list, wideFlatRatio) => {
  let best = -1;
  let score = -Infinity;
  for (let i = 0; i < list.length; i += 1) {
    const value = heroScore(list[i], wideFlatRatio);
    if (value > score) {
      score = value;
      best = i;
    }
  }
  return best;
};

/** The component with the largest visual mass, plus `height` = the score it won with. */
export const heroOf = (list, options = {}) => {
  if (!Array.isArray(list)) bad('components must be an array');
  const ratio = positive(options.wideFlatRatio ?? 4, 'wideFlatRatio');
  const index = heroIndexOf(list, ratio);
  if (index < 0) return null;
  return { ...list[index], height: heroScore(list[index], ratio) };
};

/**
 * Background debris: small ink fragments — a stray rule, a caption fragment, a
 * decorative dot — that survive the mask. Excludes the hero by score, never by
 * reference, because the hero is returned as a copy.
 */
export const debrisCount = (list, options = {}) => {
  if (!Array.isArray(list)) bad('components must be an array');
  const maxW = positive(options.maxW ?? 96, 'maxW');
  const maxH = positive(options.maxH ?? 32, 'maxH');
  const minPixels = count(options.minPixels ?? 30, 'minPixels', { min: 0 });
  const hero = heroIndexOf(list, positive(options.wideFlatRatio ?? 4, 'wideFlatRatio'));
  let debris = 0;
  for (let i = 0; i < list.length; i += 1) {
    if (i === hero) continue;
    const c = list[i];
    if (c.area < minPixels) continue;
    if (c.w <= maxW && c.h <= maxH) debris += 1;
  }
  return debris;
};

/* ------------------------------------------------------------------ glow -- */

/**
 * Saturated mid-luminance pixels: the dim coloured light a hero sits in. Bright
 * accent type is saturated but far too light to be a glow, and a grey scrim has
 * no saturation, so both stay out of the count.
 *
 * `box` is in source pixels; the pad is the reference 30 px scaled with the
 * frame height, so a 1600x1000 hero gets the same visual halo as a 720p one.
 * Returns a pixel count — divide by the frame area for the fraction RULES uses.
 */
export const glowArea = (rgba, width, height, box = null, options = {}) => {
  requireRgba(rgba, width, height);
  const step = count(options.step ?? 1, 'step');
  const satMin = fraction(options.satMin ?? 0.25, 'satMin');
  const lumMin = finite(options.lumMin ?? 10, 'lumMin');
  const lumMax = finite(options.lumMax ?? 110, 'lumMax');
  if (lumMin > lumMax) bad(`lumMin ${lumMin} is above lumMax ${lumMax}`);
  if (box && typeof box !== 'object') bad('box must be an object with x, y, w and h, or null for the whole frame');

  const pad = Math.round((GLOW_PAD_PX * height) / REFERENCE_HEIGHT);
  const left = box ? Math.max(0, Math.round(finite(box.x, 'box.x')) - pad) : 0;
  const top = box ? Math.max(0, Math.round(finite(box.y, 'box.y')) - pad) : 0;
  const right = box ? Math.min(width - 1, Math.round(finite(box.x, 'box.x') + positive(box.w, 'box.w')) + pad) : width - 1;
  const bottom = box ? Math.min(height - 1, Math.round(finite(box.y, 'box.y') + positive(box.h, 'box.h')) + pad) : height - 1;
  if (right < left || bottom < top) return 0;

  let found = 0;
  for (let y = top; y <= bottom; y += step) {
    const row = y * width * 4;
    for (let x = left; x <= right; x += step) {
      const i = row + x * 4;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const max = r > g ? (r > b ? r : b) : g > b ? g : b;
      if (max === 0) continue;
      const min = r < g ? (r < b ? r : b) : g < b ? g : b;
      const luma = 0.299 * r + 0.587 * g + 0.114 * b;
      if (luma < lumMin || luma > lumMax) continue;
      if ((max - min) / max < satMin) continue;
      found += 1;
    }
  }
  return found;
};

/* ---------------------------------------------------------------- frames -- */

/**
 * Every number one frame contributes. The hero box is reported in source
 * pixels; `glow` is a fraction of the frame area and `debris` a count, so the
 * scoring rules need nothing but these numbers and a canvas height.
 */
export const frameMetrics = (rgba, width, height, options = {}) => {
  requireRgba(rgba, width, height);
  const step = count(options.step ?? 1, 'step');

  const grid = toGrey(rgba, width, height, { step });
  const background = backgroundLuma(grid);
  const mask = inkMask(grid, { floor: options.floor ?? 18 });
  const found = components(mask, grid.width, grid.height, {
    dilateX: options.dilateX ?? 6,
    dilateY: options.dilateY ?? 1,
    minPixels: options.minPixels ?? 24,
  });
  const heroGrid = heroOf(found, { wideFlatRatio: options.wideFlatRatio ?? 4 });
  const hero = heroGrid
    ? {
        x: heroGrid.x * step,
        y: heroGrid.y * step,
        w: heroGrid.w * step,
        h: heroGrid.h * step,
        height: heroGrid.height * step,
      }
    : null;

  const debris = debrisCount(found, {
    maxW: options.debrisMaxW ?? Math.max(1, Math.round((width * 0.06) / step)),
    maxH: options.debrisMaxH ?? Math.max(1, Math.round((height * 0.04) / step)),
    minPixels: options.debrisMinPixels ?? 0,
    wideFlatRatio: options.wideFlatRatio ?? 4,
  });

  // Glow is counted at full resolution on purpose: the rule is a fraction of
  // the frame area, and sampling would need rescaling that no caller remembers.
  const box = hero ?? { x: 0, y: 0, w: width, h: height };
  const glowPixels = glowArea(rgba, width, height, box, { ...(options.glow ?? {}), step: 1 });

  let sum = 0;
  let sumSq = 0;
  let ink = 0;
  for (let i = 0; i < grid.grey.length; i += 1) {
    const v = grid.grey[i];
    sum += v;
    sumSq += v * v;
    if (mask[i]) ink += 1;
  }
  const samples = grid.grey.length;
  const meanLuma = sum / samples;
  return {
    meanLuma,
    lumaStd: Math.sqrt(Math.max(0, sumSq / samples - meanLuma * meanLuma)),
    inkCoverage: ink / samples,
    hero,
    debris,
    glow: glowPixels / (width * height),
    glowPixels,
    background,
    componentCount: found.length,
    step,
  };
};

/**
 * Per-frame verdict. Thresholds are fractions of canvas height (RULES), so the
 * same film judged at 1600x1000 and at 720p lands on the same level.
 *
 * `rules.family` (or `metrics.family`) exempts a chapter or end card from
 * `hero-small`: those frames are two lines by design. Nothing else is exempt —
 * an empty chapter card should still fail.
 */
export const scoreFrame = (metrics, canvas, rules = {}) => {
  if (!metrics || typeof metrics !== 'object') bad('metrics must be the object frameMetrics() returned');
  if (!canvas || typeof canvas !== 'object') bad('canvas is required');
  const height = positive(canvas.height, 'canvas.height');
  positive(canvas.width, 'canvas.width');

  const heroStrong = positive(rules.heroStrong ?? RULES.heroStrong, 'heroStrong');
  const heroSmall = positive(rules.heroSmall ?? RULES.heroSmall, 'heroSmall');
  const heroEmpty = positive(rules.heroEmpty ?? RULES.heroEmpty, 'heroEmpty');
  const minLumaStd = finite(rules.minLumaStd ?? RULES.minLumaStd, 'minLumaStd');
  const minInkCoverage = finite(rules.minInkCoverage ?? RULES.minInkCoverage, 'minInkCoverage');
  const maxDebris = count(rules.maxDebris ?? RULES.maxDebris, 'maxDebris', { min: 0 });
  const minGlow = finite(rules.minGlowFraction ?? RULES.minGlowFraction, 'minGlowFraction');

  const family = rules.family ?? metrics.family ?? null;
  const exempt =
    rules.archetype === EXEMPT_ARCHETYPE ||
    (Array.isArray(rules.exemptFamilies) && rules.exemptFamilies.includes(family)) ||
    EXEMPT_FAMILIES.includes(family);

  const emptyAt = heroEmpty * height;
  const smallAt = heroSmall * height;
  const heroHeight = metrics.hero ? finite(metrics.hero.height, 'metrics.hero.height') : 0;
  const flags = [];
  const flag = (rule, level, message) => flags.push({ rule, level, message });

  if (!metrics.hero || heroHeight < emptyAt) {
    flag(
      'hero-empty',
      'high',
      `no picture or type mass reaches ${Math.round(emptyAt)} px of a ${Math.round(height)} px frame (hero ${Math.round(heroHeight)} px); the frame is furniture`,
    );
  } else if (heroHeight < smallAt && !exempt) {
    flag(
      'hero-small',
      'medium',
      `hero scores ${Math.round(heroHeight)} px of a ${Math.round(height)} px frame; it is under ${Math.round(smallAt)} px and a strong hero is ${Math.round(heroStrong * height)} px`,
    );
  }

  const lumaStd = finite(metrics.lumaStd, 'metrics.lumaStd');
  if (lumaStd < minLumaStd) {
    flag('flat-frame', 'high', `luma standard deviation ${lumaStd.toFixed(1)} is under ${minLumaStd}; the frame has no contrast to look at`);
  }
  const inkCoverage = finite(metrics.inkCoverage, 'metrics.inkCoverage');
  if (inkCoverage < minInkCoverage) {
    flag('empty-frame', 'high', `ink covers ${(inkCoverage * 100).toFixed(2)}% of the frame, under ${(minInkCoverage * 100).toFixed(0)}%; nothing is on screen`);
  }
  const debris = count(metrics.debris ?? 0, 'metrics.debris', { min: 0 });
  if (debris > maxDebris) {
    flag('debris', 'medium', `${debris} small ink fragments other than the hero; the background is carrying leftovers`);
  }
  const glow = finite(metrics.glow ?? 0, 'metrics.glow');
  if (glow < minGlow) {
    flag('hero-unlit', 'medium', `lit area is ${(glow * 100).toFixed(3)}% of the frame, under ${(minGlow * 100).toFixed(3)}%; the hero sits on the backdrop instead of in it`);
  }

  const rank = { ok: 0, low: 1, medium: 2, high: 3 };
  const level = flags.reduce((worst, entry) => (rank[entry.level] > rank[worst] ? entry.level : worst), 'ok');
  return { level, flags };
};

/* -------------------------------------------------------------- sequence -- */

/**
 * 320x180 luma of the content band, area-averaged. Area averaging rather than
 * sampling, because a bar two pixels wide still has to move the comparison;
 * excluding the chrome bands, because a ticking progress bar or a burning
 * clock is not the picture changing.
 */
export const contentProfile = (rgba, width, height) => {
  requireRgba(rgba, width, height);
  const top = Math.floor(height * CONTENT_TOP);
  const bottom = Math.max(top + 1, Math.ceil(height * (1 - CONTENT_BOTTOM)));
  const band = bottom - top;
  const profile = new Float32Array(PROFILE_WIDTH * PROFILE_HEIGHT);
  for (let gy = 0; gy < PROFILE_HEIGHT; gy += 1) {
    const y0 = top + Math.floor((band * gy) / PROFILE_HEIGHT);
    const y1 = Math.max(y0 + 1, top + Math.floor((band * (gy + 1)) / PROFILE_HEIGHT));
    for (let gx = 0; gx < PROFILE_WIDTH; gx += 1) {
      const x0 = Math.floor((width * gx) / PROFILE_WIDTH);
      const x1 = Math.max(x0 + 1, Math.floor((width * (gx + 1)) / PROFILE_WIDTH));
      let sum = 0;
      let n = 0;
      for (let y = y0; y < y1; y += 1) {
        let i = (y * width + x0) * 4;
        for (let x = x0; x < x1; x += 1) {
          sum += 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
          i += 4;
          n += 1;
        }
      }
      profile[gy * PROFILE_WIDTH + gx] = sum / n;
    }
  }
  return profile;
};

const meanAbsDiff = (a, b) => {
  let sum = 0;
  for (let i = 0; i < a.length; i += 1) sum += Math.abs(a[i] - b[i]);
  return sum / a.length;
};

const profileOf = (frame, index) => {
  if (frame.profile !== undefined) {
    if (!(frame.profile instanceof Float32Array) || frame.profile.length !== PROFILE_WIDTH * PROFILE_HEIGHT) {
      bad(`frames[${index}].profile must be a ${PROFILE_WIDTH}x${PROFILE_HEIGHT} Float32Array`);
    }
    return frame.profile;
  }
  return contentProfile(frame.rgba, frame.width, frame.height);
};

const checkFrame = (frame, index) => {
  if (!frame || typeof frame !== 'object') bad(`frames[${index}] must be {index, rgba, width, height}`);
  if (!Number.isInteger(frame.index) || frame.index < 1) {
    bad(`frames[${index}].index must be the 1-based frame number, got ${frame.index}`);
  }
  if (frame.profile === undefined) requireRgba(frame.rgba, frame.width, frame.height);
  else {
    count(frame.width, 'width');
    count(frame.height, 'height');
  }
};

const shotAt = (shots, index) => {
  const filmFrame = index - 1;
  for (const shot of shots) {
    const start = shot.startFrame;
    const span = shot.durationFrames;
    if (!Number.isFinite(start) || !Number.isFinite(span)) continue;
    if (filmFrame >= start && filmFrame < start + span) return shot;
  }
  return null;
};

const median = (values) => {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

/**
 * Sequence-level findings. Frames are the sampled ones (index is the 1-based
 * film frame), so every span is multiplied by `step` before it is reported in
 * seconds; otherwise a step of 4 would make a 4x longer hold look identical to
 * a 1x one.
 *
 * A frame may carry `profile` and `metrics` already computed by the caller:
 * the CLI decodes one frame at a time and must not hold every RGBA buffer.
 */
export const analyzeSequence = (frames, canvas, options = {}) => {
  if (!Array.isArray(frames) || frames.length === 0) {
    bad('frames must be a non-empty array of {index, rgba, width, height}');
  }
  if (!canvas || typeof canvas !== 'object') bad('canvas is required');
  const canvasHeight = positive(canvas.height, 'canvas.height');
  positive(canvas.width, 'canvas.width');
  const fps = positive(options.fps ?? 30, 'fps');
  const step = count(options.step ?? 1, 'step');
  const rules = { ...RULES, ...(options.rules ?? {}) };
  const shots = Array.isArray(options.shots) ? options.shots : [];
  const setPieces = new Set(Array.isArray(options.setPieceShots) ? options.setPieceShots : []);
  const grace = Math.round((40 * fps) / 30);
  const emptyAt = rules.heroSmall * canvasHeight;
  const minEmptySpan = Math.ceil((rules.emptyRunFrames * fps) / 30);

  const perFrame = [];
  const staticRuns = [];
  const cuts = [];
  const emptyRuns = [];
  let previous = null;
  let staticStart = null;
  let emptyStart = null;

  frames.forEach((frame, i) => {
    checkFrame(frame, i);
    if (previous && frame.index <= previous.index) {
      bad(`frames[${i}].index ${frame.index} does not increase; frames must be sorted by frame number`);
    }
    const metrics =
      frame.metrics ?? frameMetrics(frame.rgba, frame.width, frame.height, options.metrics ?? {});
    const profile = profileOf(frame, i);
    const change = previous ? meanAbsDiff(profile, previous.profile) : null;
    const shot = shotAt(shots, frame.index);
    const heroHeight = metrics.hero ? metrics.hero.height : 0;
    const inGrace = Boolean(
      shot && setPieces.has(shot.id) && frame.index - 1 - shot.startFrame < grace,
    );
    const empty = heroHeight < emptyAt && !inGrace;
    const still = change !== null && change < rules.staticChange;

    perFrame.push({
      index: frame.index,
      t: (frame.index - 1) / fps,
      width: frame.width,
      height: frame.height,
      ...metrics,
      change,
      static: still,
      empty,
      shotId: shot ? shot.id : null,
      family: shot ? shot.family ?? null : null,
      setPieceGrace: inGrace,
    });

    // A static run is a stretch between two samples that look the same; the
    // frame before the first unchanged pair is the frame the hold began on.
    if (still) {
      if (staticStart === null) staticStart = previous.index;
    } else if (staticStart !== null) {
      const end = previous.index;
      if (end - staticStart >= step) {
        staticRuns.push({
          startFrame: staticStart,
          endFrame: end,
          frames: end - staticStart + step,
          seconds: (end - staticStart) / fps,
        });
      }
      staticStart = null;
    }
    if (change !== null && change > rules.cutChange) {
      cuts.push({ frame: frame.index, previous: previous.index, from: metrics.meanLuma, change });
    }

    if (empty) {
      if (emptyStart === null) emptyStart = frame.index;
    } else if (emptyStart !== null) {
      const span = previous.index - emptyStart + step;
      if (span >= minEmptySpan) {
        emptyRuns.push({ startFrame: emptyStart, endFrame: previous.index, frames: span, seconds: span / fps });
      }
      emptyStart = null;
    }

    previous = { index: frame.index, profile };
  });
  const last = perFrame[perFrame.length - 1];
  if (staticStart !== null && last.index - staticStart >= step) {
    staticRuns.push({
      startFrame: staticStart,
      endFrame: last.index,
      frames: last.index - staticStart + step,
      seconds: (last.index - staticStart) / fps,
    });
  }
  if (emptyStart !== null) {
    const span = last.index - emptyStart + step;
    if (span >= minEmptySpan) {
      emptyRuns.push({ startFrame: emptyStart, endFrame: last.index, frames: span, seconds: span / fps });
    }
  }

  const longestStaticSeconds = staticRuns.reduce((max, run) => Math.max(max, run.seconds), 0);
  return {
    longestStaticSeconds,
    staticRuns,
    cuts,
    emptyRuns,
    perFrame,
    thresholds: {
      heroSmallPx: emptyAt,
      emptyRunFrames: rules.emptyRunFrames,
      minEmptySpanFrames: minEmptySpan,
      staticChange: rules.staticChange,
      cutChange: rules.cutChange,
      setPieceGraceFrames: grace,
    },
    medianHero: median(perFrame.map((frame) => (frame.hero ? frame.hero.height : 0))),
  };
};

/**
 * How long the last picture is held. The tail of a film is where a strong cut
 * lands on its final frame and a weak one keeps drifting; `glowOffFrames`
 * forgives the light decay that follows a hero settling, which is motion the
 * viewer reads as intentional.
 */
export const landingHold = (frames, options = {}) => {
  if (!Array.isArray(frames) || frames.length === 0) bad('frames must be a non-empty array');
  const fps = positive(options.fps ?? 30, 'fps');
  const step = count(options.step ?? 1, 'step');
  const threshold = finite(options.threshold ?? 1.5, 'threshold');
  const glowOffFrames = count(options.glowOffFrames ?? RULES.glowOffFrames, 'glowOffFrames', { min: 0 });
  frames.forEach(checkFrame);
  if (frames.length < 2) return { frames: 0, seconds: 0, heldFrames: 0, samples: 0 };

  let held = 0;
  let next = profileOf(frames[frames.length - 1], frames.length - 1);
  for (let i = frames.length - 1; i > 0; i -= 1) {
    const before = profileOf(frames[i - 1], i - 1);
    if (meanAbsDiff(next, before) < threshold) held += 1;
    else break;
    next = before;
  }
  const heldFrames = held * step;
  const net = Math.max(0, heldFrames - glowOffFrames);
  return { frames: net, seconds: net / fps, heldFrames, samples: held };
};

/**
 * Film aggregate. A high flag fails; a long static run or a short landing hold
 * is medium (the film will read as drifting, not broken); an empty run over
 * the limit is high, because that is a stretch where nothing is on screen.
 */
export const scoreFilm = (report, rules = {}) => {
  if (!report || typeof report !== 'object') bad('report must be the object analyzeSequence() returned, plus landingHold');
  const merged = { ...RULES, ...rules };
  const flags = [];

  const perFrame = Array.isArray(report.perFrame) ? report.perFrame : [];
  for (const frame of perFrame) {
    const list = Array.isArray(frame.flags) ? frame.flags : frame.score?.flags ?? [];
    for (const entry of list) {
      if (!entry || typeof entry !== 'object') continue;
      flags.push({ ...entry, frame: frame.index });
    }
  }

  for (const run of Array.isArray(report.staticRuns) ? report.staticRuns : []) {
    if (!(run.seconds > merged.maxStaticRunSeconds)) continue;
    flags.push({
      rule: 'static-run',
      level: 'medium',
      message: `${run.seconds.toFixed(2)} s with no picture change from frame ${run.startFrame}; the limit is ${merged.maxStaticRunSeconds} s`,
      startFrame: run.startFrame,
      endFrame: run.endFrame,
    });
  }

  for (const run of Array.isArray(report.emptyRuns) ? report.emptyRuns : []) {
    if (!(run.frames > merged.emptyRunFrames)) continue;
    flags.push({
      rule: 'empty-run',
      level: 'high',
      message: `${run.frames} frames from ${run.startFrame} have no hero over ${Math.round(merged.heroSmall * 1000) / 10}% of the frame height`,
      startFrame: run.startFrame,
      endFrame: run.endFrame,
    });
  }

  const hold = report.landingHold;
  if (hold && Number.isFinite(hold.frames) && hold.frames < merged.landingHoldFrames) {
    flags.push({
      rule: 'landing-hold',
      level: 'medium',
      message: `the last picture is held ${hold.frames} frames, under ${merged.landingHoldFrames}; the film steps off its own ending`,
    });
  }

  const tally = (level) => flags.filter((entry) => entry.level === level).length;
  const high = tally('high');
  return { ok: high === 0, high, medium: tally('medium'), low: tally('low'), flags };
};
