// Render a typeset card (title / end card / number card) to a 1600x1000 PNG with Playwright.
// compose-screencast.mjs calls this for any narration segment that has no clip.
// Usage: node render-card.mjs <out.png> '<json spec>'
// spec: { kicker, title, subtitle, lines: [..], footer, footerRight, accent }
import { chromium } from 'playwright';
import fs from 'node:fs';
const [out, specJson] = process.argv.slice(2);
if (!out || !specJson) { console.error("usage: node render-card.mjs <out.png> '<json spec>'"); process.exit(2); }
const s = JSON.parse(specJson);
const width = Number(s.width) || 1600;
const height = Number(s.height) || 1000;
if (!Number.isInteger(width) || !Number.isInteger(height) || width < 320 || height < 320) throw new Error('card frame must have valid dimensions');
const horizontal = width >= height;
const titleSize = Math.round(Math.min(horizontal ? 78 : 67, width * (horizontal ? .049 : .060)));
const esc = (t) => String(t ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:${width}px;height:${height}px;background:#0d1017;color:#e8ecf3;font-family:"Segoe UI Variable Display","Segoe UI",Inter,system-ui,sans-serif;overflow:hidden}
.wrap{position:absolute;inset:0;padding:${Math.round(height * .10)}px ${Math.round(width * .07)}px;box-sizing:border-box;display:flex;flex-direction:column;justify-content:center;gap:22px}
.kicker{font-size:22px;letter-spacing:.18em;text-transform:uppercase;color:${s.accent || '#5aa9ff'};font-weight:600}
.title{font-size:${s.title && s.title.length > 40 ? Math.round(titleSize * .82) : titleSize}px;font-weight:700;line-height:1.08;letter-spacing:-.01em;max-width:86vw}
.subtitle{font-size:${horizontal ? 32 : 28}px;color:#aeb7c7;font-weight:400;max-width:86vw;line-height:1.35}
.lines{margin-top:18px;font-size:26px;line-height:1.55;color:#c9d1de;font-family:Consolas,"Cascadia Mono",ui-monospace,monospace}
.footer{position:absolute;left:7%;right:7%;bottom:8%;font-size:20px;color:#7d879a;border-top:1px solid #222a37;padding-top:18px;display:flex;justify-content:space-between}
.bar{position:absolute;left:0;top:0;bottom:0;width:10px;background:${s.accent || '#5aa9ff'}}
</style></head><body><div class="bar"></div><div class="wrap">
${s.kicker ? `<div class="kicker">${esc(s.kicker)}</div>` : ''}
${s.title ? `<div class="title">${esc(s.title)}</div>` : ''}
${s.subtitle ? `<div class="subtitle">${esc(s.subtitle)}</div>` : ''}
${s.lines ? `<div class="lines">${s.lines.map((l) => esc(l)).join('<br>')}</div>` : ''}
</div>${s.footer ? `<div class="footer"><span>${esc(s.footer)}</span><span>${esc(s.footerRight || '')}</span></div>` : ''}</body></html>`;
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
await p.setContent(html); await p.waitForTimeout(150); await p.screenshot({ path: out }); await b.close();
console.log(JSON.stringify({ ok: true, out, bytes: fs.statSync(out).size }));
