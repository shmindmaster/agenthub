import test from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough, Writable } from 'node:stream';
import { createAcpSession } from '../skills/use-coding-agent/cline/acp-session.mjs';

function fixture({ empty = false, unsupported = false, timeout = false, unconfirmed = false } = {}) {
  const input = new PassThrough();
  const methods = [];
  const responses = [];
  const reply = message => input.write(JSON.stringify({ jsonrpc: '2.0', ...message }) + '\n');
  const output = new Writable({ write(chunk, encoding, done) {
    const m = JSON.parse(chunk);
    if (!m.method) { responses.push(m); done(); return; }
    methods.push(m.method);
    queueMicrotask(() => {
      if (timeout) return;
      if (m.method === 'initialize') reply({ id: m.id, result: { agentCapabilities: { loadSession: !unsupported } } });
      if (m.method === 'session/load') {
        reply({ method: 'session/update', params: { sessionId: 'existing', update: { sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'old history' } } } });
        reply({ id: m.id, result: {} });
      }
      if (m.method === 'session/set_config_option') {
        const value = unconfirmed && m.params.configId === 'model' ? 'anthropic/claude-sonnet-5.5' : m.params.value;
        reply({ id: m.id, result: { configOptions: [{ id: m.params.configId, currentValue: value }] } });
      }
      if (m.method === 'session/prompt') {
        assert.equal(m.params.sessionId, 'existing');
        reply({ id: 91, method: 'session/request_permission', params: {} });
        if (!empty) for (const text of ['new ', 'reply']) reply({ method: 'session/update', params: { sessionId: 'existing', update: { sessionUpdate: 'agent_message_chunk', content: { type: 'text', text } } } });
        reply({ id: m.id, result: { stopReason: 'end_turn' } });
      }
    });
    done();
  } });
  return { client: createAcpSession(input, output, { timeoutMs: 50 }), methods, responses };
}
const options = { sessionId: 'existing', cwd: 'C:/synthetic', prompt: 'continue', provider: 'cline', model: 'synthetic/model:free' };
test('resume loads existing session and awaits prompt reply, excluding replay', async () => {
  const f = fixture();
  try {
    assert.deepEqual(await f.client.resume(options), { sessionId: 'existing', text: 'new reply', stopReason: 'end_turn' });
    assert.deepEqual(f.methods, ['initialize', 'session/load', 'session/set_config_option', 'session/set_config_option', 'session/prompt']);
    assert.equal(f.responses[0].result.outcome.outcome, 'cancelled');
  } finally { f.client.close(); }
});
for (const [name, config, expected] of [['empty reply', { empty: true }, /without an assistant reply/], ['unsupported resume', { unsupported: true }, /does not support/], ['bounded timeout', { timeout: true }, /timeout/], ['unconfirmed model refuses before prompting', { unconfirmed: true }, /did not confirm model/]]) {
  test(name, async () => { const f = fixture(config); try { await assert.rejects(f.client.resume(options), expected); } finally { f.client.close(); } });
}
test('resume requires an explicit provider and model', async () => {
  const f = fixture();
  try { await assert.rejects(f.client.resume({ sessionId: 'existing', cwd: 'C:/synthetic', prompt: 'continue' }), /provider and model are required/); assert.deepEqual(f.methods, []); } finally { f.client.close(); }
});
