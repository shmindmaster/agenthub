// Render a transparent 1600x1000 annotation overlay: dim everything except one or more boxes, outline them,
// add labels, arrows, and notes. The compositor applies it per segment via the manifest `overlay` hint.
// Usage: node render-overlay.mjs <out.png> '<json spec>'
// spec: { dim: 0.55, boxes: [{ x, y, w, h, label, labelPos: 'above'|'below'|'left'|'right', accent }],
//         arrows: [{ from:[x,y], to:[x,y], label, accent }], notes: [{ x, y, text, accent }] }
// Coordinates are in the 1600x1000 delivery frame (after the compositor's scale+pad), not the raw capture.
import { chromium } from 'playwright';
const [out, specJson] = process.argv.slice(2);
if (!out || !specJson) { console.error("usage: node render-overlay.mjs <out.png> '<json spec>'"); process.exit(2); }
const s = JSON.parse(specJson);
const esc = (t) => String(t ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const dim = s.dim ?? 0.55;
const accentDefault = s.accent || '#F5C518';
const boxes = (s.boxes || []).map((b, i) => {
  const acc = b.accent || accentDefault;
  const lp = b.labelPos || 'above';
  const pos = lp === 'above' ? `left:${b.x}px;top:${b.y - 46}px` : lp === 'below' ? `left:${b.x}px;top:${b.y + b.h + 10}px` : lp === 'left' ? `right:${1600 - b.x + 12}px;top:${b.y}px` : `left:${b.x + b.w + 12}px;top:${b.y}px`;
  // Only the first box carries the dim shadow; later boxes are outlines so several cutouts do not stack darkness.
  return `<div class="box" style="left:${b.x}px;top:${b.y}px;width:${b.w}px;height:${b.h}px;border-color:${acc};box-shadow:0 0 0 9999px rgba(8,10,16,${i === 0 ? dim : 0})"></div>` +
    (b.label ? `<div class="label" style="${pos};background:${acc}">${esc(b.label)}</div>` : '');
});
const arrows = (s.arrows || []).map((a) => `<line x1="${a.from[0]}" y1="${a.from[1]}" x2="${a.to[0]}" y2="${a.to[1]}" stroke="${a.accent || accentDefault}" stroke-width="5" marker-end="url(#ah)"/>` + (a.label ? `<text x="${(a.from[0] + a.to[0]) / 2}" y="${(a.from[1] + a.to[1]) / 2 - 14}" fill="#fff" font-size="26" font-weight="700" text-anchor="middle" style="paint-order:stroke;stroke:#0d1017;stroke-width:8px">${esc(a.label)}</text>` : ''));
const notes = (s.notes || []).map((n) => `<div class="note" style="left:${n.x}px;top:${n.y}px;border-color:${n.accent || accentDefault}">${esc(n.text)}</div>`);
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:1600px;height:1000px;background:transparent;overflow:hidden;font-family:"Segoe UI Variable Display","Segoe UI",Inter,system-ui,sans-serif}
.box{position:absolute;border:4px solid;border-radius:10px}
.label{position:absolute;color:#0d1017;font-size:22px;font-weight:700;padding:5px 12px;border-radius:8px;letter-spacing:.02em;white-space:nowrap}
.note{position:absolute;max-width:520px;background:rgba(13,16,23,.92);color:#fff;border-left:6px solid;padding:14px 18px;font-size:24px;line-height:1.35;border-radius:8px}
svg{position:absolute;inset:0;width:1600px;height:1000px;pointer-events:none}
</style></head><body>
${boxes.join('')}
<svg viewBox="0 0 1600 1000"><defs><marker id="ah" markerWidth="12" markerHeight="12" refX="9" refY="6" orient="auto"><path d="M0,0 L12,6 L0,12 z" fill="${accentDefault}"/></marker></defs>${arrows.join('')}</svg>
${notes.join('')}
</body></html>`;
const br = await chromium.launch(); const p = await br.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
await p.setContent(html); await p.waitForTimeout(100); await p.screenshot({ path: out, omitBackground: true }); await br.close();
console.log(JSON.stringify({ ok: true, out }));
