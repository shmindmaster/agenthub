// Write a synthetic product-screencast job workspace for the screen-stage proof film (one screen beat, S01, 6.0 s).
// Usage: node make-proof-job.mjs <outDir> [--viewer-facing]
// No audio, no TTS: word times are hand-supplied. The clip capture/clips/S01.mp4 is written later by the stage recorder.
// Default intent is "draft": the ledger has no sign-in, so write-scenario-proof.mjs cannot show a signed-out refusal and no
// scenario proof exists. --viewer-facing omits the intent (the pipeline then demands evidence/demo-scenario-proof.json).
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

const args = process.argv.slice(2);
const outDir = args.find((a) => !a.startsWith('--'));
if (!outDir) { console.error('usage: node make-proof-job.mjs <outDir> [--viewer-facing]'); process.exit(2); }
const root = resolve(outDir);
const put = (rel, data) => { const p = join(root, rel); mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof data === 'string' ? data : JSON.stringify(data, null, 2) + '\n'); };

const DURATION = 7.2;
// [word, start, end] seconds. Content-word starts are the click moments: amounts 1.0, Format 2.0, Number 3.1, Currency 4.2; Applied 4.6.
const WORDS = [
  ['Select', 0.45, 0.80], ['the', 0.80, 0.95], ['amounts,', 1.00, 1.50], ['open', 1.62, 1.90], ['Format,', 2.00, 2.50], ['choose', 2.62, 3.00],
  ['Number,', 3.10, 3.55], ['pick', 3.65, 4.05], ['Currency.', 4.20, 4.58], ['Applied', 4.60, 4.95], ['to', 4.95, 5.05], ['all', 5.05, 5.22],
  ['seven', 5.22, 5.50], ['cells', 5.50, 5.78], ['at', 5.78, 5.86], ['once.', 5.86, 5.98],
].map(([w, start, end]) => ({ w, start, end }));
const TEXT = WORDS.map((x) => x.w).join(' ');

put('job.json', {
  kind: 'product-screencast',
  title: 'Tally ledger: format a column as currency',
  repositoryWritePolicy: 'read-only',
  deliveryProfile: 'youtube-16x9',
  ...(args.includes('--viewer-facing') ? {} : { intent: 'draft' }),
  screenStage: {},
});

put('story/narration-timeline.json', { durationSeconds: DURATION, segments: [{ id: 'S01', scene: 'S01', text: TEXT, startSeconds: 0, durationSeconds: DURATION, words: WORDS }] });
put('voice/asr/S01.json', { words: WORDS });   // where build-cue-sheet reads per-segment word times (seconds into the line)

put('story/storyboard.json', {
  title: 'Tally ledger: currency in four clicks', scenarioId: 'ledger-currency', cta: 'Try the Format menu on your own ledger',
  beats: [{ id: 'S01', visualMode: 'screen', durationSeconds: DURATION, title: 'Select, Format, Number, Currency', resultHoldSeconds: 1.4 }],
});

put('story/cue-plan.json', {
  voiceFirst: true,
  beats: {
    S01: {
      actions: [
        { label: 'Select amounts', keywords: ['amounts'] },
        { label: 'Open format', keywords: ['format'] },
        { label: 'Open number', keywords: ['number'] },
        { label: 'Apply currency', keywords: ['currency'] },
      ],
      result: { label: 'Currency format applied', keywords: ['applied'] },
      expectedState: 'The Amount cells read as dollars and a toast confirms the format',
      pointer: { maxReversals: 1, reason: 'the flow goes from the data column to the menu bar, then down the menu: one turn' },
    },
  },
});

put('capture/manifest.json', { clips: [{ id: 'S01', file: 'clips/S01.mp4', segments: ['S01'] }] });

put('capture/scenes.mjs', `// Synthetic ledger fixture. Serve it first: node serve.mjs 4811 (or set FIXTURE_URL).
// Click pacing: pointer travel 400 ms + settle 250 ms + click 60 ms + hold; holds are chosen so the presses land about
// 1.0 s apart (hold 290/390/390 ms), then the toast is observed and the end is held. The stage recorder re-times the film.
export const options = {
  baseUrl: process.env.FIXTURE_URL || 'http://127.0.0.1:4811',
  viewport: { width: 1280, height: 720 },
  provenance: { sourceRevision: 'fixture-1' },
};
export const order = ['S01'];
export const identity = async (page) => {
  const ledger = await page.evaluate(() => window.__ledger);
  return { persona: ledger.persona, servedRevision: ledger.revision };
};
export const scenes = {
  async S01(h) {
    await h.go('/', { readySelector: '[data-testid="col-amount"]', settle: 800 });
    await h.click(h.page.getByTestId('col-amount'), { label: 'Select amounts', ms: 400, settle: 250, hold: 290 });
    await h.click(h.page.getByTestId('menu-format'), { label: 'Open format', ms: 400, settle: 250, hold: 390 });
    await h.click(h.page.getByTestId('item-number'), { label: 'Open number', ms: 400, settle: 250, hold: 390 });
    await h.click(h.page.getByTestId('sub-currency'), { label: 'Apply currency', ms: 400, settle: 250, hold: 100 });
    await h.expect(h.page.getByTestId('toast'), 'Currency format applied', { text: 'Currency format applied to 7 cells', hold: 300 });
    await h.hold(1300);
  },
};
`);

put('capture/scenario.mjs', `// Scenario contract for write-scenario-proof.mjs. The ledger fixture is open to everyone (no sign-in), so the proof's
// "signed-out browser is refused" check cannot pass; this file documents the contract shape and the job stays intent "draft".
export const scenario = {
  scenarioId: 'ledger-currency', synthetic: true, persona: 'Household ledger owner, synthetic', personaId: 'demo-ledger-owner',
  problem: 'Amounts in a ledger are plain numbers and hard to read as money.',
  start: '/',
  hero: { segmentId: 'S01', beforeState: 'Amounts are plain numbers', action: 'Select the Amount column and apply Currency from Format > Number', visibleResult: 'Amounts read as dollars and a toast confirms it' },
  outcome: { statement: 'The Amount column is formatted as currency', evidence: 'Cells read $300.00 and the toast says Currency format applied to 7 cells' },
  continuity: { entities: [{ type: 'ledger', id: 'household-nov' }] },
};
export const guarded = (page) => page.getByTestId('col-amount');
export const signIn = async () => {};
export const prove = async ({ page, act, check }) => {
  await act('Select amounts', () => page.getByTestId('col-amount').click());
  await act('Open format', () => page.getByTestId('menu-format').click());
  await act('Open number', () => page.getByTestId('item-number').click());
  await act('Apply currency', () => page.getByTestId('sub-currency').click());
  await check('the currency toast', page.getByTestId('toast').filter({ hasText: 'Currency format applied to 7 cells' }));
};
`);

console.log(JSON.stringify({ ok: true, root, intent: args.includes('--viewer-facing') ? 'viewer-facing' : 'draft', segment: 'S01', durationSeconds: DURATION, words: WORDS.length }));
