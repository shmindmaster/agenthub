#!/usr/bin/env node
// Static server for the calibration fixtures. No dependencies — the fixture set
// has to run anywhere the plugin is installed, including a machine with no npm
// install in the consuming repo.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, extname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..', 'fixtures', 'worthiness', 'apps');
const PORT = Number(process.env.FIXTURE_PORT ?? 8977);
const TYPES = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript' };

createServer(async (req, res) => {
  let p = normalize(decodeURIComponent(req.url.split('?')[0])).replace(/^(\.\.[/\\])+/, '');
  if (p.endsWith('/')) p += 'index.html';
  try {
    const body = await readFile(join(ROOT, p));
    res.writeHead(200, {
      'Content-Type': TYPES[extname(p)] ?? 'application/octet-stream',
      // Fixtures must be byte-identical every walk, or `deterministic` is untestable.
      'Cache-Control': 'no-store',
    });
    res.end(body);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
  }
}).listen(PORT, () => {
  console.log(`fixtures on http://localhost:${PORT}/`);
  console.log('  clean-pass  dead-wait  illegible  unstable  no-hero');
});
