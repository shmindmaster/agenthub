// The kit's ElevenLabs provider against the real speech adapter. Offline: the real credential is removed and every
// process spawned here is refused before it could reach the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { music, resolveCli, runCli, soundEffect, speech } from '../kit/marketing/lib/providers/elevenlabs.mjs';

delete process.env.ELEVENLABS_API_KEY;
delete process.env.MVG_ELEVENLABS_AUTHORIZATION;

const adapter = resolve(dirname(fileURLToPath(import.meta.url)), '../scripts/elevenlabs_cli.py');
const python = process.env.MVG_PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
const line = { text: 'A synthetic line.', voiceId: 'fixture-voice', model: 'eleven_v4', maxCredits: 21, workspace: 'fixture-workspace', revision: 'mvg-voice-v1', settings: { stability: 0.5, similarity_boost: 0.75, apply_text_normalization: 'auto' } };

function workspace(t) {
  const dir = mkdtempSync(join(tmpdir(), 'elevenlabs-provider-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function capture(output) {
  const seen = [];
  const run = async (_cli, args) => {
    seen.push(args);
    writeFileSync(`${output}.provenance.json`, JSON.stringify({ request_id: 'fixture-request', reused: false, actual_credits: null }));
    return { code: 0, stdout: `${JSON.stringify({ ok: true, output, acceptance_state: 'pending', reused: false })}\n`, stderr: '' };
  };
  return { seen, run };
}

test('speech hands the owner manifest to the adapter and keeps the existing arguments and receipt', async (t) => {
  const output = join(workspace(t), 'take.mp3');
  const { seen, run } = capture(output);
  const res = await speech({}, { ...line, output, run, authorizationManifest: 'C:/private/authorization.json' });
  const args = seen[0];
  assert.equal(args[0], 'tts');
  assert.deepEqual(args.slice(args.indexOf('--authorization-manifest'), args.indexOf('--authorization-manifest') + 2), ['--authorization-manifest', 'C:/private/authorization.json']);
  for (const [flag, value] of [['--text', line.text], ['--output', output], ['--voice-id', 'fixture-voice'], ['--model-id', 'eleven_v4'], ['--max-credits', '21'], ['--cache-workspace', 'fixture-workspace'], ['--cache-revision', 'mvg-voice-v1'], ['--stability', '0.5'], ['--similarity-boost', '0.75'], ['--text-normalization', 'auto']]) {
    assert.equal(args[args.indexOf(flag) + 1], value, flag);
  }
  assert.equal(res.receipt.request_id, 'fixture-request');
});

test('speech takes the manifest from MVG_ELEVENLABS_AUTHORIZATION for the unchanged voice stage', async (t) => {
  const output = join(workspace(t), 'take.mp3');
  const { seen, run } = capture(output);
  process.env.MVG_ELEVENLABS_AUTHORIZATION = 'C:/private/from-env.json';
  t.after(() => { delete process.env.MVG_ELEVENLABS_AUTHORIZATION; });
  await speech({}, { ...line, output, run });
  assert.equal(seen[0][seen[0].indexOf('--authorization-manifest') + 1], 'C:/private/from-env.json');
});

test('speech without owner authorization is refused by the real adapter, and nothing is written', async (t) => {
  const output = join(workspace(t), 'take.mp3');
  await assert.rejects(speech({ python, script: adapter, cwd: dirname(adapter) }, { ...line, output }), /owner authorization manifest/);
  assert.equal(existsSync(output), false);
  assert.equal(existsSync(`${output}.provenance.json`), false);
});

test('sound effects and music fail closed without starting the adapter', async () => {
  const run = async () => { throw new Error('the adapter must not start'); };
  await assert.rejects(soundEffect({}, { prompt: 'tick', output: 'x.mp3', durationSeconds: 1, maxCredits: 200, workspace: 'w', revision: 'r', run }), /speech only/);
  await assert.rejects(music({}, { prompt: 'bed', output: 'y.mp3', lengthMs: 30000, maxCredits: 500, workspace: 'w', revision: 'r', run }), /speech only/);
});

test('the real adapter has no sfx or music command', async () => {
  const cli = { python, script: adapter, cwd: dirname(adapter) };
  for (const args of [['sfx', '--text', 'a', '--output', 'b'], ['music', '--prompt', 'a', '--output', 'b']]) {
    const res = await runCli(cli, args);
    assert.equal(res.code, 2);
    assert.match(res.stderr, /invalid choice/);
  }
});

test('resolveCli still requires an explicit adapter path', () => {
  const previous = process.env.MVG_ELEVENLABS_CLI;
  delete process.env.MVG_ELEVENLABS_CLI;
  try {
    assert.throws(() => resolveCli(), /owner-authorized.*MVG_ELEVENLABS_CLI/);
  } finally {
    if (previous !== undefined) process.env.MVG_ELEVENLABS_CLI = previous;
  }
});
