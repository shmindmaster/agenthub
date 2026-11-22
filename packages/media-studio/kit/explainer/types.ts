/**
 * The explainer film as the renderer, the builder and the release gate agree on
 * it.
 *
 * kit/explainer/build-explainer.mjs writes these props and
 * kit/explainer/validate-explainer-release.mjs refuses them, so the field names here
 * are the contract between two processes that never read each other's code.
 * `visual` is the kit's own Visual union rather than a copy of it: a picture
 * primitive gains a field once and every explainer shot can use it.
 *
 * The three values at the bottom are this layer's leaf. theme.mjs reads
 * theme.json through node:fs and cannot be pulled into a browser bundle, so the
 * components read the same JSON directly; keeping the alpha rule and the
 * frame-to-shot lookup here means Stage, Chrome and every shot agree on which
 * shot is live instead of each resolving it slightly differently.
 */
import type { Visual } from '../src/Visuals';
import { FAMILIES } from './grammar.mjs';
import theme from './theme.json';

/** A composition family: the grammar's keys, one renderer each in shots.tsx. */
export type Family = keyof typeof FAMILIES;

export type Backdrop = 'dots' | 'stars' | 'grid' | 'none';

/** How much furniture a shot tolerates; `none` means picture only. */
export type ChromeLevel = 'full' | 'minimal' | 'none';

/** A word the line names, and when the picture answers it. */
export type Beat = {
  target: string;
  atSeconds: number;
  frame: number;
  motion?: string;
};

export type Chapter = {
  id: string;
  label: string;
  startSeconds: number;
  endSeconds: number;
  startFrame: number;
  endFrame: number;
};

export type ExplainerFilm = {
  id: string;
  title: string;
  subtitle?: string;
  backdrop: Backdrop;
  width: number;
  height: number;
  fps: number;
  accent?: string;
  chrome?: { hud?: boolean; progress?: boolean };
  chapters: Chapter[];
};

export type ExplainerShot = {
  id: string;
  archetype: string;
  family: Family;
  chapterId: string;
  startSeconds: number;
  durationSeconds: number;
  startFrame: number;
  durationFrames: number;
  kicker?: string;
  title?: string;
  sub?: string;
  accent?: string;
  chrome?: ChromeLevel;
  visual?: Visual;
  visualScale?: number;
  repeatIsPoint?: boolean;
  longShotReason?: string;
  heroAtSeconds?: number;
  holdSeconds: number;
  beats: Beat[];
};

export type ExplainerProps = {
  film: ExplainerFilm;
  shots: ExplainerShot[];
  totalSeconds: number;
  voiceoverFile?: string;
};

/** theme.json, typed once for the render layer. */
export const T = theme;

/** `#RRGGBB` + alpha 0..1 -> `#RRGGBBAA`, clamped. theme.mjs's helper without node:fs. */
export const alpha = (hex: string, a: number): string => {
  const byte = Math.round(Math.min(1, Math.max(0, a)) * 255);
  const part = byte.toString(16);
  return `${hex.slice(0, 7)}${byte < 16 ? `0${part}` : part}`;
};

/**
 * The shot on screen at an absolute frame. Stage and Chrome sit outside the
 * Sequences, so they see film time; every shot sees its own time from zero.
 */
export const shotAtFrame = (
  shots: ExplainerShot[],
  frame: number,
): ExplainerShot | null =>
  shots.find(
    (shot) =>
      frame >= shot.startFrame && frame < shot.startFrame + shot.durationFrames,
  ) ?? null;

/** The one accent a shot may use: its own, else the film's, else the token. */
export const accentOf = (shot: ExplainerShot, film: ExplainerFilm): string =>
  shot.accent ?? film.accent ?? T.color.accent;
