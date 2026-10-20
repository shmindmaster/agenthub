// Frame layout per delivery ratio. The captured UI sits in a "UI band" inside the platform-safe area and the kinetic
// captions, the persistent synthetic label and the CTA sit beside it, never over the focal point. Reels/Shorts
// reserve the top 14% and bottom 35% of a 9:16 frame for platform chrome, so nothing mvg draws goes there.
export const FRAMES = Object.freeze({
  '16x9': { width: 1920, height: 1080, profile: 'youtube-16x9' },
  '4x5': { width: 1080, height: 1350, profile: 'linkedin-4x5' },
  '9x16': { width: 1080, height: 1920, profile: 'vertical-9x16' },
});

export const DEFAULT_SAFE = Object.freeze({
  '16x9': { topPct: 0, bottomPct: 0, sidePct: 4 },
  '4x5': { topPct: 0, bottomPct: 0, sidePct: 4 },
  '9x16': { topPct: 14, bottomPct: 35, sidePct: 4 },
});

/** Base zoom of the UI crop per ratio: a portrait band shows a smaller slice of the screen so text stays readable. */
export const BASE_ZOOM = Object.freeze({ '16x9': 1.15, '4x5': 1.7, '9x16': 2.4 });

/** Rendered width of the persistent label: uppercase Geist 600 at 0.05em tracking is about 0.73 em per character. */
export function labelWidth(label, fontSize) {
  return Math.ceil(String(label).length * fontSize * 0.73);
}

export const MIN_LABEL_FONT = Object.freeze({ '16x9': 24, '4x5': 26, '9x16': 26 });

export function safeRect(ratio, brand) {
  const frame = FRAMES[ratio];
  const s = brand?.safeZones?.[ratio] || DEFAULT_SAFE[ratio];
  const top = Math.round((frame.height * s.topPct) / 100);
  const bottom = Math.round((frame.height * s.bottomPct) / 100);
  const side = Math.round((frame.width * s.sidePct) / 100);
  return { x: side, y: top, w: frame.width - 2 * side, h: frame.height - top - bottom, top, bottom, side };
}

const inside = (box, safe) => box.x >= safe.x && box.y >= safe.y && box.x + box.w <= safe.x + safe.w && box.y + box.h <= safe.y + safe.h;

export function layoutFor(ratio, brand) {
  const frame = FRAMES[ratio];
  if (!frame) throw new Error(`unknown ratio ${ratio}`);
  const safe = safeRect(ratio, brand);
  let layout;
  if (ratio === '16x9') {
    layout = {
      uiBand: { x: 0, y: 0, w: 1920, h: 896 },
      captionBox: { x: 96, y: 908, w: 1728, h: 90, fontSize: 50, maxLines: 1 },
      labelBox: { x: 96, y: 1008, w: 780, h: 52, fontSize: 24 },
    };
  } else if (ratio === '4x5') {
    layout = {
      uiBand: { x: 0, y: 92, w: 1080, h: 760 },
      captionBox: { x: 60, y: 884, w: 960, h: 330, fontSize: 66, maxLines: 3 },
      labelBox: { x: 60, y: 22, w: 960, h: 54, fontSize: 26 },
    };
  } else {
    // Captions sit above the picture so every text box stays inside the safe area; the UI band takes the rest of the
    // frame and may extend under the bottom platform chrome, but its focal centre stays inside the safe area. A
    // 610 px band left the UI a thin strip at 1.6x; this one shows it at about 2.2x.
    layout = {
      uiBand: { x: 0, y: 584, w: 1080, h: 900 },
      captionBox: { x: 60, y: 334, w: 960, h: 230, fontSize: 62, maxLines: 3 },
      labelBox: { x: 60, y: 272, w: 960, h: 50, fontSize: 26 },
    };
  }
  layout.ctaBox = { x: safe.x + 40, y: safe.y + Math.round(safe.h * 0.18), w: safe.w - 80, h: Math.round(safe.h * 0.6) };
  return { ratio, frame, safe, zoom: BASE_ZOOM[ratio], ...layout };
}

/** Errors for any text-bearing box outside the platform-safe rectangle (the UI band may bleed to the frame edge; in 9:16 its top and centre stay inside). */
export function safeZoneErrors(layout, label = 'SYNTHETIC DEMO · NO PHI · REAL PRODUCT') {
  const errors = [];
  const lb = layout.labelBox;
  if (lb.fontSize < MIN_LABEL_FONT[layout.ratio]) errors.push(`${layout.ratio}: label font ${lb.fontSize}px is below the ${MIN_LABEL_FONT[layout.ratio]}px legibility minimum`);
  if (labelWidth(label, lb.fontSize) > lb.w - 24) errors.push(`${layout.ratio}: labelBox is too narrow for the label at ${lb.fontSize}px`);
  for (const name of ['captionBox', 'labelBox', 'ctaBox']) {
    if (!inside(layout[name], layout.safe)) errors.push(`${layout.ratio}: ${name} leaves the platform-safe area`);
  }
  const band = layout.uiBand;
  if (layout.ratio === '9x16' && (band.y < layout.safe.y || band.y + band.h / 2 > layout.safe.y + layout.safe.h)) errors.push('9x16: uiBand starts or centres outside the platform-safe area');
  const clash = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
  for (const name of ['captionBox', 'labelBox']) if (clash(layout[name], band)) errors.push(`${layout.ratio}: ${name} overlaps the UI band`);
  if (clash(layout.captionBox, layout.labelBox)) errors.push(`${layout.ratio}: captionBox overlaps labelBox`);
  return errors;
}
