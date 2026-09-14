#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { loadToolContract, mcpToolList, slackContractHash } from './contract.mjs';
import { resolveBackend } from './backend.mjs';

const PROTOCOL = '2025-11-25';
// packages/slack/plugin.json is the version authority (Bump-PackageVersion.ps1);
// serverInfo must not carry a second copy that drifts on the next bump.
const { version: PACKAGE_VERSION } = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'plugin.json'), 'utf8'),
);
const contract = loadToolContract();
const tools = mcpToolList(contract);
const contractHash = slackContractHash(contract);
const backend = resolveBackend();

function ok(id, result) {
  return { jsonrpc: '2.0', id, result };
}

function fail(id, code, message) {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

function toolResult(payload) {
  return {
    content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }],
    structuredContent: payload,
  };
}

async function callTool(name, args = {}) {
  switch (name) {
    case 'slack_search':
      return backend.search(args);
    case 'slack_channels':
      return backend.channels(args);
    case 'slack_users':
      return backend.users(args);
    case 'slack_messages':
      return backend.messages(args);
    case 'slack_thread':
      return backend.thread(args);
    case 'slack_post':
      return backend.post(args);
    case 'slack_reply':
      return backend.post({ ...args, thread_ts: args.thread_ts });
    case 'slack_update':
      return backend.update(args);
    case 'slack_delete':
      return backend.delete(args);
    case 'slack_react':
      return backend.react(args);
    case 'slack_unreact':
      return backend.unreact(args);
    case 'slack_file_get':
      return backend.fileGet(args);
    case 'slack_file_upload':
      return backend.fileUpload(args);
    case 'slack_permalink':
      return backend.permalink(args);
    case 'slack_channel_info':
      return backend.channelInfo(args);
    case 'slack_user_info':
      return backend.userInfo(args);
    case 'slack_whoami':
      return backend.whoami(args.actor_mode || 'user');
    case 'slack_pin':
      return backend.pin(args);
    case 'slack_unpin':
      return backend.unpin(args);
    case 'slack_bookmarks':
      return backend.bookmarks(args);
    case 'slack_canvas_get':
      return backend.canvasGet(args);
    case 'slack_list_items':
      return backend.listItems(args);
    case 'slack_api_read':
      return backend.apiRead(args);
    case 'slack_api_write':
      return backend.apiWrite(args);
    default:
      throw new Error(`unknown tool: ${name}`);
  }
}

async function handle(message) {
  if (!message || message.jsonrpc !== '2.0') {
    return fail(message && message.id != null ? message.id : null, -32600, 'invalid JSON-RPC');
  }
  const { id, method, params } = message;
  if (method === 'initialize') {
    return ok(id, {
      protocolVersion: PROTOCOL,
      capabilities: { tools: { listChanged: false } },
      serverInfo: {
        name: 'agenthub-slack',
        version: PACKAGE_VERSION,
      },
      _meta: {
        slackContractHash: contractHash,
        backend: backend.mode,
      },
    });
  }
  if (method === 'notifications/initialized' || method === 'notifications/cancelled') {
    return null;
  }
  if (method === 'ping') {
    return ok(id, {});
  }
  if (method === 'tools/list') {
    return ok(id, { tools });
  }
  if (method === 'tools/call') {
    try {
      const result = await callTool(params.name, params.arguments || {});
      return ok(id, toolResult(result));
    } catch (error) {
      return ok(id, {
        isError: true,
        content: [{ type: 'text', text: error.message || String(error) }],
      });
    }
  }
  if (method === 'resources/list') {
    return ok(id, { resources: [] });
  }
  if (method === 'prompts/list') {
    return ok(id, { prompts: [] });
  }
  return fail(id, -32601, `method not found: ${method}`);
}

let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', async (chunk) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, newline).replace(/\r$/, '');
    buffer = buffer.slice(newline + 1);
    if (!line.trim()) continue;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      process.stdout.write(`${JSON.stringify(fail(null, -32700, 'parse error'))}\n`);
      continue;
    }
    const response = await handle(message);
    if (response) {
      process.stdout.write(`${JSON.stringify(response)}\n`);
    }
  }
});

process.stdin.on('end', () => process.exit(0));
