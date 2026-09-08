// Render an arbitrary HTML body (flow diagram / typeset card) to a 1600x1000 PNG.
// Usage: node render-html.mjs <out.png> <html-file>
// The body gets the house dark frame plus .kicker / .footer / .bar helpers; author the flow diagram as plain HTML or inline SVG.
import { chromium } from 'playwright';
import fs from 'node:fs';
const [out, htmlFile] = process.argv.slice(2);
if (!out || !htmlFile) { console.error('usage: node render-html.mjs <out.png> <html-file>'); process.exit(2); }
const body = fs.readFileSync(htmlFile, 'utf8');
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:1600px;height:1000px;background:#0d1017;color:#e8ecf3;font-family:"Segoe UI Variable Display","Segoe UI",Inter,system-ui,sans-serif;overflow:hidden}
.kicker{font-size:22px;letter-spacing:.18em;text-transform:uppercase;color:#5aa9ff;font-weight:600}
.footer{position:absolute;left:120px;right:120px;bottom:60px;font-size:20px;color:#7d879a;border-top:1px solid #222a37;padding-top:18px;display:flex;justify-content:space-between}
.bar{position:absolute;left:0;top:0;bottom:0;width:10px;background:#5aa9ff}
</style></head><body>${body}</body></html>`;
const br = await chromium.launch(); const p = await br.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
await p.setContent(html); await p.waitForTimeout(150); await p.screenshot({ path: out }); await br.close();
console.log(JSON.stringify({ ok: true, out }));
