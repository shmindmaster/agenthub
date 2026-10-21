// Frame layout per delivery ratio. Each ratio is captured natively at its own viewport, so the product picture fills
// the whole frame at scale 1.0: no UI band, no crop, no bars. Kinetic captions sit on their own plate over the picture
// inside the platform-safe area; the synthetic-data disclosure is an end-card line, never a chip on the product picture.
// Reels/Shorts reserve the top 14% and bottom 35% of a 9:16 frame for platform chrome, so captions stay out of it.
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

export const CTA_PILL_FONT = Object.freeze({ '16x9': 46, '4x5': 50, '9x16': 52 });

/** End-card disclosure line: about 2.8% of the frame width, so a landscape cut shown full width on a phone is as legible as
 *  the portrait cuts (at 16:9 the old 0.62 x pill size came out at 1.5% of the width). */
export const CTA_FOOT_FONT = Object.freeze({ '16x9': 54, '4x5': 31, '9x16': 32 });

/** Caption plate per ratio: one short line on 16:9, at most two on the portrait ratios, inside the safe area. */
const CAPTION = Object.freeze({
  '16x9': { x: 96, y: 924, w: 1728, h: 100, fontSize: 52, maxLines: 1 },
  '4x5': { x: 60, y: 1110, w: 960, h: 190, fontSize: 60, maxLines: 2 },
  '9x16': { x: 60, y: 1030, w: 960, h: 200, fontSize: 60, maxLines: 2 },
});

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
  const captionBox = { ...CAPTION[ratio] };
  return {
    ratio, frame, safe, zoom: 1,
    uiBand: { x: 0, y: 0, w: frame.width, h: frame.height },
    captionBox,
    // The end card block is centred in the safe area and shares the caption left edge.
    ctaBox: { x: captionBox.x, y: safe.y, w: frame.width - 2 * captionBox.x, h: safe.h },
    ctaPillFont: CTA_PILL_FONT[ratio],
    ctaFootFont: CTA_FOOT_FONT[ratio],
  };
}

/** Errors for a text-bearing box outside the platform-safe rectangle, or a product picture that does not fill the frame. */
export function safeZoneErrors(layout) {
  const errors = [];
  for (const name of ['captionBox', 'ctaBox']) {
    if (!inside(layout[name], layout.safe)) errors.push(`${layout.ratio}: ${name} leaves the platform-safe area`);
  }
  const band = layout.uiBand;
  if (band.x !== 0 || band.y !== 0 || band.w !== layout.frame.width || band.h !== layout.frame.height) errors.push(`${layout.ratio}: the product picture must fill the frame (no bars)`);
  return errors;
}
