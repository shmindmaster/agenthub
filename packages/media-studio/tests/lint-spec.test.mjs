import test from 'node:test';
import assert from 'node:assert/strict';
import { join, resolve } from 'node:path';
import { lintSpec } from '../kit/marketing/lib/lint.mjs';

// Host-native absolute paths keep the expected messages identical on Windows and POSIX.
const SPEC_DIR = resolve('synthetic');
const GHOST_JOB = join(SPEC_DIR, 'ghost');

const io = (receiptExists) => ({
  specDir: SPEC_DIR,
  exists: () => receiptExists,
  readJson: () => ({ clips: { C1: { valid: true, clipSeconds: 10, events: { clicks: 0 } } } }),
});

const validSpec = () => ({
  voice: {
    provider: 'elevenlabs',
    name: 'Narrator',
    model: 'eleven_flash_v2_5',
    settings: { apply_text_normalization: 'on' },
    pronunciationDictionaries: [{ id: 'product', version: '1' }],
  },
  labels: 'SYNTHETIC · NO PHI',
  cta: { text: 'Explore the dashboard', url: 'https://example.com/demo', claim: 'c1' },
  claims: [{
    id: 'c1',
    text: 'The dashboard tracks open cases',
    phrases: ['tracks open cases'],
    evidence: 'approved:product behavior',
  }],
  cuts: [{
    id: 'main',
    ratios: ['16x9'],
    targetSeconds: 3,
    beats: [{
      id: 'B1',
      kind: 'ui',
      narration: 'The dashboard tracks open cases.',
      claims: ['c1'],
      ui: { sourceJob: join(SPEC_DIR, 'film'), clipId: 'C1' },
    }],
  }],
});

test('lintSpec returns the exact quiet result for a valid synthetic spec', () => {
  assert.deepEqual(
    lintSpec(validSpec(), { forbiddenNames: [], urls: { demo: 'https://example.com/demo' } }, { io: io(true) }),
    {
      ok: true,
      errors: [],
      warnings: [],
      estimates: [{ cut: 'main', estimateSeconds: 2.7, targetSeconds: 3 }],
    },
  );
});

test('lintSpec preserves exact ordered findings and estimates for an invalid synthetic spec', () => {
  const spec = {
    voice: { ownerVoice: true, name: 'Sarosh', provider: 'openai' },
    music: { provider: 'elevenlabs', lengthSeconds: 1 },
    labels: 'REAL PRODUCT',
    cta: { text: 'Guarantee this, unlike CentralReach.', url: 'not-a-url', claim: 'absent' },
    claims: [
      { id: 'c1', text: 'One case remains', phrases: ['One case remains'], evidence: 'vibes-only' },
      { id: 'c1', text: 'Two cases remain', phrases: ['Two cases remain'], evidence: 'approved:x' },
    ],
    cuts: [{
      id: 'main',
      ratios: ['16x9'],
      targetSeconds: 4,
      beats: [{
        id: 'B1',
        kind: 'card',
        narration: '90 cases remain.',
        onScreenText: 'The clinic dashboard updates each case throughout every workday',
        claims: ['unknown'],
        ui: { sourceJob: GHOST_JOB, clipId: 'missing' },
        sfx: [{ cue: 'later' }],
      }],
    }],
  };

  assert.deepEqual(
    lintSpec(spec, { forbiddenNames: ['CentralReach'], urls: { demo: 'https://brand.example/demo' } }, { io: io(false) }),
    {
      ok: false,
      errors: [
        { code: 'evidence', message: 'c1: evidence must start with file:, clip: or approved:', where: 'c1' },
        { code: 'claim-duplicate', message: 'duplicate claim id c1', where: 'c1' },
        { code: 'evidence', message: 'c1: approved: evidence needs a named source', where: 'c1' },
        { code: 'owner-voice', message: 'marketing narration is never the owner voice clone', where: 'voice' },
        { code: 'voice-policy', message: 'owner clone names and celebrity sound-alikes are not allowed', where: 'voice' },
        { code: 'disclosure', message: 'OpenAI voices require a stated AI-voice disclosure (usage policy)', where: 'voice' },
        { code: 'music', message: 'music.prompt is required when music.provider is elevenlabs', where: 'music' },
        { code: 'music', message: 'music.licenseBasis is required (Eleven Music terms limit paid-ad use by plan)', where: 'music' },
        { code: 'label', message: 'labels must state SYNTHETIC and NO PHI', where: 'labels' },
        { code: 'banned-phrase', message: '"Guarantee" (guarantee): No guarantees. — "Guarantee this, unlike CentralReach."', where: 'cta' },
        { code: 'banned-phrase', message: '"unlike" (comparative): No comparative claims without substantiation. — "Guarantee this, unlike CentralReach."', where: 'cta' },
        { code: 'forbidden-name', message: 'names "CentralReach", which must never appear in an ad', where: 'cta' },
        { code: 'cta-url', message: 'cta.url is not a valid URL', where: 'cta' },
        { code: 'claim-missing', message: 'cta.claim absent is not a claim id', where: 'cta' },
        { code: 'banned-phrase', message: '"Guarantee" (guarantee): No guarantees. — "Guarantee this, unlike CentralReach."', where: 'cta' },
        { code: 'banned-phrase', message: '"unlike" (comparative): No comparative claims without substantiation. — "Guarantee this, unlike CentralReach."', where: 'cta' },
        { code: 'forbidden-name', message: 'names "CentralReach", which must never appear in an ad', where: 'cta' },
        { code: 'beat-shape', message: 'card beats must not carry a ui clip', where: 'main/B1' },
        { code: 'claim-missing', message: 'beat references unknown claim unknown', where: 'main/B1' },
        { code: 'claim-unmapped', message: 'beat speaks or shows text but references no claim', where: 'main/B1' },
        { code: 'figure-unsupported', message: '"90" in "90 cases remain." is a figure no referenced claim states; invented or unsupported figures fail', where: 'main/B1' },
        { code: 'clip-missing', message: `capture receipt not found: ${join(GHOST_JOB, 'capture', 'receipt.json')}`, where: 'main/B1' },
        { code: 'sfx-cue', message: 'unsupported cue later', where: 'main/B1' },
        { code: 'music-length', message: 'music.lengthSeconds 1 s is shorter than cut main (4 s target) plus 2 s; the bed must outlast the program (the assets stage re-checks against the measured length)', where: 'music' },
        { code: 'no-ui', message: 'cut main has no real UI beat; credibility-bearing seconds must be captured product UI', where: 'main' },
      ],
      warnings: [
        { code: 'on-screen-length', message: 'on-screen text longer than 8 words will not survive phone-size reading', where: 'main/B1' },
        { code: 'short', message: 'cut main is estimated at 1.9 s against a 4 s target', where: 'main' },
      ],
      estimates: [{ cut: 'main', estimateSeconds: 1.9, targetSeconds: 4 }],
    },
  );
});
