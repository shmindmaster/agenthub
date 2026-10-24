// ACP protocol adapter only: the caller owns transport, host policy and process
// lifetime. This module never starts a host, approves a tool or opens a window.
import { createInterface } from 'node:readline';

export function createAcpSession(input, output, { timeoutMs = 30000 } = {}) {
  let nextId = 0;
  const pending = new Map();
  const listeners = new Set();
  const lines = createInterface({ input, crlfDelay: Infinity });
  const send = message => output.write(JSON.stringify({ jsonrpc: '2.0', ...message }) + '\n');
  function fail(error) {
    for (const entry of pending.values()) { clearTimeout(entry.timer); entry.reject(error); }
    pending.clear();
  }
  lines.on('close', () => fail(new Error('ACP transport closed before response')));
  input.on('error', fail);
  output.on('error', fail);
  lines.on('line', line => {
    let message;
    try { message = JSON.parse(line); } catch { fail(new Error('Invalid ACP JSON response')); return; }
    if (message.method) {
      // Never silently grant tool permissions. ACP cancellation is safe even
      // when a host emits a permission request during a resumed prompt.
      if (message.method === 'session/request_permission' && message.id !== undefined) {
        send({ id: message.id, result: { outcome: { outcome: 'cancelled' } } });
      } else if (message.id !== undefined) {
        send({ id: message.id, error: { code: -32601, message: 'Unsupported client method' } });
      } else {
        for (const listener of listeners) listener(message);
      }
      return;
    }
    const entry = pending.get(message.id);
    if (!entry) return;
    pending.delete(message.id);
    clearTimeout(entry.timer);
    if (message.error) entry.reject(new Error(`ACP ${message.error.code}: ${message.error.message}`));
    else entry.resolve(message.result);
  });
  function request(method, params) {
    return new Promise((resolve, reject) => {
      const id = ++nextId;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(`ACP timeout: ${method}`)); }, timeoutMs);
      pending.set(id, { resolve, reject, timer });
      send({ id, method, params });
    });
  }
  return {
    async resume({ sessionId, cwd, prompt }) {
      if (!sessionId || !cwd || typeof prompt !== 'string' || !prompt.trim()) throw new Error('sessionId, cwd and prompt are required');
      const initialized = await request('initialize', { protocolVersion: 1, clientCapabilities: {}, clientInfo: { name: 'agenthub', version: '1' } });
      if (!initialized.agentCapabilities?.loadSession) throw new Error('ACP agent does not support session/load');
      // session/load replays old history; collect only updates after loading.
      await request('session/load', { sessionId, cwd, mcpServers: [] });
      let text = '';
      const collect = message => {
        const update = message.params?.update;
        if (message.method === 'session/update' && message.params.sessionId === sessionId && update?.sessionUpdate === 'agent_message_chunk' && update.content?.type === 'text') text += update.content.text;
      };
      listeners.add(collect);
      try {
        const result = await request('session/prompt', { sessionId, prompt: [{ type: 'text', text: prompt }] });
        if (!text.trim()) throw new Error('ACP prompt completed without an assistant reply');
        return { sessionId, text, stopReason: result.stopReason };
      } finally { listeners.delete(collect); }
    },
    close() { fail(new Error('ACP client closed')); lines.close(); }
  };
}
