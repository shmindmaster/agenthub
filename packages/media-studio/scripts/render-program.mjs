#!/usr/bin/env node
// The only Remotion entry for a film. Props are one argument. A picture that does not match the voice is deleted.
// Usage: node render-program.mjs --kit <dir> --composition <Name> --props <file> --out <file> --voice-seconds <n>
import { existsSync, readFileSync, statSync, unlinkSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { durationAgrees, DURATION_TOLERANCE, renderArgv } from './picture-gates.mjs';

const flag = (argv, name) => { const index = argv.indexOf(name); return index >= 0 ? argv[index + 1] : null; };

export function planRender(options) {
  const propsPath = options.propsPath;
  if (!propsPath || !existsSync(propsPath) || statSync(propsPath).size === 0) {
    throw new Error('Remotion props file is missing or empty');
  }
  JSON.parse(readFileSync(propsPath, 'utf8'));
  const extra = options.extra || ['--concurrency=4', '--gl=angle', '--x264-preset=veryfast', '--crf=18', '--pixel-format=yuv420p', '--muted'];
  return {
    cwd: options.kit,
    argv: renderArgv({ cli: options.cli, composition: options.composition, propsPath, outFile: options.outFile, extra }),
    voiceSeconds: options.voiceSeconds,
  };
}

function probeDuration(file) {
  const probe = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'json', file], { windowsHide: true, encoding: 'utf8' });
  if (probe.status !== 0) throw new Error(probe.stderr || 'ffprobe failed');
  return Number(JSON.parse(probe.stdout).format.duration);
}

function main() {
  const argv = process.argv.slice(2);
  const kit = flag(argv, '--kit');
  const composition = flag(argv, '--composition');
  const propsPath = flag(argv, '--props');
  const outFile = flag(argv, '--out');
  const voiceSeconds = Number(flag(argv, '--voice-seconds'));
  const cli = flag(argv, '--cli');
  if (!kit || !composition || !propsPath || !outFile || !cli) {
    console.error('Usage: node render-program.mjs --kit <dir> --composition <Name> --props <file> --out <file> --voice-seconds <n> --cli <remotion-cli.js>');
    process.exit(1);
  }
  let plan;
  try { plan = planRender({ kit, composition, propsPath: resolve(propsPath), outFile: resolve(outFile), voiceSeconds, cli }); }
  catch (error) { console.error(`[render-program] ${error.message}`); process.exit(1); }
  const node = process.execPath;
  const render = spawnSync(node, plan.argv, { cwd: kit, windowsHide: true, stdio: 'inherit' });
  if (render.status !== 0) process.exit(render.status || 1);
  const rendered = resolve(outFile);
  let pictureSeconds;
  try { pictureSeconds = probeDuration(rendered); }
  catch (error) { console.error(`[render-program] ${error.message}`); process.exit(1); }
  if (!durationAgrees(pictureSeconds, plan.voiceSeconds)) {
    if (existsSync(rendered)) unlinkSync(rendered);
    console.error(`[render-program] picture is ${pictureSeconds}s and the voice is ${voiceSeconds}s (tolerance ${DURATION_TOLERANCE}s); deleted ${outFile}`);
    process.exit(1);
  }
  console.log(JSON.stringify({ ok: true, seconds: pictureSeconds }));
}

const invoked = process.argv[1] && (isAbsolute(process.argv[1]) ? resolve(process.argv[1]) : resolve(process.argv[1])).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (invoked) main();
