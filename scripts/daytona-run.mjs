#!/usr/bin/env node
// Run one command on a disposable Daytona v2 Linux sandbox, on the exact committed revision of a repository.
//   node scripts/daytona-run.mjs --owner <project> [--repo <path>] [--cpu 8] [--memory 16] [--disk 40] [--minutes 60]
//                                [--put <local>=<remote>]... [--get <remote>=<local>]... [--script <file>] [-- <command>]
// The repository is sent as a git bundle of HEAD and checked out at /work/repo; uncommitted changes are not sent.
// The box has a hard lifetime and is deleted when the command ends, whatever the outcome. Exit code is the command's.
// Linux only. macOS needs Daytona v2 and a paid 24-hour Mac reservation, so this script never creates one.
// The key is read from DAYTONA_API_KEY and never printed. The SDK is installed on first use outside the repository.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const SDK = '2.2.0';
export const MAX = { cpu: 32, memory: 128, disk: 512, minutes: 720 };

export function parseArgs(argv) {
  const cut = argv.indexOf('--');
  const head = cut < 0 ? argv : argv.slice(0, cut);
  const o = { repo: '.', cpu: 8, memory: 16, disk: 40, minutes: 60, put: [], get: [], command: cut < 0 ? '' : argv.slice(cut + 1).join(' ') };
  for (let i = 0; i < head.length; i += 2) {
    const key = head[i].replace(/^--/, '');
    const value = head[i + 1];
    if (!head[i].startsWith('--') || value === undefined) throw new Error(`unexpected argument ${head[i]}`);
    if (key === 'put' || key === 'get') {
      const at = value.lastIndexOf('=');
      if (at < 1 || at === value.length - 1) throw new Error(`--${key} needs <from>=<to>`);
      o[key].push([value.slice(0, at), value.slice(at + 1)]);
    } else if (key in MAX) {
      const n = Number(value);
      if (!(n > 0) || n > MAX[key]) throw new Error(`--${key} must be above 0 and at most ${MAX[key]}`);
      o[key] = n;
    } else if (['owner', 'repo', 'image', 'script'].includes(key)) o[key] = value;
    else throw new Error(`unknown option --${key}`);
  }
  if (!/^[a-z0-9][a-z0-9-]*$/.test(o.owner || '')) throw new Error('--owner <project> is required (lower case, digits, hyphens): every box is labelled with who it is for');
  if (o.script && o.command.trim()) throw new Error('give --script or a command after --, not both');
  if (!o.script && !o.command.trim()) throw new Error('no command: put it after --, or use --script <file>');
  return o;
}

/** The image name carries the Dockerfile's hash, so an edited Dockerfile builds a new image and an unchanged one is reused. */
export const imageName = (dockerfile) => `agenthub-work-${createHash('sha256').update(dockerfile.replace(/\r\n/g, '\n')).digest('hex').slice(0, 12)}`;

function loadSdk() {
  let home = join(process.env.LOCALAPPDATA || tmpdir(), 'AgentHub');
  // The folder is a junction on the owner's PC, and a recursive mkdir through a junction fails there.
  if (existsSync(home)) home = realpathSync(home);
  const root = join(home, 'daytona', `sdk-${SDK}`);
  if (!existsSync(join(root, 'node_modules', '@daytona', 'sdk', 'package.json'))) {
    mkdirSync(root, { recursive: true });
    writeFileSync(join(root, 'package.json'), '{"private":true}\n');
    const npm = process.platform === 'win32' ? ['cmd.exe', ['/d', '/s', '/c', 'npm']] : ['npm', []];
    execFileSync(npm[0], [...npm[1], 'install', '--no-audit', '--no-fund', '--silent', `@daytona/sdk@${SDK}`], { cwd: root, stdio: ['ignore', 'ignore', 'inherit'], windowsHide: true });
  }
  const require = createRequire(pathToFileURL(join(root, 'package.json')));
  return { Daytona: require('@daytona/sdk').Daytona, ImageBuilder: require('@daytona/sdk/v2').ImageBuilder };
}

async function ensureImage(v2, ImageBuilder, say) {
  const dockerfile = readFileSync(join(here, '..', 'ci', 'daytona', 'Dockerfile'), 'utf8').replace(/\r\n/g, '\n');
  const name = imageName(dockerfile);
  let image = null;
  try { image = await v2.images.get(name); } catch (e) { if (e?.statusCode !== 404 && !/not.?found/i.test(`${e?.name} ${e?.message}`)) throw e; }
  if (!image) { say(`building image ${name}`); image = await v2.images.build(ImageBuilder.fromDockerfile(dockerfile), { name }); }
  while (image.status !== 'ready' && image.status !== 'failed') { await new Promise((r) => setTimeout(r, 5000)); image = await v2.images.get(image.id); }
  if (image.status === 'failed') throw new Error(`image ${name} failed: ${image.error ?? 'no reason given'}`);
  return name;
}

const quote = (s) => `'${s.split("'").join("'\"'\"'")}'`;

export async function main(argv) {
  const o = parseArgs(argv);
  if (!process.env.DAYTONA_API_KEY) throw new Error('DAYTONA_API_KEY is not set');
  const started = Date.now();
  const say = (m) => process.stderr.write(`[daytona ${Math.round((Date.now() - started) / 1000)}s] ${m}\n`);
  const repo = resolve(o.repo);
  const git = (...a) => execFileSync('git', ['-C', repo, ...a], { encoding: 'utf8', windowsHide: true }).trim();
  const revision = git('rev-parse', 'HEAD');
  if (git('status', '--porcelain')) say('the working tree has uncommitted changes; they are NOT sent');
  const command = (o.script ? readFileSync(resolve(o.script), 'utf8') : o.command).replace(/\r\n/g, '\n');
  const tmp = mkdtempSync(join(tmpdir(), 'daytona-run-'));
  let daytona;
  let box;
  let code = null;
  try {
    git('bundle', 'create', '-q', join(tmp, 'src.bundle'), 'HEAD');
    const { Daytona, ImageBuilder } = loadSdk();
    daytona = new Daytona();
    const image = o.image || await ensureImage(daytona.v2, ImageBuilder, say);
    const run = `${o.owner}-${started.toString(36)}`;
    box = await daytona.v2.create(image, { resources: { cpu: o.cpu, memory: o.memory, disk: o.disk }, lifecyclePolicy: { timeoutSeconds: Math.round(o.minutes * 60), onTimeout: 'delete' }, labels: { owner: o.owner, run }, waitSeconds: 300 });
    if (box.state !== 'started') await box.wait();
    say(`box ${box.id}, run ${run}, ${o.cpu} cores, ${o.memory} GiB, hard limit ${o.minutes} min, revision ${revision.slice(0, 12)}`);
    await box.process.run('mkdir -p /work');
    await box.fs.uploadFile(join(tmp, 'src.bundle'), '/work/src.bundle');
    for (const [from, to] of o.put) await box.fs.uploadFile(resolve(from), to);
    const setup = await box.process.run(`git config --global user.email ci@example.invalid && git config --global user.name ci && git config --global init.defaultBranch main && git clone -q /work/src.bundle /work/repo 2>/dev/null && git -C /work/repo checkout -q -B run ${revision} && git -C /work/repo rev-parse HEAD`);
    if (setup.exitCode !== 0 || setup.stdout.trim().split('\n').pop() !== revision) throw new Error(`checkout failed: ${setup.stderr || setup.stdout}`);
    writeFileSync(join(tmp, 'cmd.sh'), `cd /work/repo\n${command}\n`);
    await box.fs.uploadFile(join(tmp, 'cmd.sh'), '/work/cmd.sh');
    const handle = await box.process.start('bash /work/cmd.sh', { tag: 'run' });
    for await (const event of handle.streamLogs()) {
      if (event.type === 'log') (event.frame.channel === 'stderr' ? process.stderr : process.stdout).write(event.frame.data);
      if (event.type === 'state' && Number.isInteger(event.result?.exitCode)) code = event.result.exitCode;
    }
    if (code === null) { code = 1; say('the log stream ended without an exit code; treating the run as failed'); }
    for (const [from, to] of o.get) {
      const want = (await box.process.run(`sha256sum ${quote(from)}`)).stdout.split(' ')[0];
      const local = resolve(to);
      mkdirSync(dirname(local), { recursive: true });
      await box.fs.downloadFile(from, local);
      const got = createHash('sha256').update(readFileSync(local)).digest('hex');
      if (!want || got !== want) { code ||= 1; say(`${from}: the download does not match the box's hash`); } else say(`${local} ${got.slice(0, 12)}`);
    }
  } finally {
    if (box) { try { await daytona.v2.delete(box); say('box deleted'); } catch (e) { say(`box ${box.id} was not deleted (${e.message}); its hard limit removes it`); } }
    if (daytona) await daytona.close?.();
    rmSync(tmp, { recursive: true, force: true });
  }
  return code;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((c) => { process.exitCode = c; }, (e) => { process.stderr.write(`${e.message}\n`); process.exitCode = 2; });
}
