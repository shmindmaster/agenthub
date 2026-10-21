// Local Qwen voice and local whisper through D:\Local-AI\ai.ps1 (the only supported entry to the local runtime).
// Both start a GPU job: mvg only calls them when the spec/brand selects the local provider, never in hosted-only runs.
import { spawn } from 'node:child_process';

const AI = process.env.MVG_LOCAL_AI || 'D:\\Local-AI\\ai.ps1';

function ps(args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', `& '${AI}' ${args}`], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...env } });
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { out += d; });
    child.on('error', reject);
    child.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(`ai.ps1 exited ${code}: ${out.trim().split('\n').pop()}`))));
  });
}

/** Qwen3-TTS role preset. Text and instruction travel in the environment so quoting never touches them. */
export async function qwenRole({ speaker, instruction, text, out }) {
  return ps('voice qwen-role --speaker $env:MVG_S --instruction $env:MVG_I --text $env:MVG_T --out $env:MVG_O --pronunciation-mode verified', { MVG_S: speaker, MVG_I: instruction, MVG_T: text, MVG_O: out });
}

/** Local whisper with word timestamps (faster-whisper JSON: segments[].words[]). */
export async function whisperWords({ file, jsonOut, txtOut }) {
  return ps('transcribe $env:MVG_F --engine whisper --no-vad --json-out $env:MVG_J --out $env:MVG_X', { MVG_F: file, MVG_J: jsonOut, MVG_X: txtOut });
}
