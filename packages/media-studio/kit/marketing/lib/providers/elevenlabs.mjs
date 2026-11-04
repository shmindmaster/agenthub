// ElevenLabs speech through the governed adapter at packages/media-studio/scripts/elevenlabs_cli.py, named by
// MVG_ELEVENLABS_CLI. It runs for owner-authorized jobs only: the immutable manifest must name the exact voice and job
// workspace (MVG_ELEVENLABS_AUTHORIZATION or o.authorizationManifest), or the adapter refuses before any network call.
// Every paid call reserves credits in that job's ledger and is receipt-bound; mvg never talks to the REST API directly.
// Sound effects and music stay disabled: the adapter is speech only.
// Run with plain `python`, never `python -I` (isolated mode drops the script folder and the adapter import fails).
import { spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export function resolveCli() {
  const script = process.env.MVG_ELEVENLABS_CLI;
  if (!script || !existsSync(script)) throw new Error('ElevenLabs speech is owner-authorized only: use an Azure voice, or set MVG_ELEVENLABS_CLI to packages/media-studio/scripts/elevenlabs_cli.py in the AgentHub checkout');
  return { python: process.env.MVG_PYTHON || 'python', script, cwd: join(script, '..') };
}

/** Run the adapter without a window; resolves { code, stdout, stderr }. Secrets are never echoed by the adapter. */
export function runCli(cli, args, { timeoutMs = 600000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cli.python, [cli.script, ...args], { cwd: cli.cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: process.env });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('ElevenLabs adapter timed out; the reservation is retained, recover before retrying')); }, timeoutMs);
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', (e) => { clearTimeout(timer); reject(e); });
    child.on('close', (code) => { clearTimeout(timer); resolve({ code, stdout, stderr }); });
  });
}

function parseResult(res, what) {
  if (res.code !== 0) throw new Error(`${what} failed: ${(res.stderr || res.stdout).trim().split('\n').pop()}`);
  const line = res.stdout.trim().split('\n').filter((l) => l.startsWith('{')).pop();
  if (!line) throw new Error(`${what}: adapter printed no result`);
  return JSON.parse(line);
}

const readReceipt = (out) => JSON.parse(readFileSync(`${out}.provenance.json`, 'utf8'));

export async function speech(cli, o) {
  const s = o.settings || {};
  const args = ['tts', '--text', o.text, '--output', o.output, '--voice-id', o.voiceId, '--model-id', o.model,
    '--max-credits', String(o.maxCredits), '--cache-workspace', o.workspace, '--cache-revision', o.revision];
  if (s.stability !== undefined) args.push('--stability', String(s.stability));
  if (s.similarity_boost !== undefined) args.push('--similarity-boost', String(s.similarity_boost));
  if (s.style !== undefined) args.push('--style', String(s.style));
  if (s.speed !== undefined) args.push('--speed', String(s.speed));
  if (s.use_speaker_boost !== undefined) args.push(s.use_speaker_boost ? '--use-speaker-boost' : '--no-use-speaker-boost');
  if (s.apply_text_normalization) args.push('--text-normalization', s.apply_text_normalization);
  if (o.previousText) args.push('--previous-text', o.previousText);
  if (o.nextText) args.push('--next-text', o.nextText);
  for (const d of o.dictionaries || []) args.push('--pronunciation-dictionary', `${d.id}:${d.version}`);
  const manifest = o.authorizationManifest ?? process.env.MVG_ELEVENLABS_AUTHORIZATION;
  if (manifest) args.push('--authorization-manifest', manifest);
  const result = parseResult(await (o.run || runCli)(cli, args), 'speech');
  return { ...result, receipt: readReceipt(o.output) };
}

const speechOnly = (what) => new Error(`ElevenLabs ${what} are disabled: the governed adapter is speech only. Use an accepted, licensed asset`);

export async function soundEffect() {
  throw speechOnly('sound effects');
}

export async function music() {
  throw speechOnly('music beds');
}
