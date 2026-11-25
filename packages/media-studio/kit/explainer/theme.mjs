/**
 * Theme access for Node-side checks (grammar, layout, gates, tests).
 *
 * The tokens themselves live in theme.json so the Remotion components
 * (`import theme from "./theme.json"`) and the Node tooling read one source.
 * Nothing here paints; it only resolves names to values.
 */
import themeData from './theme.json' with { type: 'json' };

export const theme = themeData;

/** Resolve a palette name (`accent`) or pass a literal (`#F5C518`) through. */
export const color = (name) => {
  if (typeof name !== 'string') throw new Error('color name must be a string');
  if (name.startsWith('#')) return name;
  const value = theme.color[name];
  if (!value) throw new Error(`unknown colour token "${name}"`);
  return value;
};

/** `tone("risk")` -> "#E85D5D"; `tone(undefined)` -> ink. */
export const tone = (name = 'default') => {
  const key = theme.tone[name] ?? name;
  return color(key);
};

export const canvas = theme.canvas;
export const type = theme.type;
export const space = theme.space;
