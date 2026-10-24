import test from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough, Writable } from 'node:stream';
import { EventEmitter } from 'node:events';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resumeDispatch, transportCommand } from '../skills/use-coding-agent/cline/acp-dispatch.mjs';

test('ACP transport keeps session and prompt out of command arguments', async () => {
  const methods = [];
  const child = new EventEmitter();
  child.stdout = new PassThrough(); child.stderr = new PassThrough();
  child.stdin = new Writable({ write(chunk, encoding, done) {
    const m = JSON.parse(chunk); methods.push(m);
    queueMicrotask(() => {
      const reply = value => child.stdout.write(JSON.stringify(value) + '\n');
      if (m.method === 'initialize') reply({ id: m.id, result: { agentCapabilities: { loadSession: true } } });
      if (m.method === 'session/load') reply({ id: m.id, result: {} });
      if (m.method === 'session/prompt') {
        reply({ method: 'session/update', params: { sessionId: 'synthetic', update: { sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'reply' } } } });
        reply({ id: m.id, result: { stopReason: 'end_turn' } });
      }
    }); done();
  } });
  let stopped = false;
  const result = await resumeDispatch({ executable: 'synthetic.exe', cwd: tmpdir(), sessionId: 'synthetic', prompt: 'quoted " task\nnext', timeoutMs: 1000 }, {
    spawnHost(file, args, options) {
      assert.equal(file, 'synthetic.exe'); assert.deepEqual(args, ['--acp', '--auto-approve', 'false']);
      assert.equal(options.windowsHide, true); assert.equal(options.shell, false); return child;
    }, stopHost: async value => { assert.equal(value, child); stopped = true; }
  });
  assert.equal(result.text, 'reply'); assert.equal(stopped, true);
  assert.deepEqual(methods.map(m => m.method), ['initialize', 'session/load', 'session/prompt']);
  assert.equal(methods[2].params.prompt[0].text, 'quoted " task\nnext');
});

test('batch transport permits spaces and rejects cmd expansion characters', () => {
  const command = transportCommand('C:\\synthetic path\\cline.cmd', 'win32');
  assert.equal(command.windowsVerbatimArguments, true);
  assert.equal(command.args[3], '""C:\\synthetic path\\cline.cmd" --acp --auto-approve false"');
  for (const value of ['C:\\%secret%\\cline.cmd', 'C:\\a&b\\cline.cmd', 'C:\\a!b\\cline.cmd']) assert.throws(() => transportCommand(value, 'win32'), /Unsafe/);
});

test('timeout attempts cleanup and cleanup failure cannot become success', async () => {
  for (const cleanupFails of [false, true]) {
    const child = new EventEmitter();
    child.stdout = new PassThrough(); child.stderr = new PassThrough();
    child.stdin = new Writable({ write(chunk, encoding, done) { done(); } });
    let stopped = false;
    await assert.rejects(resumeDispatch({ executable: 'synthetic.exe', cwd: tmpdir(), sessionId: 'synthetic', prompt: 'task', timeoutMs: 10 }, {
      spawnHost: () => child,
      stopHost: async () => { stopped = true; if (cleanupFails) throw new Error('synthetic cleanup failed'); }
    }), cleanupFails ? /synthetic cleanup failed/ : /ACP timeout/);
    assert.equal(stopped, true);
  }
});

test('dispatcher SessionId wiring and refusal use synthetic registry only', { skip: process.platform !== 'win32', timeout: 60000 }, () => {
  const root = mkdtempSync(join(tmpdir(), 'acp dispatch fixture '));
  const repo = fileURLToPath(new URL('../../../', import.meta.url));
  try {
    mkdirSync(join(root, 'registry')); mkdirSync(join(root, 'scripts/lib'), { recursive: true });
    copyFileSync(join(repo, 'scripts/lib/PathBinding.ps1'), join(root, 'scripts/lib/PathBinding.ps1'));
    const marker = join(root, 'launched');
    const fake = join(root, 'fake host.cmd');
    const responder = join(root, 'host.cjs');
    writeFileSync(responder, `const fs=require('node:fs'); fs.writeFileSync(${JSON.stringify(marker)},'yes'); const rl=require('node:readline').createInterface({input:process.stdin}); rl.on('line',line=>{ const m=JSON.parse(line); const send=x=>console.log(JSON.stringify(x)); if(m.method==='initialize')send({id:m.id,result:{agentCapabilities:{loadSession:true}}}); if(m.method==='session/load')send({id:m.id,result:{}}); if(m.method==='session/prompt'){send({method:'session/update',params:{sessionId:m.params.sessionId,update:{sessionUpdate:'agent_message_chunk',content:{type:'text',text:m.params.prompt[0].text}}}});send({id:m.id,result:{stopReason:'end_turn'}});} });`);
    writeFileSync(fake, `@echo off\r\n"${process.execPath}" "${responder}" %*\r\n`);
    writeFileSync(join(root, 'registry/agents.json'), JSON.stringify({ activeAgents: ['cline', 'codex'].map(id => ({ id, executable: fake })) }));
    const fleet = { autonomyProfiles: { profiles: [] }, hostSettings: {}, dispatchPolicy: {} };
    const save = () => writeFileSync(join(root, 'registry/fleet-profile.json'), JSON.stringify(fleet));
    const run = (host, extra = []) => spawnSync('pwsh', ['-NoProfile', '-File', resolve(repo, 'packages/coding-agent-dispatch/skills/use-coding-agent/Invoke-CodingAgent.ps1'), '-HostId', host, '-SessionId', 'synthetic', '-Prompt', 'synthetic "task"\nnext', '-Cwd', root, '-TimeoutSec', '15', ...extra], { encoding: 'utf8', windowsHide: true, timeout: 25000, env: { ...process.env, AGENTHUB_ROOT: root, LOCALAPPDATA: join(root, 'runtime') } });
    save();
    let result = run('cline');
    assert.equal(result.status, 0, result.stderr); assert.equal(JSON.parse(result.stdout).text, 'synthetic "task"\nnext');
    rmSync(marker);
    fleet.dispatchPolicy.cline = { enabled: false, reason: 'synthetic owner exclusion' }; save();
    result = run('cline'); assert.equal(result.status, 3); assert.match(result.stderr, /synthetic owner exclusion/);
    result = run('codex'); assert.equal(result.status, 3); assert.match(result.stderr, /requires -HostId cline/);
    assert.equal(existsSync(marker), false, 'refused calls must not launch the fixture');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

