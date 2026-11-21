import assert from 'node:assert/strict';
import test from 'node:test';
import { connectForgeLinear } from '../skills/dispatch/forge-linear.mjs';

const linear = {
  server: 'linear_example', mcpUrl: 'https://mcp.linear.app/mcp', teamKey: 'CORE',
  teamId: '11111111-1111-4111-8111-111111111111', projectId: '22222222-2222-4222-8222-222222222222',
  claimLabel: 'agent:forge', claimedState: 'In Progress',
};
const issue = { issue: 'CORE-83', uuid: '33333333-3333-4333-8333-333333333333' };

function fixture({ itemFields, teamFields, loseWriteResponse = false } = {}) {
  const requests = [];
  const item = { id: issue.issue, uuid: issue.uuid, teamId: linear.teamId, projectId: linear.projectId,
    status: 'Ready', labels: ['app:agenthub', 'Maintenance'], ...itemFields };
  const fetchImpl = async (url, options) => {
    assert.equal(url, linear.mcpUrl);
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, 'Bearer fixture-token');
    const { method, id, params } = JSON.parse(options.body);
    if (method === 'initialize') {
      return new Response(JSON.stringify({ jsonrpc: '2.0', id, result: { protocolVersion: '2025-06-18' } }), {
        headers: { 'Mcp-Session-Id': 'fixture-session', 'Content-Type': 'application/json' },
      });
    }
    assert.equal(options.headers['Mcp-Session-Id'], 'fixture-session');
    if (method === 'notifications/initialized') return new Response(null, { status: 202 });
    const { name, arguments: args } = params;
    requests.push([name, args]);
    let data;
    if (name === 'get_team') data = { id: linear.teamId, key: linear.teamKey, ...teamFields };
    if (name === 'get_issue') data = item;
    if (name === 'save_issue') {
      item.status = args.state;
      item.labels = [...item.labels, ...(args.addLabels ?? [])].filter((label) => !args.removeLabels?.includes(label));
      data = item;
      if (loseWriteResponse) throw new Error('test transport closed');
    }
    if (name === 'save_comment') data = { id: 'fixture-comment' };
    assert.ok(data, name);
    const result = { content: [{ type: 'text', text: JSON.stringify(data) }] };
    return new Response(`event: message\ndata: ${JSON.stringify({ jsonrpc: '2.0', id, result })}\n\n`, {
      headers: { 'Content-Type': 'text/event-stream' },
    });
  };
  const readFile = () => JSON.stringify({
    expected: { server_name: linear.server, server_url: linear.mcpUrl, access_token: 'fixture-token' },
    unrelated: { server_name: 'linear', server_url: linear.mcpUrl, access_token: 'other-fixture-token' },
  });
  return { requests, item, connect: () => connectForgeLinear(linear, '/runner', { fetchImpl, readFile }) };
}

test('claim and close-out send only the verified UUID and intended fields', async () => {
  const { connect, requests, item } = fixture();
  const client = await connect();
  await client.claim(issue, (before) => before.status === 'Ready');
  assert.equal(item.status, 'In Progress');
  assert.equal(await client.release(issue, 'In Review', 'Draft ready for review.'), true);
  assert.equal(item.status, 'In Review');
  assert.deepEqual(requests.filter(([name]) => name.startsWith('save_')), [
    ['save_issue', { id: issue.uuid, state: 'In Progress', addLabels: [linear.claimLabel] }],
    ['save_issue', { id: issue.uuid, state: 'In Review', removeLabels: [linear.claimLabel] }],
    ['save_comment', { issueId: issue.uuid, body: 'Draft ready for review.' }],
  ]);
});

test('the native client rejects the wrong workspace, different project and stale candidate before writing', async () => {
  const otherTeam = fixture({ teamFields: { key: 'OTHER' } });
  await assert.rejects(otherTeam.connect(), /configured team/);
  const otherProject = fixture({ itemFields: { projectId: 'other' } });
  const projectClient = await otherProject.connect();
  await assert.rejects(projectClient.claim(issue, () => true), /outside the configured/);
  await assert.rejects(projectClient.release(issue, 'Ready', 'Release'), /outside the configured/);
  const changed = fixture({ itemFields: { status: 'Done' } });
  const changedClient = await changed.connect();
  await assert.rejects(changedClient.claim(issue, (before) => before.status === 'Ready'), /no longer eligible/);
  for (const { requests } of [otherTeam, otherProject, changed]) assert.ok(requests.every(([name]) => !name.startsWith('save_')));
});

test('a lost mutation response is reconciled by reading the issue without issuing a duplicate write', async () => {
  const { connect, requests } = fixture({ loseWriteResponse: true });
  const client = await connect();
  const item = await client.claim(issue, (before) => before.status === 'Ready');
  assert.equal(item.status, 'In Progress');
  assert.equal(requests.filter(([name]) => name === 'save_issue').length, 1);
  assert.equal(requests.filter(([name]) => name === 'get_issue').length, 2);
});
