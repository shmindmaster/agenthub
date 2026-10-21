// Minimal JSON-Schema (draft-07 subset) validator so mvg needs no npm dependency.
// Supported: type (string|array), enum, const, required, properties, additionalProperties (false|schema),
// items, minItems, maxItems, uniqueItems, minLength, maxLength, minimum, maximum, pattern, oneOf, anyOf,
// $ref ("#/definitions/name"). Anything else in a schema is ignored, never silently trusted: the schemas in
// ./schemas are written within this subset and the tests exercise each keyword they use.

const typeOf = (v) => (v === null ? 'null' : Array.isArray(v) ? 'array' : Number.isInteger(v) ? 'integer' : typeof v);
const matchesType = (v, t) => (t === 'number' ? typeof v === 'number' && Number.isFinite(v) : typeOf(v) === t);

export function validate(schema, value, root = schema, path = '$') {
  const errors = [];
  const fail = (m) => errors.push(`${path}: ${m}`);
  if (schema.$ref) {
    const target = schema.$ref.replace(/^#\/definitions\//, '');
    const def = root.definitions?.[target];
    if (!def) { fail(`unresolved $ref ${schema.$ref}`); return errors; }
    return validate(def, value, root, path);
  }
  if (schema.type) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => matchesType(value, t))) { fail(`expected ${types.join('|')}, got ${typeOf(value)}`); return errors; }
  }
  if (schema.const !== undefined && value !== schema.const) fail(`must equal ${JSON.stringify(schema.const)}`);
  if (schema.enum && !schema.enum.includes(value)) fail(`must be one of ${schema.enum.join(', ')}`);
  if (typeof value === 'string') {
    if (schema.minLength !== undefined && value.length < schema.minLength) fail(`shorter than ${schema.minLength}`);
    if (schema.maxLength !== undefined && value.length > schema.maxLength) fail(`longer than ${schema.maxLength}`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) fail(`does not match ${schema.pattern}`);
  }
  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) fail(`below minimum ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) fail(`above maximum ${schema.maximum}`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) fail(`needs at least ${schema.minItems} items`);
    if (schema.maxItems !== undefined && value.length > schema.maxItems) fail(`allows at most ${schema.maxItems} items`);
    if (schema.uniqueItems && new Set(value.map((v) => JSON.stringify(v))).size !== value.length) fail('items must be unique');
    if (schema.items) value.forEach((item, i) => errors.push(...validate(schema.items, item, root, `${path}[${i}]`)));
  }
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    for (const key of schema.required || []) if (!(key in value)) fail(`missing required property "${key}"`);
    const props = schema.properties || {};
    for (const [key, sub] of Object.entries(props)) if (key in value) errors.push(...validate(sub, value[key], root, `${path}.${key}`));
    if (schema.additionalProperties !== undefined) {
      for (const key of Object.keys(value)) {
        if (key in props) continue;
        if (schema.additionalProperties === false) fail(`unknown property "${key}"`);
        else if (typeof schema.additionalProperties === 'object') errors.push(...validate(schema.additionalProperties, value[key], root, `${path}.${key}`));
      }
    }
  }
  if (schema.oneOf) {
    const hits = schema.oneOf.filter((s) => validate(s, value, root, path).length === 0).length;
    if (hits !== 1) fail(`must match exactly one alternative (matched ${hits})`);
  }
  if (schema.anyOf && !schema.anyOf.some((s) => validate(s, value, root, path).length === 0)) fail('must match at least one alternative');
  return errors;
}
