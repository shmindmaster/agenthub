/**
 * One renderer per composition family, and the blocks they share.
 *
 * The kit this replaces declared 22 archetypes and composed exactly one of
 * them; every other storyboard fell through to the same slide. Here the family
 * decides the composition, and every family is built to the same four rules:
 * one hero at 45-75% of the frame, one light on it, one thing that keeps moving
 * while the line is spoken, and a hold at the end. Nothing enters without a
 * named motion from motion.mjs and nothing animates its way out — the next
 * shot's entrance is the transition.
 *
 * Every box comes from layout.mjs. A pixel position written here would be a
 * second layout that drifts from the one the gates check.
 */
import type { CSSProperties, FC, ReactNode } from 'react';
import {
  AbsoluteFill,
  Img,
  Interactive,
  OffthreadVideo,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import { VisualBody, isVideoSrc, phase, type Visual } from '../src/Visuals';
import { fitHeadline, layoutFor, textWidth } from './layout.mjs';
import { EASINGS, enter, progress, staggerFrames } from './motion.mjs';
import {
  T,
  accentOf,
  alpha,
  type Beat,
  type ExplainerFilm,
  type ExplainerShot,
} from './types';

export type ShotProps = {
  shot: ExplainerShot;
  film: ExplainerFilm;
  index: number;
};

type Region = {
  x: number;
  y: number;
  w: number;
  h: number;
  align: 'left' | 'center';
  valign?: 'top' | 'center' | 'bottom';
};

type Regions = {
  hero: Region;
  kicker: Region | null;
  title: Region | null;
  sub: Region | null;
  safe: Region;
};

const ROOT: CSSProperties = {
  backgroundColor: 'transparent',
  color: T.color.ink,
  fontFamily: T.type.family,
  overflow: 'hidden',
};

const ShotRoot: FC<{ children: ReactNode }> = ({ children }) => (
  <AbsoluteFill style={ROOT}>{children}</AbsoluteFill>
);

const clamp01 = (value: number) => Math.min(1, Math.max(0, value));

/** layout.mjs is plain JS; its regions are resolved pixels, so this is the one
 * place the result gets a type instead of being re-derived per family. */
const regionsFor = (family: string, film: ExplainerFilm): Regions =>
  layoutFor(family, film) as Regions;

const two = (value: number) => (value < 10 ? `0${value}` : String(value));

/** The frame the hero lands: the shot's own heroAtSeconds, local to its
 * Sequence. Every family sets its first entrance from here so the picture and
 * the light arrive on the same frame. */
const beatAt = (shot: ExplainerShot, fps: number): number =>
  Math.round((shot.heroAtSeconds ?? 0) * fps);

/** The frame an item lands. Falls back to the same curve VisualBody uses, so a
 * shell and its body never disagree about when a beat is due. */
const landAt = (
  item: { at?: number },
  i: number,
  count: number,
  shot: ExplainerShot,
  from: number,
  fps: number,
): number =>
  Math.round((item.at ?? phase(i, count, shot.durationSeconds, from)) * fps);

/** `enter("wipe")` clips left to right. A seam, an upright rule or a bar beside
 * a title needs the same curve on scaleY, so the timing still comes from
 * motion.mjs and only the axis differs. */
const wipeDown = (p: number) => ({
  transform: `scaleY(${p})`,
  transformOrigin: 'top',
});

/**
 * The schema carries no `emphasis` field yet. A storyboard that adds one is
 * still honoured; otherwise the last content word takes the accent so the eye
 * has exactly one place to land.
 */
const emphasisOf = (shot: ExplainerShot): string | undefined =>
  (shot as ExplainerShot & { emphasis?: string }).emphasis;

const accentIndexFor = (words: string[], emphasis?: string | null): number => {
  if (emphasis === null) return -1;
  const clean = (word: string) =>
    word.replace(/[^A-Za-z0-9'’%-]/g, '').toLowerCase();
  if (emphasis) {
    for (let i = words.length - 1; i >= 0; i -= 1) {
      if (clean(words[i]) === clean(emphasis)) return i;
    }
  }
  for (let i = words.length - 1; i >= 0; i -= 1) {
    if (/[A-Za-z0-9]/.test(words[i])) return i;
  }
  return -1;
};

const CAPTIONED_KINDS = [
  'code',
  'flow',
  'layers',
  'sequence',
  'table',
  'timeline',
  'beforeafter',
  'map',
  'checklist',
  'still',
  'broll',
  'screen-in-context',
  'lower-third',
  'chart',
  'svg',
];

/** VisualBody prints `caption` itself for these kinds. A shell that places a
 * caption of its own asks first, so the same words never appear twice. */
const bodyPrintsCaption = (visual: Visual | undefined): boolean =>
  Boolean(visual && CAPTIONED_KINDS.indexOf(visual.kind) >= 0);

const captionOf = (visual: Visual | undefined): string | undefined =>
  visual && 'caption' in visual ? visual.caption : undefined;

type StatSpec = {
  prefix: string;
  suffix: string;
  value: number;
  decimals: number;
  grouped: boolean;
};

/** Split "49%", "$2.4M" or "1,000,000" into the parts a count-up has to keep. */
const parseStat = (raw: string): StatSpec | null => {
  const match = /^([^0-9]*)([0-9][0-9,]*(?:\.[0-9]+)?)(.*)$/.exec(raw.trim());
  if (!match) return null;
  const digits = match[2];
  const parts = digits.split('.');
  const value = Number(
    `${parts[0].split(',').join('')}${parts.length > 1 ? `.${parts[1]}` : ''}`,
  );
  if (!Number.isFinite(value)) return null;
  return {
    prefix: match[1],
    suffix: match[3],
    value,
    decimals: parts.length > 1 ? parts[1].length : 0,
    grouped: digits.indexOf(',') >= 0,
  };
};

const formatStat = (spec: StatSpec, t: number): string => {
  const fixed = (spec.value * t).toFixed(spec.decimals);
  const dot = fixed.indexOf('.');
  const whole = dot >= 0 ? fixed.slice(0, dot) : fixed;
  const fraction = dot >= 0 ? fixed.slice(dot + 1) : '';
  const grouped = spec.grouped
    ? whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
    : whole;
  return `${spec.prefix}${grouped}${fraction ? `.${fraction}` : ''}${spec.suffix}`;
};

/** Fit on the final string, never on the counted-up frame: sizing from "0"
 * would grow the type mid-count and push the halo off centre. */
const numberSize = (value: string, maxWidth: number): number => {
  for (let size = T.type.number; size > 160; size -= 8) {
    if (textWidth(value, size, -0.03) <= maxWidth) return size;
  }
  return 160;
};

const recentBeat = (beats: Beat[], seconds: number): Beat | null => {
  let best: Beat | null = null;
  for (const beat of beats) {
    if (beat.atSeconds <= seconds && (!best || beat.atSeconds >= best.atSeconds)) {
      best = beat;
    }
  }
  return best;
};

/* ---------------------------------------------------------------- blocks -- */

const Box: FC<{ r: Region; style?: CSSProperties; children?: ReactNode }> = ({
  r,
  style,
  children,
}) => (
  <div
    style={{
      position: 'absolute',
      left: r.x,
      top: r.y,
      width: r.w,
      height: r.h,
      display: 'flex',
      flexDirection: 'column',
      justifyContent:
        r.valign === 'center'
          ? 'center'
          : r.valign === 'bottom'
            ? 'flex-end'
            : 'flex-start',
      alignItems: r.align === 'center' ? 'center' : 'flex-start',
      textAlign: r.align,
      ...style,
    }}
  >
    {children}
  </div>
);

/**
 * XL type, one accent word, word by word. The wrap is computed once from the
 * full text and each line is a nowrap row, so a word that has landed can never
 * be pushed to the next line by the words still arriving.
 */
const Headline: FC<{
  text: string;
  accent: string;
  at: number;
  maxWidth: number;
  maxSize?: number;
  minSize?: number;
  maxLines?: number;
  align?: 'left' | 'center';
  accentWord?: string | null;
  lineHeight?: number;
  weight?: number;
}> = ({
  text,
  accent,
  at,
  maxWidth,
  maxSize,
  minSize = 84,
  maxLines = 3,
  align = 'left',
  accentWord,
  lineHeight,
  weight = 800,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const tracking = T.type.tracking.display;
  const fitted = fitHeadline(text, {
    maxWidth: Math.floor(maxWidth * 0.88),
    maxLines,
    maxSize: maxSize ?? T.type.xl,
    minSize,
    tracking,
  });
  const lines = fitted.lines.map((line) => line.split(' ').filter(Boolean));
  const flat = lines.reduce<string[]>((all, line) => all.concat(line), []);
  const lit = accentIndexFor(flat, accentWord);
  if (!flat.length) return null;
  let k = 0;

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: align === 'center' ? 'center' : 'flex-start',
        width: '100%',
      }}
    >
      {lines.map((line, li) => (
        <div
          key={li}
          style={{
            display: 'flex',
            justifyContent: align === 'center' ? 'center' : 'flex-start',
            columnGap: Math.round(fitted.size * 0.26),
            whiteSpace: 'nowrap',
            fontSize: fitted.size,
            fontWeight: weight,
            lineHeight: lineHeight ?? T.type.lineHeight.display,
            letterSpacing: `${tracking}em`,
            color: T.color.ink,
          }}
        >
          {line.map((word) => {
            const wordIndex = k;
            k += 1;
            const p = progress(
              'rise',
              frame,
              fps,
              (at + staggerFrames(wordIndex)) / fps,
            );
            return (
              <span
                key={wordIndex}
                style={{
                  ...enter('rise', p),
                  display: 'inline-block',
                  color: wordIndex === lit ? accent : undefined,
                }}
              >
                {word}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};

const Kicker: FC<{
  text?: string;
  at: number;
  color?: string;
  align?: 'left' | 'center';
}> = ({ text, at, color, align = 'left' }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (!text) return null;
  return (
    <div
      style={{
        ...enter('fade', progress('fade', frame, fps, at / fps)),
        fontSize: T.type.label,
        fontWeight: 700,
        letterSpacing: `${T.type.tracking.label}em`,
        textTransform: 'uppercase',
        color: color ?? T.color.muted,
        textAlign: align,
      }}
    >
      {text}
    </div>
  );
};

const Sub: FC<{
  text?: string;
  at: number;
  size?: number;
  align?: 'left' | 'center';
  maxWidth?: number;
}> = ({ text, at, size = T.type.caption, align = 'left', maxWidth }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (!text) return null;
  return (
    <div
      style={{
        ...enter('rise', progress('rise', frame, fps, at / fps)),
        fontSize: size,
        lineHeight: 1.32,
        fontWeight: 500,
        color: T.color.muted,
        textAlign: align,
        maxWidth,
      }}
    >
      {text}
    </div>
  );
};

const Rule: FC<{
  accent: string;
  at: number;
  width?: number;
  thickness?: number;
}> = ({ accent, at, width = 220, thickness = 2 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        width,
        height: thickness,
        background: accent,
        borderRadius: thickness,
        ...enter('wipe', progress('wipe', frame, fps, at / fps)),
      }}
    />
  );
};

/** A quiet frame for content that is evidence rather than type: one hairline,
 * an inner backlight, no card. */
const HeroFrame: FC<{ accent: string; at: number }> = ({ accent, at }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        borderRadius: T.radius.card,
        border: `1px solid ${alpha(T.color.ink, 0.09)}`,
        boxShadow: `inset 0 1px 0 ${alpha(T.color.ink, 0.06)}, 0 30px 80px rgba(0,0,0,0.35)`,
        background: `linear-gradient(180deg, ${alpha(accent, 0.05)} 0%, transparent 55%)`,
        pointerEvents: 'none',
        ...enter('bloom', progress('bloom', frame, fps, at / fps)),
      }}
    />
  );
};

/* ------------------------------------------------------------- statement -- */

const Statement: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('statement', film);
  const accent = accentOf(shot, film);
  const hero = shot.visual && shot.visual.kind === 'hero' ? shot.visual : null;
  const card =
    shot.visual && shot.visual.kind === 'lower-third' ? shot.visual : null;
  const title = hero ? hero.title : shot.title ?? '';
  const sub = shot.sub ?? (hero ? hero.sub : undefined);
  const at = beatAt(shot, fps);

  return (
    <ShotRoot>
      <Box r={r.hero}>
        <Headline
          text={title}
          accent={accent}
          at={at}
          maxWidth={r.hero.w}
          maxSize={T.type.xl}
          minSize={84}
          maxLines={3}
          align={r.hero.align}
          accentWord={emphasisOf(shot)}
        />
        {sub ? (
          <div style={{ marginTop: 34, maxWidth: Math.round(r.hero.w * 0.66) }}>
            <Sub text={sub} at={at + 14} size={T.type.caption} align={r.hero.align} />
          </div>
        ) : null}
      </Box>
      {hero && hero.kicker ? (
        <div
          style={{
            position: 'absolute',
            left: r.hero.x,
            top: r.hero.y - 62,
          }}
        >
          <Kicker text={hero.kicker} at={Math.max(0, at - 10)} />
        </div>
      ) : null}
      {card ? (
        <div
          style={{
            position: 'absolute',
            left: r.safe.x,
            top: Math.round(film.height * 0.7),
            display: 'flex',
            gap: 20,
          }}
        >
          <div
            style={{
              width: 3,
              background: accent,
              ...wipeDown(progress('wipe', frame, fps, (at + 4) / fps)),
            }}
          />
          <div
            style={{
              ...enter('slide', progress('slide', frame, fps, (at + 4) / fps)),
            }}
          >
            <div style={{ fontSize: T.type.caption, fontWeight: 800 }}>
              {card.name}
            </div>
            {card.title ? (
              <div
                style={{
                  marginTop: 6,
                  fontSize: T.type.label,
                  letterSpacing: '0.06em',
                  color: T.color.muted,
                }}
              >
                {card.title}
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </ShotRoot>
  );
};

/* ---------------------------------------------------------------- number -- */

const NumberShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('number', film);
  const accent = accentOf(shot, film);
  const stat = shot.visual && shot.visual.kind === 'stat' ? shot.visual : null;
  const value = stat ? stat.value : shot.title ?? '';
  const label = stat ? stat.label : shot.sub ?? '';
  const extra = stat ? stat.sub : undefined;
  const at = beatAt(shot, fps);
  const spec = parseStat(value);
  const size = numberSize(value, r.hero.w);
  const counted = spec
    ? formatStat(spec, EASINGS.out(clamp01((frame - at) / 20)))
    : value;
  const entryP = progress(spec ? 'settle' : 'pop', frame, fps, at / fps);
  const ringP = progress('bloom', frame, fps, at / fps);
  // Consecutive number shots breathe out of phase, so a cut never lands on the
  // same point of the cycle twice.
  const breath = 1 + 0.02 * Math.sin(((frame - at) / 30 + index) * Math.PI * 2);

  return (
    <ShotRoot>
      <Box r={r.hero} style={{ position: 'relative' }}>
        <div
          style={{
            position: 'absolute',
            left: '50%',
            top: '50%',
            width: 560,
            height: 560,
            marginLeft: -280,
            marginTop: -280,
            borderRadius: T.radius.pill,
            border: `2px solid ${alpha(accent, 0.32)}`,
            ...enter('bloom', ringP),
            scale: String((0.97 + 0.03 * ringP) * breath),
          }}
        />
        <Interactive.Div
          name={`Number ${shot.id}`}
          style={{
            position: 'relative',
            ...enter(spec ? 'settle' : 'pop', entryP),
            fontSize: size,
            fontWeight: 900,
            lineHeight: 0.9,
            letterSpacing: '-0.03em',
            color: accent,
            fontVariantNumeric: 'tabular-nums',
          }}
        >
          {counted}
        </Interactive.Div>
      </Box>
      {r.sub ? (
        <Box r={r.sub}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, (at + 10) / fps)),
              fontSize: T.type.caption,
              fontWeight: 700,
              color: T.color.ink,
              textAlign: 'center',
            }}
          >
            {label}
          </div>
          {extra ? (
            <div
              style={{
                marginTop: 12,
                maxWidth: Math.round(r.sub.w * 0.8),
                fontSize: 28,
                lineHeight: 1.3,
                color: T.color.muted,
                textAlign: 'center',
              }}
            >
              {extra}
            </div>
          ) : null}
        </Box>
      ) : null}
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={at} align="center" />
        </Box>
      ) : null}
    </ShotRoot>
  );
};

/* -------------------------------------------------------------- contrast -- */

type Side = { title: string; items: { text: string; at?: number }[] };

/** Two states the visual already describes. Split keeps its two sides; a
 * before/after becomes the same left/right pair, because the seam is what makes
 * the frame legible at a glance. */
const sidesOf = (shot: ExplainerShot): { left: Side; right: Side } | null => {
  const v = shot.visual;
  if (!v) return null;
  if (v.kind === 'split') {
    return {
      left: { title: v.left.title, items: v.left.items },
      right: { title: v.right.title, items: v.right.items },
    };
  }
  if (v.kind === 'beforeafter') {
    return {
      left: {
        title: v.before.title,
        items: v.before.items.map((text) => ({ text })),
      },
      right: {
        title: v.after.title,
        items: v.after.items.map((text) => ({ text })),
      },
    };
  }
  return null;
};

const Contrast: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('contrast', film);
  const accent = accentOf(shot, film);
  const at = beatAt(shot, fps);
  const sides = sidesOf(shot);
  if (!sides) return <Statement shot={shot} film={film} index={index} />;

  const visual = shot.visual;
  const from = visual?.revealFrom ?? 0;
  const mid = r.hero.x + Math.round(r.hero.w / 2);
  const colW = Math.round(r.hero.w / 2 - 46);
  const seamP = progress('wipe', frame, fps, (at + 4) / fps);

  const column = (side: Side, lit: boolean, x: number) => (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: r.hero.y,
        width: colW,
        height: r.hero.h,
        opacity: lit ? 1 : 0.55,
        color: lit ? T.color.ink : T.color.muted,
      }}
    >
      {/* The rule sits in its own layer so the lit title keeps the same
          baseline as the dim one; pushing it down would read as a mistake. */}
      {lit ? (
        <div style={{ position: 'absolute', left: 0, top: 0 }}>
          <Rule accent={accent} at={at + 6} width={56} thickness={2} />
        </div>
      ) : null}
      <div
        style={{
          marginTop: 18,
          ...enter(
            'rise',
            progress('rise', frame, fps, (at + (lit ? 6 : 2)) / fps),
          ),
          fontSize: T.type.s,
          fontWeight: 800,
          letterSpacing: '-0.01em',
          color: lit ? T.color.ink : T.color.muted,
        }}
      >
        {side.title}
      </div>
      <div
        style={{
          marginTop: 26,
          display: 'flex',
          flexDirection: 'column',
          gap: 18,
        }}
      >
        {side.items.map((item, i) => {
          const start = landAt(item, i, side.items.length, shot, from, fps);
          return (
            <div
              key={i}
              style={{
                ...enter('rise', progress('rise', frame, fps, start / fps)),
                fontSize: T.type.body,
                lineHeight: 1.3,
                fontWeight: 600,
              }}
            >
              {item.text}
            </div>
          );
        })}
      </div>
    </div>
  );

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={at} />
        </Box>
      ) : null}
      {r.title ? (
        <Box r={r.title}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, at / fps)),
              fontSize: Math.floor(Math.min(T.type.m, r.title.h / 2.15)),
              fontWeight: 800,
              lineHeight: 1.02,
            }}
          >
            {shot.title ?? ''}
          </div>
        </Box>
      ) : null}
      <div
        style={{
          position: 'absolute',
          left: mid,
          top: r.hero.y - 10,
          width: 1,
          height: r.hero.h + 20,
          background: alpha(T.color.ink, 0.25),
          ...wipeDown(seamP),
        }}
      />
      {column(sides.left, false, r.hero.x)}
      {column(sides.right, true, mid + 46)}
    </ShotRoot>
  );
};

/* ------------------------------------------------------------- mechanism -- */

const Mechanism: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('mechanism', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const at = beatAt(shot, fps);
  if (!visual) return <Statement shot={shot} film={film} index={index} />;

  const zoom = Math.min(1.8, Math.max(1, (shot.visualScale ?? 1) * 1.15));
  const beat = recentBeat(shot.beats, Math.max(0, frame) / fps);
  const ringP = beat
    ? clamp01((frame - Math.round(beat.atSeconds * fps)) / 12)
    : 0;
  const intro = progress('settle', frame, fps, at / fps);
  const caption = captionOf(visual);

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={at} />
        </Box>
      ) : null}
      {r.title ? (
        <Box r={r.title}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, at / fps)),
              fontSize: Math.floor(Math.min(T.type.m, r.title.h / 2.15)),
              fontWeight: 800,
              lineHeight: 1.02,
            }}
          >
            {shot.title ?? ''}
          </div>
        </Box>
      ) : null}
      <div
        style={{
          position: 'absolute',
          left: r.hero.x + 4,
          top: r.hero.y + 4,
          width: r.hero.w - 8,
          height: r.hero.h - 8,
          borderRadius: 22,
          border: `2px solid ${alpha(accent, 0.55)}`,
          opacity: intro * (0.9 - 0.5 * ringP),
          scale: String(1.014 - 0.014 * ringP),
          pointerEvents: 'none',
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: r.hero.y,
          width: r.hero.w / zoom,
          height: r.hero.h / zoom,
          zoom,
        }}
      >
        <VisualBody
          visual={visual}
          accent={accent}
          durationSeconds={shot.durationSeconds}
        />
      </div>
      {caption && !bodyPrintsCaption(visual) ? (
        <div
          style={{
            position: 'absolute',
            left: r.hero.x,
            top: r.hero.y + r.hero.h + 10,
            width: r.hero.w,
            fontSize: 28,
            lineHeight: 1.2,
            color: T.color.muted,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            ...enter('fade', progress('fade', frame, fps, (at + 24) / fps)),
          }}
        >
          {caption}
        </div>
      ) : null}
    </ShotRoot>
  );
};

/* ---------------------------------------------------------------- layers -- */

const LayersShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('layers', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const at = beatAt(shot, fps);
  if (!visual || visual.kind !== 'layers') {
    return <Statement shot={shot} film={film} index={index} />;
  }

  const zoom = 1.5;
  const from = visual.revealFrom ?? 0;
  const layers = visual.layers;
  let active = 0;
  layers.forEach((layer, i) => {
    const start = landAt(layer, i, layers.length, shot, from, fps);
    if (Math.round(frame) >= start) active = i;
  });
  const bandY = layers.length
    ? ((active + 0.5) / layers.length) * 100
    : 50;

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={at} />
        </Box>
      ) : null}
      {r.title ? (
        <Box r={r.title}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, at / fps)),
              fontSize: Math.floor(Math.min(T.type.m, r.title.h / 2.15)),
              fontWeight: 800,
              lineHeight: 1.02,
            }}
          >
            {shot.title ?? ''}
          </div>
        </Box>
      ) : null}
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: r.hero.y,
          width: r.hero.w,
          height: r.hero.h,
        }}
      >
        {/* The pool of light follows the band whose `at` has passed most
            recently. Band heights are even, so the index places it without
            measuring the stack. */}
        <div
          style={{
            position: 'absolute',
            inset: 0,
            background: `radial-gradient(44% 26% at 46% ${bandY.toFixed(1)}%, ${alpha(accent, 0.1)} 0%, transparent 72%)`,
            pointerEvents: 'none',
          }}
        />
        <div
          style={{
            position: 'absolute',
            inset: 0,
            background:
              'linear-gradient(to bottom, rgba(0,0,0,0) 58%, rgba(0,0,0,0.55) 100%)',
            pointerEvents: 'none',
          }}
        />
        <div
          style={{
            position: 'absolute',
            left: 0,
            top: 0,
            width: r.hero.w / zoom,
            height: r.hero.h / zoom,
            zoom,
            filter: 'drop-shadow(0 16px 22px rgba(0,0,0,0.45))',
          }}
        >
          <VisualBody
            visual={visual}
            accent={accent}
            durationSeconds={shot.durationSeconds}
          />
        </div>
      </div>
    </ShotRoot>
  );
};

/* -------------------------------------------------------------- timeline -- */

const TimelineShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('timeline', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const at = beatAt(shot, fps);
  if (!visual || visual.kind !== 'timeline') {
    return <Statement shot={shot} film={film} index={index} />;
  }

  const zoom = 1.35;
  const sweep = progress('push', frame, fps, 0, shot.durationSeconds);
  // Above the event column: the primitive's spine runs down, so a playhead drawn
  // left-to-right across the body would cut through the labels.
  const railY = r.hero.y - 22;

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={at} />
        </Box>
      ) : null}
      {r.title ? (
        <Box r={r.title}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, at / fps)),
              fontSize: Math.floor(Math.min(T.type.m, r.title.h / 2.15)),
              fontWeight: 800,
              lineHeight: 1.02,
            }}
          >
            {shot.title ?? ''}
          </div>
        </Box>
      ) : null}
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: railY,
          width: r.hero.w,
          height: 2,
          background: alpha(T.color.ink, 0.14),
          ...enter('wipe', progress('wipe', frame, fps, at / fps)),
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: Math.round(r.hero.x + r.hero.w * sweep) - 1,
          top: railY - 5,
          width: 2,
          height: 12,
          background: accent,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: Math.round(r.hero.x + r.hero.w * sweep) - 5,
          top: railY - 4,
          width: 10,
          height: 10,
          borderRadius: T.radius.pill,
          background: accent,
          boxShadow: `0 0 18px ${alpha(accent, 0.55)}`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: r.hero.y,
          width: r.hero.w / zoom,
          height: r.hero.h / zoom,
          zoom,
        }}
      >
        <VisualBody
          visual={visual}
          accent={accent}
          durationSeconds={shot.durationSeconds}
        />
      </div>
    </ShotRoot>
  );
};

/* -------------------------------------------------------------- evidence -- */

const Evidence: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('evidence', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const at = beatAt(shot, fps);
  if (!visual) return <Statement shot={shot} film={film} index={index} />;

  const claim =
    visual.kind === 'proof' || visual.kind === 'sidecar'
      ? visual.claim
      : shot.title ?? '';
  const tracking = T.type.tracking.display;
  // Fit here as well as inside Headline so the connector can start at the real
  // baseline. Same input, same computation, same lines — nothing is measured.
  const fitted = fitHeadline(claim, {
    maxWidth: r.title ? r.title.w : r.hero.w,
    maxLines: 2,
    maxSize: 64,
    minSize: 52,
    tracking,
  });
  const claimBottom =
    (r.title ? r.title.y : r.hero.y - 60) +
    Math.round(fitted.lines.length * fitted.size * T.type.lineHeight.display);
  const connectorTop = claimBottom + 6;
  const connectorLen = Math.max(12, r.hero.y - 10 - connectorTop);
  const caption = captionOf(visual);
  const zoom = Math.min(1.3, Math.max(1, shot.visualScale ?? 1));

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={at} />
        </Box>
      ) : null}
      {r.title ? (
        <Box r={r.title}>
          <Headline
            text={claim}
            accent={accent}
            at={at}
            maxWidth={r.title.w}
            maxSize={64}
            minSize={52}
            maxLines={2}
            accentWord={emphasisOf(shot)}
          />
        </Box>
      ) : null}
      <svg
        width={2}
        height={connectorLen}
        style={{
          position: 'absolute',
          left: (r.title ? r.title.x : r.hero.x) + 1,
          top: connectorTop,
          overflow: 'visible',
        }}
      >
        <line
          x1={1}
          y1={0}
          x2={1}
          y2={connectorLen}
          stroke={alpha(accent, 0.55)}
          strokeWidth={1}
          pathLength={1}
          strokeDasharray={1}
          {...enter('draw', progress('draw', frame, fps, (at + 6) / fps))}
        />
      </svg>
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: r.hero.y,
          width: r.hero.w / zoom,
          height: r.hero.h / zoom,
          zoom,
        }}
      >
        <HeroFrame accent={accent} at={at} />
        <VisualBody
          visual={visual}
          accent={accent}
          durationSeconds={shot.durationSeconds}
        />
      </div>
      {caption && !bodyPrintsCaption(visual) ? (
        <div
          style={{
            position: 'absolute',
            left: r.hero.x,
            top: Math.round(film.height * 0.8),
            width: r.hero.w,
            fontSize: T.type.label,
            letterSpacing: '0.04em',
            color: T.color.muted,
            ...enter('fade', progress('fade', frame, fps, (at + 24) / fps)),
          }}
        >
          {caption}
        </div>
      ) : null}
    </ShotRoot>
  );
};

/* ----------------------------------------------------------------- quote -- */

const QuoteShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('quote', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual && shot.visual.kind === 'quote' ? shot.visual : null;
  const text = visual ? visual.text : shot.title ?? '';
  const who = visual ? visual.attribution : shot.sub;
  const at = beatAt(shot, fps);

  return (
    <ShotRoot>
      <div
        style={{
          position: 'absolute',
          left: r.hero.x - 22,
          top: r.hero.y - 96 - (index % 2) * 8,
          fontFamily: 'Georgia, "Times New Roman", serif',
          fontSize: 300,
          lineHeight: 1,
          color: alpha(accent, 0.12),
          opacity: progress('settle', frame, fps, (at + 2) / fps),
          pointerEvents: 'none',
        }}
      >
        {'\u201C'}
      </div>
      <Box r={r.hero}>
        <Headline
          text={text}
          accent={accent}
          at={at}
          maxWidth={r.hero.w}
          maxSize={88}
          minSize={64}
          maxLines={4}
          align={r.hero.align}
          accentWord={null}
          lineHeight={1.06}
          weight={700}
        />
        {who ? (
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, (at + 20) / fps)),
              marginTop: 40,
              fontSize: 28,
              letterSpacing: '0.04em',
              color: T.color.muted,
            }}
          >
            {who}
          </div>
        ) : null}
      </Box>
    </ShotRoot>
  );
};

/* ------------------------------------------------------------- checklist -- */

const Checklist: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('checklist', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const at = beatAt(shot, fps);
  if (!visual || visual.kind !== 'checklist') {
    return <Statement shot={shot} film={film} index={index} />;
  }

  const from = visual.revealFrom ?? 0;
  const items = visual.items;
  const rowH = 82;
  const visible = 5;
  const lift = items
    .slice(visible)
    .reduce(
      (sum, item, i) =>
        sum +
        progress(
          'slide',
          frame,
          fps,
          landAt(item, visible + i, items.length, shot, from, fps) / fps,
        ),
      0,
    ) * rowH;

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={at} />
        </Box>
      ) : null}
      {r.title ? (
        <Box r={r.title}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, at / fps)),
              fontSize: Math.floor(Math.min(64, r.title.h / 2.15)),
              fontWeight: 800,
              lineHeight: 1.02,
            }}
          >
            {shot.title ?? ''}
          </div>
        </Box>
      ) : null}
      {/* Rail: one dot per item, filled as each is spoken. It stays put while
          the list scrolls, so it reads as progress rather than as an index. */}
      {items.map((item, i) => {
        const start = landAt(item, i, items.length, shot, from, fps);
        const done = frame >= start;
        // Dots sit on the row centres while the whole list fits; past five items
        // they compress into the window the list scrolls through, so the rail
        // still reads as progress rather than as a second, wrong index.
        const step =
          items.length <= visible ? rowH : (rowH * visible) / items.length;
        const top = r.hero.y + i * step + Math.min(step, rowH) / 2 - 3;
        return (
          <div
            key={`rail-${i}`}
            style={{
              position: 'absolute',
              left: r.hero.x - 46,
              top: Math.round(top),
              width: 7,
              height: 7,
              borderRadius: T.radius.pill,
              background: done ? accent : alpha(T.color.ink, 0.18),
              opacity: done ? 1 : 0.8,
            }}
          />
        );
      })}
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: r.hero.y,
          width: r.hero.w,
          height: rowH * visible,
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            transform: `translateY(${-Math.round(lift)}px)`,
          }}
        >
          {items.map((item, i) => {
            const start = landAt(item, i, items.length, shot, from, fps);
            const check = clamp01((frame - start) / 10);
            return (
              <Interactive.Div
                key={i}
                name={`Item ${i + 1}`}
                style={{
                  height: rowH,
                  display: 'flex',
                  alignItems: 'center',
                  gap: 22,
                  ...enter('rise', progress('rise', frame, fps, start / fps)),
                }}
              >
                <div
                  style={{
                    width: 26,
                    height: 26,
                    borderRadius: 7,
                    border: `1px solid ${alpha(check > 0 ? accent : T.color.ink, check > 0 ? 0.7 : 0.3)}`,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                  }}
                >
                  <svg width={18} height={18} viewBox="0 0 18 18">
                    <polyline
                      points="3,9 7,13 15,4"
                      fill="none"
                      stroke={accent}
                      strokeWidth={2.5}
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      pathLength={1}
                      strokeDasharray={1}
                      strokeDashoffset={1 - check}
                    />
                  </svg>
                </div>
                <div
                  style={{
                    fontSize: T.type.caption,
                    lineHeight: 1.25,
                    fontWeight: 600,
                  }}
                >
                  {item.text}
                </div>
              </Interactive.Div>
            );
          })}
        </div>
      </div>
    </ShotRoot>
  );
};

/* ----------------------------------------------------------------- media -- */

const MediaShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('media', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const src = visual && 'src' in visual ? visual.src : null;
  if (!src) return <Statement shot={shot} film={film} index={index} />;

  const at = beatAt(shot, fps);
  const push = 1 + 0.04 * progress('push', frame, fps, 0, shot.durationSeconds);
  const slideIn = (offset: number) =>
    enter('slide', progress('slide', frame, fps, (at + offset) / fps));

  return (
    <ShotRoot>
      <AbsoluteFill style={{ overflow: 'hidden' }}>
        {isVideoSrc(src) ? (
          <OffthreadVideo
            src={staticFile(src)}
            muted
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              scale: String(push),
            }}
          />
        ) : (
          <Img
            src={staticFile(src)}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              scale: String(push),
            }}
          />
        )}
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          background:
            'linear-gradient(to top, rgba(0,0,0,0.86) 0%, rgba(0,0,0,0.55) 26%, rgba(0,0,0,0.12) 55%, rgba(0,0,0,0) 74%)',
          pointerEvents: 'none',
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: r.title ? r.title.x - 26 : r.safe.x,
          top: (r.title ? r.title.y : r.safe.y) + 4,
          width: 2,
          height: 52,
          background: accent,
          ...wipeDown(progress('wipe', frame, fps, (at + 4) / fps)),
        }}
      />
      {r.title ? (
        <Box r={r.title}>
          <div
            style={{
              ...slideIn(0),
              fontSize: 56,
              fontWeight: 800,
              lineHeight: 1.05,
              letterSpacing: '-0.01em',
              color: T.color.ink,
            }}
          >
            {shot.title ?? ''}
          </div>
        </Box>
      ) : null}
      {r.sub ? (
        <Box r={r.sub}>
          <div
            style={{
              ...slideIn(6),
              fontSize: 30,
              lineHeight: 1.3,
              color: T.color.inkSoft,
            }}
          >
            {shot.sub ?? ''}
          </div>
        </Box>
      ) : null}
    </ShotRoot>
  );
};

/* ----------------------------------------------------------------- sting -- */

const StingShot: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('sting', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const at = beatAt(shot, fps);
  const p = progress('pop', frame, fps, at / fps);

  if (visual && visual.kind === 'lottie') {
    return (
      <ShotRoot>
        <Box
          r={r.hero}
          style={{
            alignItems: 'center',
            ...enter('settle', progress('settle', frame, fps, at / fps)),
          }}
        >
          <VisualBody
            visual={visual}
            accent={accent}
            durationSeconds={shot.durationSeconds}
          />
        </Box>
      </ShotRoot>
    );
  }

  const mark = visual && visual.kind === 'hero' ? visual.title : shot.title ?? '';
  return (
    <ShotRoot>
      <Box r={r.hero}>
        <div
          style={{
            ...enter('pop', p),
            fontSize: T.type.l,
            fontWeight: 900,
            letterSpacing: '-0.02em',
            color: T.color.ink,
            textAlign: 'center',
          }}
        >
          {mark}
        </div>
        <div style={{ marginTop: 26 }}>
          <Rule accent={accent} at={at + 8} width={72} thickness={2} />
        </div>
      </Box>
    </ShotRoot>
  );
};

/* --------------------------------------------------------------- chapter -- */

const ChapterShot: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('chapter', film);
  const accent = accentOf(shot, film);
  const visual =
    shot.visual && shot.visual.kind === 'chapter' ? shot.visual : null;
  const at = beatAt(shot, fps);
  const chapterIndex = film.chapters.findIndex((c) => c.id === shot.chapterId);
  const number = two(chapterIndex >= 0 ? chapterIndex + 1 : 1);
  const label = visual
    ? visual.title
    : shot.title
      ? shot.title
      : chapterIndex >= 0
        ? film.chapters[chapterIndex].label
        : '';
  const kicker = visual && visual.kicker ? visual.kicker : `Chapter ${number}`;

  return (
    <ShotRoot>
      <div
        style={{
          position: 'absolute',
          left: r.hero.x - 8,
          top: r.hero.y - 92,
          fontSize: 240,
          fontWeight: 900,
          lineHeight: 0.8,
          letterSpacing: '-0.05em',
          color: alpha(accent, 0.18),
          opacity: progress('settle', frame, fps, at / fps),
          pointerEvents: 'none',
        }}
      >
        {number}
      </div>
      <Box r={r.hero}>
        <Kicker text={kicker} at={at + 2} color={accent} />
        <div
          style={{
            marginTop: 22,
            ...enter('rise', progress('rise', frame, fps, (at + 4) / fps)),
            fontSize: 96,
            fontWeight: 800,
            lineHeight: 1.02,
            letterSpacing: '-0.02em',
            color: T.color.ink,
          }}
        >
          {label}
        </div>
        <div style={{ marginTop: 30 }}>
          <Rule accent={accent} at={at + 8} width={260} thickness={2} />
        </div>
      </Box>
    </ShotRoot>
  );
};

/* ------------------------------------------------------------------- end -- */

const EndShot: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('end', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual && shot.visual.kind === 'cta' ? shot.visual : null;
  const title = visual ? visual.title : shot.title ?? '';
  const next = visual ? visual.next : shot.sub ?? '';
  const kicker = visual && visual.kicker ? visual.kicker : shot.kicker;
  const at = beatAt(shot, fps);
  const tracking = T.type.tracking.display;
  const fitted = fitHeadline(title, {
    maxWidth: r.hero.w,
    maxLines: 2,
    maxSize: T.type.l,
    minSize: 84,
    tracking,
  });

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Rule accent={accent} at={at} width={64} thickness={2} />
          {kicker ? (
            <div style={{ marginTop: 14 }}>
              <Kicker text={kicker} at={at + 4} align="center" />
            </div>
          ) : null}
        </Box>
      ) : null}
      <Box r={r.hero}>
        <div
          style={{
            ...enter('rise', progress('rise', frame, fps, at / fps)),
            fontSize: fitted.size,
            fontWeight: 900,
            lineHeight: 1,
            letterSpacing: `${tracking}em`,
            textAlign: 'center',
            color: T.color.ink,
          }}
        >
          {title}
        </div>
      </Box>
      {r.sub ? (
        <Box r={r.sub}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, (at + 10) / fps)),
              fontSize: 36,
              lineHeight: 1.3,
              color: T.color.muted,
              textAlign: 'center',
            }}
          >
            {next}
          </div>
        </Box>
      ) : null}
    </ShotRoot>
  );
};

/* ---------------------------------------------------------------- export -- */

export const SHOT_RENDERERS: Record<string, FC<ShotProps>> = {
  statement: Statement,
  number: NumberShot,
  contrast: Contrast,
  mechanism: Mechanism,
  layers: LayersShot,
  timeline: TimelineShot,
  evidence: Evidence,
  quote: QuoteShot,
  checklist: Checklist,
  media: MediaShot,
  sting: StingShot,
  chapter: ChapterShot,
  end: EndShot,
};

/**
 * The one entry point a Sequence uses. The schema only promises that `family` is
 * a non-empty string, so a storyboard written against an older grammar can name
 * a family this build has no component for; it renders as `statement` rather
 * than as an empty frame, which is the failure a viewer would notice last.
 */
export const Shot: FC<ShotProps> = ({ shot, film, index }) => {
  const Renderer = SHOT_RENDERERS[shot.family] ?? SHOT_RENDERERS.statement;
  return <Renderer shot={shot} film={film} index={index} />;
};
