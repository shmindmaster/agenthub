// Cloud entry for one chunk of a split Remotion render:
//   node cloud/chunk-render.mjs <index> <count> <compositionId> <out.mp4> [remotion render flags...]
// Reads the composition's length through the Remotion CLI (so the kit's own remotion.config.ts applies), then renders
// frames [index*size, min(total, (index+1)*size) - 1]. cloud-render.mjs joins the chunks with a stream-copy concat.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';

const [indexArg, countArg, comp, out, ...flags] = process.argv.slice(2);
const index = Number(indexArg), count = Number(countArg);
if (!comp || !out || !(count > 0) || !(index >= 0 && index < count)) {
  console.error('usage: chunk-render.mjs <index> <count> <compositionId> <out.mp4> [remotion render flags...]');
  process.exit(2);
}
const cli = 'node_modules/@remotion/cli/remotion-cli.js';
// Only the flags that change what the composition is (props, public dir, config, env) go to the length probe.
const probeFlags = flags.filter((f) => /^--(props|public-dir|config|env-file)=/.test(f));
const probe = spawnSync('node', [cli, 'compositions', 'src/index.ts', ...probeFlags], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const row = String(probe.stdout).split('\n').map((l) => l.trim().split(/\s+/)).find((cols) => cols[0] === comp && /^\d+x\d+$/.test(cols[2] || ''));
const total = row ? Number(row[3]) : NaN;
if (!Number.isInteger(total) || total <= 0) {
  console.error(`could not read the length of composition ${comp}:\n${String(probe.stdout).slice(-1500)}\n${String(probe.stderr).slice(-1500)}`);
  process.exit(1);
}
const size = Math.ceil(total / count);
const first = index * size;
const last = Math.min(total, first + size) - 1;
console.log(`chunk ${index + 1}/${count}: frames ${first}-${last} of ${total}`);
fs.writeFileSync(`${out}.range.json`, JSON.stringify({ index, count, total, first, last }));
if (first > last) process.exit(0); // more chunks than frames: this one has nothing to render
const render = spawnSync('node', [cli, 'render', 'src/index.ts', comp, out, `--frames=${first}-${last}`, ...flags], { stdio: 'inherit' });
process.exit(render.status ?? 1);
