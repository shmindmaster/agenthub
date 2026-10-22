// Local Qwen voice and local whisper through D:\Local-AI\ai.ps1 (the only supported entry to the local runtime).
// Both start a GPU job: mvg only calls them when the spec/brand selects the local provider, never in hosted-only runs.
import { spawn } from 'node:child_process';

const AI = process.env.MVG_LOCAL_AI || 'D:\\Local-AI\\ai.ps1';

function ps(args, env, { stdoutOnly = false, spawnImpl = spawn } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawnImpl('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', `& '${AI.replace(/'/g, "''")}' ${args}`], { windowsHide: true, timeout: 1800000, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...env } });
    let out = '', err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; if (!stdoutOnly) out += d; });
    child.on('error', reject);
    child.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(`ai.ps1 exited ${code}: ${(err || out).trim().split('\n').pop()}`))));
  });
}
export { ps as localCommandOutput };

export async function alignWords({ file, script, output }) {
  return ps('align $env:MVG_F --script $env:MVG_SCRIPT --language English --output $env:MVG_O', { MVG_F: file, MVG_SCRIPT: script, MVG_O: output });
}

export function visionEndpoint(capability) {
  if (capability?.id !== 'provider.local' || capability.status !== 'enabled') throw new Error(`Local-AI vision unavailable: provider.local is ${capability?.status || 'unknown'}; no service started or paid fallback attempted`);
  if (!(capability.required_files || []).some((p) => /mmproj/i.test(p))) throw new Error('Local-AI provider has no registered vision projector');
  const url = new URL(capability.serves);
  if (url.protocol !== 'http:' || !['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname) || url.username || url.password || url.search || url.hash) throw new Error('Local-AI vision endpoint must be credential-free loopback HTTP');
  return url.href.replace(/\/$/, '');
}

/** Existing Local-AI vision service only. Never starts a retired LLM, downloads weights, or reclaims retrieval. */
export async function localVisionJson({ frames, system, instructions, schema, schemaName }, { discover, fetchImpl = fetch } = {}) {
  const capability = discover ? await discover() : JSON.parse(await ps('capability provider.local --json', {}, { stdoutOnly: true }));
  const endpoint = visionEndpoint(capability);
  const request = async (path, init = {}) => {
    const response = await fetchImpl(`${endpoint}/${path}`, { ...init, redirect: 'error', signal: AbortSignal.timeout(180000) });
    if (!response.ok) throw new Error(`Local-AI vision HTTP ${response.status}`);
    return response.json();
  };
  const models = await request('models');
  if (models.data?.length !== 1 || !models.data[0].id) throw new Error('Local-AI vision requires one unambiguous served model');
  const model = models.data[0].id;
  const verdicts = [];
  for (const frame of frames) {
    const response = await request('chat/completions', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, temperature: 0, max_tokens: 2048,
        response_format: { type: 'json_schema', json_schema: { name: schemaName, strict: true, schema } },
        messages: [{ role: 'system', content: system }, { role: 'user', content: [
          { type: 'text', text: `${instructions}\nReview only frame ${frame.label} at ${frame.t}s. Return exactly that frame label.` },
          { type: 'image_url', image_url: { url: frame.dataUrl } },
        ] }],
      }),
    });
    verdicts.push(response.choices?.[0]?.message?.content);
  }
  // The shared parser validates both each single-frame response and the combined result.
  return { frameTexts: verdicts, model, capability: capability.id };
}

/** Qwen3-TTS role preset. Text and instruction travel in the environment so quoting never touches them. */
export async function qwenRole({ speaker, instruction, text, out }) {
  return ps('voice qwen-role --speaker $env:MVG_S --instruction $env:MVG_I --text $env:MVG_T --out $env:MVG_O --pronunciation-mode verified', { MVG_S: speaker, MVG_I: instruction, MVG_T: text, MVG_O: out });
}

/** Local whisper with word timestamps (faster-whisper JSON: segments[].words[]). */
export async function whisperWords({ file, jsonOut, txtOut }) {
  return ps('transcribe $env:MVG_F --engine whisper --no-vad --json-out $env:MVG_J --out $env:MVG_X', { MVG_F: file, MVG_J: jsonOut, MVG_X: txtOut });
}
