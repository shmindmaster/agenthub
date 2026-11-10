// A product's standing policy, merged under its brand file.
//
// Rules that belong to one product (an industry claim policy, a required
// disclosure line, other names the product goes by) live in
// product-profiles.json, keyed by product, so they hold for every job folder
// without each brand file repeating them. A brand file can add to a profile;
// it cannot loosen it.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const clean = (v) => String(v || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const union = (...lists) => [...new Set(lists.flatMap((l) => l || []))];

let cached = null;
export function loadProfiles(path = join(here, '..', 'product-profiles.json')) {
  if (path === join(here, '..', 'product-profiles.json') && cached) return cached;
  let parsed = { profiles: {} };
  try { parsed = JSON.parse(readFileSync(path, 'utf8')); } catch { parsed = { profiles: {} }; }
  if (path === join(here, '..', 'product-profiles.json')) cached = parsed;
  return parsed;
}

/** The profile for a product name or brand id, or null. */
export function productProfile(product, brandId, profiles = loadProfiles()) {
  const wanted = [clean(product), clean(brandId)].filter(Boolean);
  for (const [id, profile] of Object.entries(profiles.profiles || {})) {
    const keys = [id, ...(profile.match || [])].map(clean);
    if (wanted.some((w) => keys.includes(w))) return { id, ...profile };
  }
  return null;
}

/**
 * The brand file as the kit should read it: the product's profile underneath,
 * the brand file's own values on top, restrictive fields combined.
 * Idempotent, and returns the brand unchanged when the product has no profile.
 */
export function withProductProfile(brand, spec, profiles = loadProfiles()) {
  const profile = productProfile(spec?.product || brand?.product, brand?.id, profiles);
  if (!profile) return brand;
  const merged = { ...(brand || {}) };
  const names = union(profile.productNames, brand?.productNames);
  if (names.length) merged.productNames = names;
  const policies = union(profile.claimPolicies, brand?.claimPolicies);
  if (policies.length) merged.claimPolicies = policies;
  if (profile.disclosure || brand?.disclosure) {
    merged.disclosure = {
      ...(brand?.disclosure || {}),
      required: Boolean(profile.disclosure?.required || brand?.disclosure?.required),
      mustInclude: union(profile.disclosure?.mustInclude, brand?.disclosure?.mustInclude),
    };
  }
  // The stricter people policy wins.
  const strictness = { any: 0, 'adults-only': 1, none: 2 };
  const people = [profile.generatedPeople, brand?.generatedPeople].filter(Boolean).sort((a, b) => strictness[b] - strictness[a])[0];
  if (people) merged.generatedPeople = people;
  return merged;
}
