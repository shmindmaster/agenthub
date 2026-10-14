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

function startServer(mode = 'fixture') {
  const child = spawn(process.execPath, [serverPath], {
    env: {
      ...process.env,
      SLACK_BRIDGE_MODE: mode,
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
      arguments: { channel_id: 'C0ENG', text: 'fixture post', approved: true },
    }));
    assert.equal(posted.channel_id, 'C0ENG');
    assert.ok(posted.ts);
    const replied = parseTool(await call('tools/call', {
      name: 'slack_reply',
      arguments: { channel_id: 'C0ENG', thread_ts: posted.ts, text: 'fixture reply', approved: true },
    }));
    assert.equal(replied.thread_ts, posted.ts);
    const edited = parseTool(await call('tools/call', {
      name: 'slack_update',
      arguments: { channel_id: 'C0ENG', ts: posted.ts, text: 'fixture post edited', approved: true },
    }));
    assert.equal(edited.text, 'fixture post edited');
    assert.ok(edited.edited);
    const reacted = parseTool(await call('tools/call', {
      name: 'slack_react',
      arguments: { channel_id: 'C0ENG', ts: posted.ts, name: 'white_check_mark', approved: true },
    }));
    assert.equal(reacted.reactions[0].name, 'white_check_mark');
    await call('tools/call', {
      name: 'slack_unreact',
      arguments: { channel_id: 'C0ENG', ts: posted.ts, name: 'white_check_mark', approved: true },
    });
    const uploaded = parseTool(await call('tools/call', {
      name: 'slack_file_upload',
      arguments: { filename: 'note.txt', content_base64: Buffer.from('hi').toString('base64'), channel_id: 'C0ENG', approved: true },
    }));
    assert.match(uploaded.file_id, /^F/);
    const deleted = parseTool(await call('tools/call', {
      name: 'slack_delete',
      arguments: { channel_id: 'C0ENG', ts: posted.ts, approved: true },
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

// Every write tool, with arguments that would succeed once approved. The seed
// message is created by an approved slack_post first, so each call targets a
// real fixture message.
function writeCalls(ts) {
  return {
    slack_post: { channel_id: 'C0ENG', text: 'gate probe' },
    slack_reply: { channel_id: 'C0ENG', thread_ts: ts, text: 'gate probe reply' },
    slack_update: { channel_id: 'C0ENG', ts, text: 'gate probe edited' },
    slack_react: { channel_id: 'C0ENG', ts, name: 'eyes' },
    slack_unreact: { channel_id: 'C0ENG', ts, name: 'eyes' },
    slack_file_upload: { filename: 'gate.txt', content_base64: Buffer.from('gate').toString('base64'), channel_id: 'C0ENG' },
    slack_pin: { channel_id: 'C0ENG', ts },
    slack_unpin: { channel_id: 'C0ENG', ts },
    slack_delete: { channel_id: 'C0ENG', ts },
  };
}

async function seed(call) {
  await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
  return parseTool(await call('tools/call', {
    name: 'slack_post',
    arguments: { channel_id: 'C0ENG', text: 'gate seed', approved: true },
  }));
}

test('every write tool refuses without approved=true and leaves the workspace unchanged', async () => {
  const { child, call } = startServer();
  try {
    const seeded = await seed(call);
    const before = parseTool(await call('tools/call', { name: 'slack_messages', arguments: { channel_id: 'C0ENG' } }));
    for (const [name, args] of Object.entries(writeCalls(seeded.ts))) {
      for (const approved of [undefined, false, 'true']) {
        const callArgs = approved === undefined ? args : { ...args, approved };
        const denied = await call('tools/call', { name, arguments: callArgs });
        assert.equal(denied.result.isError, true, `${name} approved=${approved} was not refused`);
        assert.match(denied.result.content[0].text, /requires approved=true/, name);
      }
    }
    const after = parseTool(await call('tools/call', { name: 'slack_messages', arguments: { channel_id: 'C0ENG' } }));
    assert.deepEqual(after.messages, before.messages, 'a refused write changed the workspace');
  } finally {
    child.kill();
  }
});

test('every write tool succeeds with approved=true in explicit fixture mode', async () => {
  const { child, call } = startServer();
  try {
    const seeded = await seed(call);
    for (const [name, args] of Object.entries(writeCalls(seeded.ts))) {
      const res = await call('tools/call', { name, arguments: { ...args, approved: true } });
      assert.notEqual(res.result.isError, true, `${name}: ${res.result.content[0].text}`);
    }
  } finally {
    child.kill();
  }
});

test('slack_api_write keeps both gates: approved=true and SLACK_BRIDGE_ALLOW_API_WRITE', async () => {
  const { child, call } = startServer();
  try {
    await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
    const noApproval = await call('tools/call', { name: 'slack_api_write', arguments: { method: 'chat.postMessage' } });
    assert.equal(noApproval.result.isError, true);
    assert.match(noApproval.result.content[0].text, /requires approved=true/);
    const noEnv = await call('tools/call', { name: 'slack_api_write', arguments: { method: 'chat.postMessage', approved: true } });
    assert.equal(noEnv.result.isError, true);
    assert.match(noEnv.result.content[0].text, /SLACK_BRIDGE_ALLOW_API_WRITE=true/);
  } finally {
    child.kill();
  }
});

test('slack_bookmarks list is a read; add and remove are gated writes', async () => {
  const { child, call } = startServer();
  try {
    await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
    const listed = await call('tools/call', { name: 'slack_bookmarks', arguments: { channel_id: 'C0ENG', action: 'list' } });
    assert.notEqual(listed.result.isError, true);
    const deniedAdd = await call('tools/call', { name: 'slack_bookmarks', arguments: { channel_id: 'C0ENG', action: 'add', title: 'x', link: 'https://example.test' } });
    assert.equal(deniedAdd.result.isError, true);
    assert.match(deniedAdd.result.content[0].text, /requires approved=true/);
    const added = parseTool(await call('tools/call', { name: 'slack_bookmarks', arguments: { channel_id: 'C0ENG', action: 'add', title: 'x', link: 'https://example.test', approved: true } }));
    const deniedRemove = await call('tools/call', { name: 'slack_bookmarks', arguments: { channel_id: 'C0ENG', action: 'remove', bookmark_id: added.bookmark.id } });
    assert.equal(deniedRemove.result.isError, true);
    const removed = await call('tools/call', { name: 'slack_bookmarks', arguments: { channel_id: 'C0ENG', action: 'remove', bookmark_id: added.bookmark.id, approved: true } });
    assert.notEqual(removed.result.isError, true);
  } finally {
    child.kill();
  }
});

test('with no token and no explicit mode, reads fall back to fixtures but approved writes are refused', async () => {
  const { child, call } = startServer('');
  try {
    const init = await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
    assert.equal(init.result._meta.backendSource, 'fallback-fixture');
    const read = await call('tools/call', { name: 'slack_channels', arguments: {} });
    assert.notEqual(read.result.isError, true);
    const write = await call('tools/call', { name: 'slack_post', arguments: { channel_id: 'C0ENG', text: 'x', approved: true } });
    assert.equal(write.result.isError, true);
    assert.match(write.result.content[0].text, /SLACK_BRIDGE_MODE=fixture/);
  } finally {
    child.kill();
  }
});

test('tools/list annotations agree with the write gate', async () => {
  const { WRITE_TOOLS } = await import('./write-gate.mjs');
  const { child, call } = startServer();
  try {
    await call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
    const listed = await call('tools/list', {});
    for (const tool of listed.result.tools) {
      assert.ok(tool.annotations, `${tool.name} has no annotations`);
      const gatedAlways = WRITE_TOOLS.has(tool.name);
      if (gatedAlways) {
        assert.equal(tool.annotations.readOnlyHint, false, `${tool.name} is a write but claims readOnlyHint`);
        assert.ok(tool.inputSchema.required.includes('approved'), `${tool.name} does not require approved`);
      } else if (tool.name !== 'slack_bookmarks') {
        assert.equal(tool.annotations.readOnlyHint, true, `${tool.name} is a read without readOnlyHint`);
      }
    }
    const deleteTool = listed.result.tools.find((t) => t.name === 'slack_delete');
    assert.equal(deleteTool.annotations.destructiveHint, true);
  } finally {
    child.kill();
  }
});
