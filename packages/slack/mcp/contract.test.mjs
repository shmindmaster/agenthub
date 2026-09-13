import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import test from 'node:test';
import { loadToolContract, slackContractHash } from './contract.mjs';
import { normalizeMessage, assertIdsPreserved } from './normalize.mjs';
import { createFixtureBackend } from './backend.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const serverPath = join(here, 'slack-mcp.mjs');

function rpc(child) {
  let buf = '';
  const pending = new Map();
  let nextId = 1;
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => {
    buf += chunk;
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl).replace(/\r$/, '');
      buf = buf.slice(nl + 1);
      if (!line.trim()) continue;
      const msg = JSON.parse(line);
      const waiter = pending.get(msg.id);
      if (waiter) {
        pending.delete(msg.id);
        waiter(msg);
      }
    }
  });
  return (method, params) => {
    const id = nextId++;
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`timeout: ${method}`)), 8000);
      pending.set(id, (msg) => {
        clearTimeout(timer);
        resolve(msg);
      });
    });
  };
}

function startServer() {
  const child = spawn(process.execPath, [serverPath], {
    env: {
      ...process.env,
      SLACK_BRIDGE_MODE: 'fixture',
      SLACK_USER_TOKEN: '',
      SLACK_BOT_TOKEN: '',
      SLACK_BRIDGE_ALLOW_API_WRITE: '',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return { child, call: rpc(child) };
}

function parseTool(msg) {
  assert.equal(msg.error, undefined, msg.error && msg.error.message);
  const text = msg.result.content[0].text;
  return JSON.parse(text);
}

test('contract hash is stable sha256 of sorted tools', () => {
  const doc = loadToolContract();
  assert.ok(doc.tools.length >= 20, 'canonical surface is too small');
  const hash = slackContractHash(doc);
  assert.match(hash, /^[A-F0-9]{64}$/);
  assert.equal(hash, slackContractHash(doc));
});

test('normalize keeps IDs and raw', () => {
  const raw = {
    user: 'U0CUSTOMER',
    text: 'hello',
    ts: '1789051234.123456',
    channel: 'C0REPORTS',
    bot_id: null,
    app_id: 'A9',
    blocks: [{ type: 'section' }],
    attachments: [{ id: 1 }],
    files: [{ id: 'F0' }],
    reactions: [{ name: 'eyes', users: ['U0CASEY'], count: 1 }],
    edited: { user: 'U0CASEY', ts: '1' },
    subtype: null,
  };
  const msg = normalizeMessage(raw, { workspace_id: 'T0FIXTURE', permalink: 'https://example.test/p' });
  assertIdsPreserved(msg);
  assert.equal(msg.channel_id, 'C0REPORTS');
  assert.equal(msg.ts, '1789051234.123456');
  assert.equal(msg.author.user_id, 'U0CUSTOMER');
  assert.equal(msg.author.app_id, 'A9');
  assert.equal(msg.blocks.length, 1);
  assert.equal(msg.attachments.length, 1);
  assert.equal(msg.files[0].id, 'F0');
  assert.equal(msg.reactions[0].name, 'eyes');
  assert.equal(msg.permalink, 'https://example.test/p');
  assert.equal(msg.raw.user, 'U0CUSTOMER');
});

test('fixture thread preserves authors, edits, files, reactions', async () => {
  const backend = createFixtureBackend();
  const thread = await backend.thread({ channel_id: 'C0REPORTS', ts: '1789051234.123456' });
  assert.equal(thread.parent.author.user_id, 'U0CUSTOMER');
  assert.equal(thread.parent.files[0].id, 'F0SHOT');
  assert.equal(thread.parent.reactions[0].name, 'eyes');
  assert.equal(thread.parent.blocks.length, 1);
  const casey = thread.messages.find((m) => m.author.user_id === 'U0CASEY');
  assert.ok(casey.edited);
  const bot = thread.messages.find((m) => m.author.bot_id === 'B0TICKET');
  assert.equal(bot.author.app_id, 'A0TICKET');
  assert.ok(thread.parent.permalink.includes('C0REPORTS'));
});

test('MCP initialize and tools/list match the contract', async () => {
  const { child, call } = startServer();
  try {
    const init = await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
    assert.equal(init.result.protocolVersion, '2025-11-25');
    assert.match(init.result._meta.slackContractHash, /^[A-F0-9]{64}$/);
    assert.equal(init.result._meta.slackContractHash, slackContractHash());
    const listed = await call('tools/list', {});
    const names = listed.result.tools.map((t) => t.name).sort();
    const expected = loadToolContract().tools.map((t) => t.name).sort();
    assert.deepEqual(names, expected);
  } finally {
    child.kill();
  }
});

test('write roundtrip in fixture mode', async () => {
  const { child, call } = startServer();
  try {
    await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
    const posted = parseTool(await call('tools/call', {
      name: 'slack_post',
      arguments: { channel_id: 'C0ENG', text: 'fixture post' },
    }));
    assert.equal(posted.channel_id, 'C0ENG');
    assert.ok(posted.ts);
    const replied = parseTool(await call('tools/call', {
      name: 'slack_reply',
      arguments: { channel_id: 'C0ENG', thread_ts: posted.ts, text: 'fixture reply' },
    }));
    assert.equal(replied.thread_ts, posted.ts);
    const edited = parseTool(await call('tools/call', {
      name: 'slack_update',
      arguments: { channel_id: 'C0ENG', ts: posted.ts, text: 'fixture post edited' },
    }));
    assert.equal(edited.text, 'fixture post edited');
    assert.ok(edited.edited);
    const reacted = parseTool(await call('tools/call', {
      name: 'slack_react',
      arguments: { channel_id: 'C0ENG', ts: posted.ts, name: 'white_check_mark' },
    }));
    assert.equal(reacted.reactions[0].name, 'white_check_mark');
    await call('tools/call', {
      name: 'slack_unreact',
      arguments: { channel_id: 'C0ENG', ts: posted.ts, name: 'white_check_mark' },
    });
    const uploaded = parseTool(await call('tools/call', {
      name: 'slack_file_upload',
      arguments: { filename: 'note.txt', content_base64: Buffer.from('hi').toString('base64'), channel_id: 'C0ENG' },
    }));
    assert.match(uploaded.file_id, /^F/);
    const deleted = parseTool(await call('tools/call', {
      name: 'slack_delete',
      arguments: { channel_id: 'C0ENG', ts: posted.ts },
    }));
    assert.equal(deleted.ok, true);
  } finally {
    child.kill();
  }
});

test('slack_api_write fails closed without approval', async () => {
  const { child, call } = startServer();
  try {
    await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
    const denied = await call('tools/call', {
      name: 'slack_api_write',
      arguments: { method: 'chat.postMessage', approved: false },
    });
    assert.equal(denied.result.isError, true);
    assert.match(denied.result.content[0].text, /approved=true/);
  } finally {
    child.kill();
  }
});
