import assert from 'node:assert/strict';
import { existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { assertEvidenceCurrent, collect, command, inspect, loadManifest, remoteIdentity, validateRecord, writeReport } from './portfolio.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'portfolio-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const repo = join(root, 'app'); mkdirSync(repo);
  const git = (...args) => command('git', args, repo);
  git('init', '-b', 'main');
  writeFileSync(join(repo, 'package.json'), JSON.stringify({ engines: { node: '>=24' }, scripts: { test: 'node --test' } }));
  git('add', '.'); git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-m','fixture');
  git('remote','add','origin','git@github-shmindmaster:shmindmaster/app.git');
  const manifest = { schemaVersion: 1, fleetRoot: root, excluded: [{id:'portfolio-records'}], repos: [{id:'app',path:'app',remote:'shmindmaster/app',kind:'business',lifecycle:'pilot',tracker:'none',checks:[{check:'tenant-isolation',status:'not-run'}]}] };
  return { root, repo, git, manifest, head: git('rev-parse','HEAD') };
}
test('approved manifest includes 22 unique targets and excludes private evidence', () => {
  const m = loadManifest(); assert.equal(m.repos.length, 22); assert(!m.repos.some(r => r.id === 'portfolio-records'));
});
test('inventory stays honest about tests and missing indexes', t => {
  const f = fixture(t); const r = inspect(f.manifest,'app');
  assert.equal(r.status,'passed'); assert.equal(r.verification.status,'not-run'); assert.equal(r.repoWise.status,'blocked');
  assert.equal(r.packages[0].node,'>=24'); assert.equal(r.checks[0].status,'not-run');
});
test('wrong remote, missing checkout, excluded target, and unavailable executable fail visibly', t => {
  const f = fixture(t);
  f.git('remote','set-url','origin','git@github.com:someone/app.git');
  assert.equal(inspect(f.manifest,'app').status,'blocked');
  assert.throws(() => inspect(f.manifest,'portfolio-records'), /allowlist/);
  f.manifest.repos.push({...f.manifest.repos[0],id:'absent',path:'absent'});
  assert.equal(collect(f.manifest).repositories[1].status,'blocked');
  assert.throws(() => command('not-a-real-program-portfolio-fixture',[],f.root), /failed/);
});
test('raw credentials in remotes never reach the report', () => {
  assert.equal(remoteIdentity('https://token@github.com/shmindmaster/app.git'),'shmindmaster/app');
  assert.equal(remoteIdentity('https://token@elsewhere.invalid/private'),null);
  assert.equal(remoteIdentity('https://evilgithub.com/shmindmaster/app.git'),null);
});
test('stale SHA, changed branch and dirty work cannot validate HEAD-only evidence', t => {
  const f = fixture(t);
  const r = {schemaVersion:1,recordType:'execution',repo:'app',head:f.head,branch:'main',status:'passed',stage:'local',commands:[{command:'test',exitCode:0,finishedAt:new Date().toISOString()}],review:{status:'passed'},rollback:'reverse diff'};
  assert.equal(assertEvidenceCurrent(r,f.manifest),true);
  assert.throws(() => assertEvidenceCurrent({...r,head:'a'.repeat(40)},f.manifest), /Stale/);
  assert.throws(() => assertEvidenceCurrent({...r,branch:'other'},f.manifest), /Stale/);
  writeFileSync(join(f.repo,'untracked.txt'),'new');
  assert.throws(() => assertEvidenceCurrent(r,f.manifest), /Uncommitted/);
});
test('a skipped or failed command and absent independent review cannot claim pass', t => {
  const f=fixture(t); const r={schemaVersion:1,recordType:'execution',repo:'app',head:f.head,branch:'main',status:'passed',stage:'local',commands:[],review:{status:'not-run'},rollback:'reverse diff'};
  assert.throws(()=>validateRecord(r), /requires/);
  assert.throws(()=>validateRecord({...r,commands:[{command:'test',exitCode:1,finishedAt:'now'}],review:{status:'passed'}}), /requires/);
});
test('reports refuse repository destinations', t => {
  const f=fixture(t); assert.throws(()=>writeReport(collect(f.manifest),f.repo), /outside repositories/);
  const nested=join(f.repo,'new-report');
  assert.throws(()=>writeReport(collect(f.manifest),nested), /outside repositories/);
  assert.equal(existsSync(nested),false);
});

test('unsupported origin cannot impersonate a local-only repository', t => {
  const f=fixture(t); f.manifest.repos[0].remote=null;
  f.git('remote','set-url','origin','https://client.invalid/private/project.git');
  assert.equal(inspect(f.manifest,'app').status,'blocked');
  f.git('remote','remove','origin');
  assert.equal(inspect(f.manifest,'app').status,'passed');
});

test('manifest directory junction cannot read outside the approved repository', t => {
  const f=fixture(t);
  const privateRoot=join(f.root,'portfolio-records'); mkdirSync(privateRoot);
  writeFileSync(join(privateRoot,'package.json'),JSON.stringify({scripts:{private:'do not read'}}));
  const link=join(f.repo,'linked'); symlinkSync(privateRoot,link,process.platform==='win32'?'junction':'dir');
  // A previously tracked directory can be replaced by a junction in a dirty checkout.
  const blob=f.git('hash-object','-w',join(privateRoot,'package.json'));
  f.git('update-index','--add','--cacheinfo',`100644,${blob},linked/package.json`);
  const result=inspect(f.manifest,'app');
  assert.equal(result.packages.find(p=>p.path==='linked/package.json').status,'blocked');
  assert(!JSON.stringify(result).includes('do not read'));
});

test('report destination fails closed when git is unavailable', t => {
  const f=fixture(t); const report=collect(f.manifest);
  const old=process.env.PATH;
  try {
    process.env.PATH='';
    assert.throws(()=>writeReport(report,join(f.root,'report')),/Cannot establish/);
    assert(!existsSync(join(f.root,'report')));
  } finally {process.env.PATH=old;}
});

test('report refuses final-file links and never overwrites linked source', t => {
  const f=fixture(t); const output=join(f.root,'report'); mkdirSync(output);
  const source=join(f.repo,'README.md'); writeFileSync(source,'preserve this source');
  linkSync(source,join(output,'README.md'));
  assert.throws(()=>writeReport(collect(f.manifest),output),/unlinked file/);
  assert.equal(readFileSync(source,'utf8'),'preserve this source');
});
