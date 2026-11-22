// A six-shot explainer fixture: one shot per composition family that carries a
// different layout, two chapters, one word-anchored beat, and a hold on every
// shot. Every builder and gate test starts from this film and mutates one thing.
import { buildExplainer } from '../../../kit/explainer/build-explainer.mjs';

const word = (text, start) => ({ text, start_seconds: start, boundary_type: 'SpeechSynthesisBoundaryType.Word' });

export const cueSheet = {
  totalSeconds: 26,
  cues: [
    { id: 'a', start: 0.2, end: 4.0, gapAfter: 0.5, text: 'One revision lands overnight.' },
    { id: 'b', start: 5.0, end: 8.5, gapAfter: 0.5, text: 'Three commitments break at once.' },
    { id: 'c', start: 9.5, end: 13.0, gapAfter: 0.5, text: 'The plan changed under them.' },
    { id: 'd', start: 14.0, end: 17.5, gapAfter: 0.5, text: 'Before it was a guess. Now it has an owner.' },
    { id: 'e', start: 18.5, end: 22.0, gapAfter: 0.5, text: 'The lead checks three things first.' },
    { id: 'f', start: 23.0, end: 26.0, gapAfter: 0, text: 'Eleven minutes saved before stand-up.' },
  ],
};

export const receipts = {
  a: [word('One', 0.05), word('revision', 0.3), word('lands', 0.7), word('overnight', 1.0)],
  b: [word('Three', 0.05), word('commitments', 0.3), word('break', 0.9), word('at', 1.1), word('once', 1.2)],
  c: [word('The', 0.05), word('plan', 0.2), word('changed', 0.5), word('under', 0.9), word('them', 1.0)],
  d: [word('Before', 0.05), word('it', 0.4), word('was', 0.5), word('a', 0.6), word('guess', 0.7)],
  e: [word('The', 0.05), word('lead', 0.2), word('checks', 0.5), word('three', 0.8), word('things', 1.0)],
  f: [word('Eleven', 0.6), word('minutes', 1.0), word('saved', 1.5), word('before', 1.9), word('stand-up', 2.2)],
};

export const plan = {
  film: { id: 'revision-drift', title: 'One revision, three broken commitments', backdrop: 'dots', accent: '#F5C518' },
  chapters: [
    { id: 'c1', label: 'The break', shots: ['a', 'b', 'c'] },
    { id: 'c2', label: 'The repair', shots: ['d', 'e', 'f'] },
  ],
  shots: [
    {
      id: 'a',
      archetype: 'cold-open',
      kicker: 'REVISION',
      title: 'One revision lands overnight.',
      sub: 'Everything promised is now a question.',
    },
    {
      id: 'b',
      archetype: 'diagram-build',
      kicker: 'THE BREAK',
      title: 'Three commitments break at once.',
      visual: {
        kind: 'flow',
        caption: 'revision → plan → commitments',
        nodes: [
          { label: 'Revision', at: 0.8 },
          { label: 'Plan', at: 1.9 },
          { label: 'Commitments', at: 2.9, mark: 'risk' },
        ],
      },
    },
    {
      id: 'c',
      archetype: 'evidence-proof',
      kicker: 'EVIDENCE',
      title: 'The plan changed under them.',
      visual: { kind: 'proof', kicker: 'SOURCE', claim: 'Two lines moved.', evidence: 'Revision 14 changed the handoff date.' },
    },
    {
      id: 'd',
      archetype: 'before-after',
      kicker: 'BEFORE / AFTER',
      title: 'Before it was a guess. Now it has an owner.',
      visual: {
        kind: 'split',
        left: { title: 'Before', mark: 'muted', items: [{ text: 'no owner', at: 0.9 }, { text: 'no date', at: 1.5 }] },
        right: { title: 'After', mark: 'good', items: [{ text: 'one owner', at: 2.2 }, { text: 'one date', at: 2.8 }] },
      },
    },
    {
      id: 'e',
      archetype: 'checklist-build',
      kicker: 'THE CHECK',
      title: 'The lead checks three things first.',
      visual: {
        kind: 'checklist',
        items: [{ text: 'which commitments moved', at: 0.7 }, { text: 'who owns each one', at: 1.7 }, { text: 'what ships late', at: 2.7 }],
      },
    },
    {
      id: 'f',
      archetype: 'kinetic-number',
      kicker: 'PAYOFF',
      title: 'Eleven minutes saved before stand-up.',
      visual: { kind: 'stat', value: '11', label: 'minutes saved', sub: 'before stand-up', at: '@Eleven' },
    },
  ],
};

export const build = (overrides = {}) =>
  buildExplainer({
    cueSheet,
    receipts,
    plan,
    fps: 30,
    width: 1600,
    height: 1000,
    ...overrides,
  });

/** A deep clone so a test can mutate one shot without leaking into the next. */
export const clone = (value) => JSON.parse(JSON.stringify(value));
