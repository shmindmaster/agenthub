// Minimal Azure Blob REST client shared by the local CLI and the cloud worker. No npm dependencies.
// Auth is a bearer token for https://storage.azure.com/ (Azure CLI locally, managed identity in the job);
// the storage account has shared-key access disabled, so there is no account key anywhere.
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const API = '2023-11-03';
const BLOCK = 8 * 1024 * 1024;
const SINGLE_PUT_MAX = 64 * 1024 * 1024;

export function blobClient(account, getToken) {
  const base = `https://${account}.blob.core.windows.net`;
  const url = (name) => `${base}/${name.split('/').map(encodeURIComponent).join('/')}`;

  async function req(method, name, { query = '', headers = {}, body, ok = [200, 201, 202, 206], retries = 4 } = {}) {
    for (let attempt = 0; ; attempt++) {
      let res;
      try {
        res = await fetch(url(name) + query, {
          method,
          body,
          duplex: body && typeof body.pipe === 'function' ? 'half' : undefined,
          headers: { Authorization: `Bearer ${await getToken()}`, 'x-ms-version': API, ...headers },
        });
      } catch (err) {
        if (attempt >= retries || (body && typeof body.pipe === 'function')) throw err;
        await new Promise((r) => setTimeout(r, 500 * 2 ** attempt));
        continue;
      }
      if (ok.includes(res.status) || (method === 'HEAD' && res.status === 404)) return res;
      const transient = res.status === 429 || res.status >= 500;
      if (transient && attempt < retries && !(body && typeof body.pipe === 'function')) {
        await res.arrayBuffer().catch(() => {});
        await new Promise((r) => setTimeout(r, 500 * 2 ** attempt));
        continue;
      }
      const text = await res.text().catch(() => '');
      throw new Error(`blob ${method} ${name}: HTTP ${res.status} ${text.slice(0, 300)}`);
    }
  }

  return {
    async exists(name) {
      return (await req('HEAD', name)).status === 200;
    },
    async putText(name, text, contentType = 'application/json') {
      await req('PUT', name, { headers: { 'x-ms-blob-type': 'BlockBlob', 'Content-Type': contentType }, body: Buffer.from(text) });
    },
    async getText(name) {
      const res = await req('GET', name, { ok: [200, 404] });
      return res.status === 404 ? null : res.text();
    },
    async putFile(name, file) {
      const size = fs.statSync(file).size;
      if (size <= SINGLE_PUT_MAX) {
        await req('PUT', name, { headers: { 'x-ms-blob-type': 'BlockBlob' }, body: fs.readFileSync(file) });
        return size;
      }
      const fd = fs.openSync(file, 'r');
      const ids = [];
      try {
        for (let off = 0, i = 0; off < size; off += BLOCK, i++) {
          const len = Math.min(BLOCK, size - off);
          const buf = Buffer.alloc(len);
          fs.readSync(fd, buf, 0, len, off);
          const id = Buffer.from(String(i).padStart(8, '0')).toString('base64');
          ids.push(id);
          await req('PUT', name, { query: `?comp=block&blockid=${encodeURIComponent(id)}`, body: buf });
        }
      } finally {
        fs.closeSync(fd);
      }
      const xml = `<?xml version="1.0" encoding="utf-8"?><BlockList>${ids.map((id) => `<Latest>${id}</Latest>`).join('')}</BlockList>`;
      await req('PUT', name, { query: '?comp=blocklist', headers: { 'Content-Type': 'application/xml' }, body: Buffer.from(xml) });
      return size;
    },
    async getFile(name, file) {
      const res = await req('GET', name);
      await pipeline(Readable.fromWeb(res.body), fs.createWriteStream(file));
      return fs.statSync(file).size;
    },
  };
}

/** Dependency fingerprint of a package-lock.json: the resolved tree only, so line endings and the kit's own version do not count. */
export function lockFingerprint(text) {
  const { packages = {} } = JSON.parse(text);
  const tree = Object.keys(packages).filter((k) => k).sort().map((k) => [k, packages[k].version, packages[k].integrity]);
  return createHash('sha256').update(JSON.stringify(tree)).digest('hex');
}

/** Run async fn over items with at most n in flight. */
export async function pool(items, n, fn) {
  const out = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(n, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        out[i] = await fn(items[i], i);
      }
    }),
  );
  return out;
}
