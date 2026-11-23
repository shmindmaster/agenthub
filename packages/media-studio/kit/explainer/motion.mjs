/**
 * The motion vocabulary: every entrance has a name, a frame count at 30 fps and
 * one easing family, so a film reads as one hand instead of a pile of effects.
 *
 * A shot never guesses a duration. It asks for a named motion and gets the
 * progress curve for the current frame; the same numbers drive the Node-side
 * gates, so a shot cannot claim a timing the picture does not use.
 */

export const REFERENCE_FPS = 30;

export const EASINGS = {
  linear: (t) => t,
  out: (t) => 1 - Math.pow(1 - t, 3),
  inOut: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  back: (t) => {
    const c = 1.70158;
    const p = t - 1;
    return 1 + (c + 1) * p * p * p + c * p * p;
  },
};

/**
 * `frames` is at REFERENCE_FPS. `push` and `drift` are the only motions that
 * run for the whole shot; everything else is an entrance with a fixed cost.
 */
export const MOTION = {
  settle: { frames: 8, ease: 'out', kind: 'fade' },
  fade: { frames: 12, ease: 'out', kind: 'fade' },
  pop: { frames: 12, ease: 'back', kind: 'pop' },
  rise: { frames: 18, ease: 'out', kind: 'rise' },
  slide: { frames: 16, ease: 'out', kind: 'slide' },
  wipe: { frames: 20, ease: 'inOut', kind: 'wipe' },
  bloom: { frames: 24, ease: 'out', kind: 'bloom' },
  draw: { frames: 30, ease: 'inOut', kind: 'draw' },
  push: { frames: 0, ease: 'linear', kind: 'push' },
  drift: { frames: 0, ease: 'linear', kind: 'drift' },
};

/** Siblings land this far apart, at 30 fps. */
export const STAGGER_FRAMES = 5;

export const motionNames = () => Object.keys(MOTION);

const spec = (name) => {
  const found = MOTION[name];
  if (!found) throw new Error(`unknown motion "${name}"`);
  return found;
};

/** Frame cost of a motion, scaled from the 30 fps reference. */
export const framesOf = (name, fps = REFERENCE_FPS) => {
  const { frames } = spec(name);
  if (!frames) return 0;
  return Math.max(1, Math.round((frames * fps) / REFERENCE_FPS));
};

/** Seconds cost of a motion at a given fps. */
export const secondsOf = (name, fps = REFERENCE_FPS) => framesOf(name, fps) / fps;

/**
 * Progress 0..1 for a motion that starts at `atSeconds`.
 * `durationSeconds` is the shot length; whole-shot motions use it.
 */
export const progress = (name, frame, fps, atSeconds = 0, durationSeconds = 0) => {
  const { ease } = spec(name);
  const cost = framesOf(name, fps);
  const span = cost || Math.max(1, Math.round(durationSeconds * fps));
  const local = frame - Math.round(atSeconds * fps);
  if (local <= 0) return 0;
  if (local >= span) return 1;
  return EASINGS[ease](local / span);
};

/**
 * The style an element carries at progress `p`. Returned as plain CSS-ish
 * values so the Remotion components only spread them.
 */
export const enter = (name, p, options = {}) => {
  const { kind } = spec(name);
  const distance = options.distance ?? 18;
  const from = options.from ?? 'below';
  const t = Math.min(1, Math.max(0, p));
  const slideX = from === 'left' ? -distance : from === 'right' ? distance : 0;
  const slideY = from === 'above' ? -distance : from === 'below' ? distance : 0;

  switch (kind) {
    case 'fade':
      return { opacity: t };
    case 'rise':
      return { opacity: t, translate: `0px ${(1 - t) * distance}px` };
    case 'slide':
      return { opacity: t, translate: `${(1 - t) * slideX}px ${(1 - t) * slideY}px` };
    case 'pop':
      return { opacity: Math.min(1, t * 1.4), scale: 0.9 + 0.1 * t };
    case 'bloom':
      return { opacity: t, scale: 0.97 + 0.03 * t, filter: `blur(${(1 - t) * 6}px)` };
    case 'wipe':
      return { opacity: 1, clipPath: `inset(0 ${(1 - t) * 100}% 0 0)` };
    case 'draw':
      return { opacity: 1, strokeDashoffset: 1 - t };
    case 'push':
      return { opacity: 1, scale: 1 + 0.045 * t };
    case 'drift':
      return { opacity: 1, translate: `${(1 - t) * -12}px 0px` };
    default:
      return { opacity: t };
  }
};

/** Staggered start for sibling `index` of `count`, in frames. */
export const staggerFrames = (index, gap = STAGGER_FRAMES) => Math.max(0, index) * gap;
