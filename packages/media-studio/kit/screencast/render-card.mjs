// Render a typeset card (title / end card / number card) to a 1600x1000 PNG with Playwright.
// compose-screencast.mjs calls this for any narration segment that has no clip.
// Usage: node render-card.mjs <out.png> '<json spec>'
// spec: { kicker, title, subtitle, lines: [..], footer, footerRight, accent }
import { chromium } from 'playwright';
import fs from 'node:fs';
const [out, specJson] = process.argv.slice(2);
if (!out || !specJson) { console.error("usage: node render-card.mjs <out.png> '<json spec>'"); process.exit(2); }
const s = JSON.parse(specJson);
const esc = (t) => String(t ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:1600px;height:1000px;background:#0d1017;color:#e8ecf3;font-family:"Segoe UI Variable Display","Segoe UI",Inter,system-ui,sans-serif;overflow:hidden}
.wrap{position:absolute;inset:0;padding:110px 120px;box-sizing:border-box;display:flex;flex-direction:column;justify-content:center;gap:22px}
.kicker{font-size:22px;letter-spacing:.18em;text-transform:uppercase;color:${s.accent || '#5aa9ff'};font-weight:600}
.title{font-size:${s.title && s.title.length > 40 ? 64 : 78}px;font-weight:700;line-height:1.08;letter-spacing:-.01em;max-width:1300px}
.subtitle{font-size:32px;color:#aeb7c7;font-weight:400;max-width:1200px;line-height:1.35}
.lines{margin-top:18px;font-size:26px;line-height:1.55;color:#c9d1de;font-family:Consolas,"Cascadia Mono",ui-monospace,monospace}
.footer{position:absolute;left:120px;right:120px;bottom:70px;font-size:20px;color:#7d879a;border-top:1px solid #222a37;padding-top:18px;display:flex;justify-content:space-between}
.bar{position:absolute;left:0;top:0;bottom:0;width:10px;background:${s.accent || '#5aa9ff'}}
</style></head><body><div class="bar"></div><div class="wrap">
${s.kicker ? `<div class="kicker">${esc(s.kicker)}</div>` : ''}
${s.title ? `<div class="title">${esc(s.title)}</div>` : ''}
${s.subtitle ? `<div class="subtitle">${esc(s.subtitle)}</div>` : ''}
${s.lines ? `<div class="lines">${s.lines.map((l) => esc(l)).join('<br>')}</div>` : ''}
</div>${s.footer ? `<div class="footer"><span>${esc(s.footer)}</span><span>${esc(s.footerRight || '')}</span></div>` : ''}</body></html>`;
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
await p.setContent(html); await p.waitForTimeout(150); await p.screenshot({ path: out }); await b.close();
console.log(JSON.stringify({ ok: true, out, bytes: fs.statSync(out).size }));
