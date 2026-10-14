import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

const fixture = mkdtempSync(join(tmpdir(), 'agenthub-appium-demand-'));
const home = join(fixture, 'home');
const stubs = join(fixture, 'stubs');
const log = join(home, 'calls.log');
const legacy = join(home, 'Library', 'LaunchAgents');
const script = resolve('packages/mobile-development/skills/mobile-device-lab/scripts/guest/start-appium-guest.sh');
const bash = 'C:/Program Files/Git/bin/bash.exe';
try {
  mkdirSync(legacy, {recursive: true});
  mkdirSync(join(home, 'mobile-lab'), {recursive: true});
  mkdirSync(stubs);
  writeFileSync(join(home, 'mobile-lab', 'mobile-development.env'), 'APPIUM_PORT=4723\nAPPIUM_BIND_ADDRESS=0.0.0.0\n');
  writeFileSync(join(legacy, 'dev.shmindmaster.appium.plist'), 'old auto-loaded job');
  writeFileSync(join(legacy, 'unrelated.plist'), 'preserve');
  writeFileSync(join(stubs, 'appium'), '#!/bin/bash\nexit 0\n');
  writeFileSync(join(stubs, 'launchctl'), '#!/bin/bash\nprintf "%s\\n" "$*" >> "$HOME/calls.log"\nif [ "$1" = bootstrap ] && [ -f "$HOME/bootstrap-fails" ]; then exit 5; fi\n');
  writeFileSync(join(stubs, 'sleep'), '#!/bin/bash\nexit 0\n');
  const run = () => spawnSync(bash, ['-c', 'export HOME="$(cygpath -u "$DEMAND_HOME")"; export PATH="$(cygpath -u "$DEMAND_STUBS"):$PATH"; bash "$(cygpath -u "$DEMAND_SCRIPT")"'], {
    env: {...process.env, DEMAND_HOME: home, DEMAND_STUBS: stubs, DEMAND_SCRIPT: script}, encoding: 'utf8', windowsHide: true, timeout: 120000,
  });
  let result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(join(legacy, 'dev.shmindmaster.appium.plist')), false);
  assert.equal(readFileSync(join(legacy, 'unrelated.plist'), 'utf8'), 'preserve');
  const plist = readFileSync(join(home, 'mobile-lab', 'state', 'dev.shmindmaster.appium.plist'), 'utf8');
  assert.match(plist, /<key>RunAtLoad<\/key><false\/>/);
  assert.match(plist, /<key>KeepAlive<\/key><false\/>/);
  let calls = readFileSync(log, 'utf8').trim().split('\n');
  assert.deepEqual(calls.map(line => line.split(' ')[0]), ['bootout', 'bootstrap', 'enable', 'kickstart']);
  assert.ok(!calls[1].includes('LaunchAgents'));
  console.log('PASS: only explicit invocation starts Appium; legacy auto-start removed and unrelated job preserved');
  result = run();
  assert.equal(result.status, 0, result.stderr);
  calls = readFileSync(log, 'utf8').trim().split('\n');
  assert.equal(calls.filter(line => line.startsWith('kickstart ')).length, 2);
  console.log('PASS: repeated demand replaces the job without introducing an automatic restart');
  writeFileSync(log, '');
  writeFileSync(join(home, 'bootstrap-fails'), '');
  result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap did not succeed/);
  assert.equal(readFileSync(log, 'utf8').includes('kickstart'), false);
  console.log('PASS: failed load refuses to report or attempt a successful start');
} finally {
  assert.ok(resolve(fixture).startsWith(resolve(tmpdir()) + '\\'));
  rmSync(fixture, {recursive: true, force: true});
}
