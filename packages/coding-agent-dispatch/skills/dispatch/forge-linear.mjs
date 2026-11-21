import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const LINEAR_MCP = 'https://mcp.linear.app/mcp';
const PROTOCOL = '2025-06-18';
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;

function accessToken(home, linear, readFile) {
  // The launcher refreshes this service account's native OAuth session during selection.
  const store = JSON.parse(readFile(join(home, '.codex', '.credentials.json'), 'utf8'));
  const matches = Object.values(store).filter((entry) => entry.server_name === linear.server && entry.server_url === LINEAR_MCP);
  if (matches.length !== 1 || !matches[0].access_token) throw new Error('Forge Linear OAuth is missing for the configured workspace');
  return matches[0].access_token;
}

async function readRpc(response, id) {
  if (!response.headers.get('content-type')?.includes('text/event-stream')) return response.json();
  const decoder = new TextDecoder();
  let remaining = '';
  for await (const chunk of response.body) {
    remaining += decoder.decode(chunk, { stream: true });
    const lines = remaining.split('\n');
    remaining = lines.pop();
    for (const line of lines) {
      if (!line.startsWith('data:')) continue;
      const event = JSON.parse(line.slice(5));
      if (event.id === id) return event;
    }
  }
  throw new Error('Linear MCP closed the response before returning a result');
}

function toolData(result) {
  if (result.isError) throw new Error('Linear MCP rejected the request');
  const content = result.content?.find((item) => item.type === 'text')?.text;
  const data = result.structuredContent ?? JSON.parse(content ?? '{}');
  if (data.error) throw new Error('Linear MCP reported a tool error');
  return data;
}

export async function connectForgeLinear(linear, home, { fetchImpl = fetch, readFile = readFileSync } = {}) {
  if (linear.mcpUrl !== LINEAR_MCP) throw new Error('Forge Linear requires the official MCP endpoint');
  const token = accessToken(home, linear, readFile);
  let seq = 0;
  let session;
  let protocol = PROTOCOL;
  const rpc = async (method, params) => {
    const notification = method === 'notifications/initialized';
    const id = notification ? undefined : ++seq;
    const headers = {
      Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream', 'Mcp-Protocol-Version': protocol,
    };
    if (session) headers['Mcp-Session-Id'] = session;
    const response = await fetchImpl(LINEAR_MCP, {
      method: 'POST', headers, redirect: 'error', signal: AbortSignal.timeout(20_000),
      body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
    });
    if (!response.ok) throw new Error(`Linear MCP ${method} failed (HTTP ${response.status})`);
    if (method === 'initialize') session = response.headers.get('mcp-session-id');
    if (notification) return;
    const envelope = await readRpc(response, id);
    if (envelope.id !== id || envelope.error || !envelope.result) throw new Error(`Linear MCP ${method} returned an invalid response`);
    return envelope.result;
  };

  const init = await rpc('initialize', { protocolVersion: PROTOCOL, capabilities: {}, clientInfo: { name: 'forge-intake', version: '1' } });
  if (init.protocolVersion !== PROTOCOL) throw new Error('Forge Linear MCP negotiated an unsupported protocol');
  protocol = init.protocolVersion;
  await rpc('notifications/initialized');
  const call = async (name, args) => toolData(await rpc('tools/call', { name, arguments: args }));
  const team = await call('get_team', { query: linear.teamId });
  if (team.id !== linear.teamId || team.key !== linear.teamKey) throw new Error('Forge Linear OAuth does not resolve the configured team');

  const requireScope = (issue, item) => {
    if (item.uuid !== issue.uuid || item.id !== issue.issue || item.teamId !== linear.teamId || item.projectId !== linear.projectId || item.archivedAt) {
      throw new Error('Forge Linear issue is outside the configured active project');
    }
    return item;
  };
  const readIssue = async (issue) => {
    if (!UUID.test(issue.uuid ?? '')) throw new Error('Forge Linear issue UUID is invalid');
    return requireScope(issue, await call('get_issue', { id: issue.uuid }));
  };

  const writeState = async (issue, before, state, action) => {
    const field = action === 'claim' ? 'addLabels' : 'removeLabels';
    try {
      await call('save_issue', { id: issue.uuid, state, [field]: [linear.claimLabel] });
    } catch (error) {
      // Linear may have applied the request before the connection failed. Read it before retrying.
      const after = await readIssue(issue);
      const claimed = after.labels?.includes(linear.claimLabel);
      if (before.status !== after.status || before.labels?.includes(linear.claimLabel) !== claimed) {
        if (after.status === state && claimed === (action === 'claim')) return after;
      }
      throw error;
    }
    return readIssue(issue);
  };

  return {
    readIssue,
    async resolveIssue(issue) {
      if (typeof issue.issue !== 'string' || !/^([A-Z]+)-\d{1,7}$/.test(issue.issue) || !issue.issue.startsWith(`${linear.teamKey}-`)) {
        throw new Error('Forge Linear issue identifier is invalid');
      }
      const item = await call('get_issue', { id: issue.issue });
      if (!UUID.test(item.uuid ?? '')) throw new Error('Forge Linear did not resolve an issue UUID');
      const resolved = { ...issue, uuid: item.uuid };
      requireScope(resolved, item);
      return resolved;
    },
    async claim(issue, verifyReady) {
      const before = await readIssue(issue);
      if (!verifyReady(before)) throw new Error('Forge Linear issue is no longer eligible');
      const after = await writeState(issue, before, linear.claimedState, 'claim');
      if (after.status !== linear.claimedState || !after.labels?.includes(linear.claimLabel)) throw new Error('Forge Linear claim did not verify');
      return after;
    },
    async release(issue, targetState, message, verifyCurrent) {
      const before = await readIssue(issue);
      if (!before.labels?.includes(linear.claimLabel) || (verifyCurrent && !verifyCurrent(before))) return false;
      const state = before.assigneeId || before.status !== linear.claimedState ? before.status : targetState;
      const after = await writeState(issue, before, state, 'release');
      if (after.status !== state || after.labels?.includes(linear.claimLabel)) return false;
      const comment = await call('save_comment', { issueId: issue.uuid, body: message });
      return Boolean(comment.id);
    },
  };
}
