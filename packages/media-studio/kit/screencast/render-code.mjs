// Render a real source excerpt (line numbers, highlight bands) to a 1600x1000 PNG — the code-reveal card of a technical story.
// Usage: node render-code.mjs <out.png> '<json>'
// spec: { file (abs path, read-only), start, end, highlight: [[a,b],...], title, subtitle, footer, repo, commit, relPath }
// Keep start..end to the 5–20 lines that matter; one highlight band per card, one card per beat.
import { chromium } from 'playwright';
import fs from 'node:fs';
const [out, specJson] = process.argv.slice(2);
if (!out || !specJson) { console.error("usage: node render-code.mjs <out.png> '<json spec>'"); process.exit(2); }
const s = JSON.parse(specJson);
const lines = fs.readFileSync(s.file, 'utf8').split(/\r?\n/);
const a = Math.max(1, s.start), b = Math.min(lines.length, s.end);
const esc = (t) => String(t ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const inHl = (n) => (s.highlight || []).some(([x, y]) => n >= x && n <= y);
const rows = [];
for (let n = a; n <= b; n++) rows.push(`<div class="ln${inHl(n) ? ' hl' : ''}"><span class="no">${n}</span><span class="code">${esc(lines[n - 1]).replace(/ /g, '&nbsp;')}</span></div>`);
const fontSize = (b - a + 1) > 34 ? 17 : (b - a + 1) > 26 ? 20 : 22;
const provenance = [s.repo, s.commit].filter(Boolean).join(' ');
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:1600px;height:1000px;background:#0d1017;color:#dfe5ef;font-family:"Segoe UI Variable Display","Segoe UI",Inter,system-ui,sans-serif;overflow:hidden}
.top{position:absolute;left:70px;right:70px;top:44px;display:flex;justify-content:space-between;align-items:baseline}
.title{font-size:30px;font-weight:700}.sub{font-size:20px;color:#8f9bb0;font-family:Consolas,"Cascadia Mono",ui-monospace,monospace}
.pane{position:absolute;left:70px;right:70px;top:110px;bottom:80px;background:#11161f;border:1px solid #232b39;border-radius:10px;padding:22px 0;overflow:hidden}
.ln{display:flex;font-family:Consolas,"Cascadia Mono",ui-monospace,monospace;font-size:${fontSize}px;line-height:1.42;white-space:nowrap}
.no{width:78px;text-align:right;padding-right:22px;color:#4f5b70;flex:none}.code{color:#d8dee9}
.hl{background:rgba(245,197,24,.14);box-shadow:inset 4px 0 0 #F5C518}.hl .code{color:#fff}
.footer{position:absolute;left:70px;right:70px;bottom:34px;font-size:18px;color:#7d879a;display:flex;justify-content:space-between}
</style></head><body>
<div class="top"><div class="title">${esc(s.title || '')}</div><div class="sub">${esc(s.relPath || '')}</div></div>
<div class="pane">${rows.join('')}</div>
<div class="footer"><span>${esc(s.footer || '')}</span><span>${esc(provenance)}</span></div>
</body></html>`;
const br = await chromium.launch(); const p = await br.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
await p.setContent(html); await p.waitForTimeout(120); await p.screenshot({ path: out }); await br.close();
console.log(JSON.stringify({ ok: true, out, lines: [a, b] }));
