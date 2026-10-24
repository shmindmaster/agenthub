// Launched only by the policy-gated dispatcher. No listener or persistent service.
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';
import { createAcpSession } from './acp-session.mjs';

export function transportCommand(executable, platform = process.platform) {
  if (typeof executable !== 'string' || !executable.trim()) throw new Error('ACP executable is required');
  const args = ['--acp', '--auto-approve', 'false'];
  if (platform === 'win32' && /\.(cmd|bat)$/i.test(executable)) {
    // Only a registry path and fixed flags reach cmd; task/session text stays on stdin.
    if (/["%!\r\n&|<>^]/.test(executable)) throw new Error('Unsafe ACP batch executable path');
    return { file: process.env.ComSpec || 'C:\\Windows\\System32\\cmd.exe', args: ['/d', '/s', '/c', `""${executable}" ${args.join(' ')}"`], windowsVerbatimArguments: true };
  }
  return { file: executable, args, windowsVerbatimArguments: false };
}

export async function resumeDispatch(config, { spawnHost = spawn, stopHost } = {}) {
  const { sessionId, cwd, prompt, timeoutMs } = config;
  if (typeof sessionId !== 'string' || !sessionId.trim() || typeof cwd !== 'string' || !cwd.trim() || typeof prompt !== 'string' || !prompt.trim()) throw new Error('sessionId, cwd and prompt are required');
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1) throw new Error('ACP timeout must be positive');
  const command = transportCommand(config.executable);
  const child = spawnHost(command.file, command.args, { cwd, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true, shell: false, windowsVerbatimArguments: command.windowsVerbatimArguments });
  // Consume diagnostics without echoing host history, configuration or protocol data.
  child.stderr.resume();
  const client = createAcpSession(child.stdout, child.stdin, { timeoutMs });
  const onError = error => child.stdout.destroy(error);
  child.on('error', onError);
  try {
    return await client.resume({ sessionId, cwd, prompt });
  } finally {
    client.close();
    child.removeListener('error', onError);
    if (stopHost) await stopHost(child);
    else if (child.pid && child.exitCode === null) {
      if (process.platform === 'win32') {
        // A failed cleanup must fail the dispatch, never report a successful reply.
        // The outer dispatcher still owns the bounded tree timeout if this fails.
        await promisify(execFile)('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, timeout: 5000 });
      } else child.kill();
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    let input = '';
    for await (const chunk of process.stdin) input += chunk;
    const result = await resumeDispatch(JSON.parse(input));
    process.stdout.write(JSON.stringify(result) + '\n');
  } catch (error) {
    process.stderr.write(`Cline ACP resume failed: ${error.message}\n`);
    process.exitCode = 1;
  }
}
