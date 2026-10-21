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

/** One line when it fits the box, otherwise two lines split at the " · " nearest the middle (the wording is unchanged). */
export function labelLines(label, fontSize, boxWidth) {
  const text = String(label);
  if (labelWidth(text, fontSize) <= boxWidth - 24) return [text];
  const parts = text.split(' · ');
  if (parts.length < 2) return [text];
  let best = 1;
  let bestGap = Infinity;
  for (let i = 1; i < parts.length; i++) {
    const left = `${parts.slice(0, i).join(' · ')} ·`;
    const gap = Math.abs(left.length - parts.slice(i).join(' · ').length);
    if (gap < bestGap) { bestGap = gap; best = i; }
  }
  return [`${parts.slice(0, best).join(' · ')} ·`, parts.slice(best).join(' · ')];
}

export const MIN_LABEL_FONT = Object.freeze({ '16x9': 34, '4x5': 36, '9x16': 36 });

/** Breathing room the review asked for: 16:9 label bottom margin, 4:5 and 9:16 label top offset (px). */
export const LABEL_MARGINS = Object.freeze({ '16x9': { bottom: 64 }, '4x5': { top: 54 }, '9x16': { top: 300 } });

export const CTA_PILL_FONT = Object.freeze({ '16x9': 46, '4x5': 50, '9x16': 52 });

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
    // The label gets its own row with >= 64 px under it, so the UI band is 836 px tall.
    layout = {
      uiBand: { x: 0, y: 0, w: 1920, h: 836 },
      captionBox: { x: 96, y: 852, w: 1728, h: 84, fontSize: 50, maxLines: 1 },
      labelBox: { x: 96, y: 946, w: 1000, h: 62, fontSize: 34 },
    };
  } else if (ratio === '4x5') {
    layout = {
      uiBand: { x: 0, y: 172, w: 1080, h: 740 },
      captionBox: { x: 60, y: 930, w: 960, h: 330, fontSize: 66, maxLines: 3 },
      labelBox: { x: 60, y: 54, w: 960, h: 104, fontSize: 36 },
    };
  } else {
    // Label (>= 300 px from the top) and captions sit above the picture so every text box stays inside the safe area;
    // the UI band takes the rest of the frame and may extend under the bottom platform chrome, but its focal centre
    // stays inside the safe area.
    layout = {
      uiBand: { x: 0, y: 676, w: 1080, h: 820 },
      captionBox: { x: 60, y: 424, w: 960, h: 230, fontSize: 62, maxLines: 3 },
      labelBox: { x: 60, y: 300, w: 960, h: 104, fontSize: 36 },
    };
  }
  // The end card block is centred in the safe area and shares the caption / label left edge.
  layout.ctaBox = { x: layout.captionBox.x, y: safe.y, w: frame.width - 2 * layout.captionBox.x, h: safe.h };
  layout.ctaPillFont = CTA_PILL_FONT[ratio];
  return { ratio, frame, safe, zoom: BASE_ZOOM[ratio], ...layout };
}

/** Errors for any text-bearing box outside the platform-safe rectangle (the UI band may bleed to the frame edge; in 9:16 its top and centre stay inside). */
export function safeZoneErrors(layout, label = 'SYNTHETIC DEMO · NO PHI · REAL PRODUCT') {
  const errors = [];
  const lb = layout.labelBox;
  if (lb.fontSize < MIN_LABEL_FONT[layout.ratio]) errors.push(`${layout.ratio}: label font ${lb.fontSize}px is below the ${MIN_LABEL_FONT[layout.ratio]}px legibility minimum`);
  const lines = labelLines(label, lb.fontSize, lb.w);
  if (lines.some((l) => labelWidth(l, lb.fontSize) > lb.w - 24)) errors.push(`${layout.ratio}: labelBox is too narrow for the label at ${lb.fontSize}px`);
  if (lines.length * lb.fontSize * 1.1 > lb.h) errors.push(`${layout.ratio}: labelBox is too short for ${lines.length} label line(s) at ${lb.fontSize}px`);
  const margins = LABEL_MARGINS[layout.ratio];
  if (margins.bottom !== undefined && layout.frame.height - (lb.y + lb.h) < margins.bottom) errors.push(`${layout.ratio}: label bottom margin is under ${margins.bottom}px`);
  if (margins.top !== undefined && lb.y < margins.top) errors.push(`${layout.ratio}: label top is above ${margins.top}px`);
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
