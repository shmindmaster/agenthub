// Dependency-free validator for exactly the JSON Schema keywords the kit
// schemas use. An unsupported keyword throws, so a schema can never silently
// stop being checked.

const KNOWN = new Set([
  "$schema", "$id", "title", "type", "const", "enum", "required", "properties",
  "additionalProperties", "items", "pattern", "minLength", "minimum",
]);

function typeOf(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (typeof value === "number") return Number.isInteger(value) ? "integer" : "number";
  return typeof value;
}

/** Returns a list of error strings; empty means valid. */
export function validate(schema, value, path = "$") {
  const errors = [];
  for (const key of Object.keys(schema)) {
    if (!KNOWN.has(key)) throw new Error(`schema-subset does not support "${key}" at ${path}`);
  }
  if (schema.type !== undefined) {
    const allowed = Array.isArray(schema.type) ? schema.type : [schema.type];
    const actual = typeOf(value);
    if (!allowed.includes(actual) && !(actual === "integer" && allowed.includes("number"))) {
      return [`${path}: type ${actual}, want ${allowed.join("|")}`];
    }
  }
  if ("const" in schema && value !== schema.const) errors.push(`${path}: not ${JSON.stringify(schema.const)}`);
  if (schema.enum && !schema.enum.includes(value)) errors.push(`${path}: ${JSON.stringify(value)} not in enum`);
  if (typeof value === "string") {
    if (schema.pattern && !new RegExp(schema.pattern, "u").test(value)) errors.push(`${path}: does not match ${schema.pattern}`);
    if (schema.minLength !== undefined && value.length < schema.minLength) errors.push(`${path}: shorter than ${schema.minLength}`);
  }
  if (typeof value === "number" && schema.minimum !== undefined && value < schema.minimum) errors.push(`${path}: below ${schema.minimum}`);
  if (Array.isArray(value) && schema.items) {
    value.forEach((item, index) => errors.push(...validate(schema.items, item, `${path}[${index}]`)));
  }
  if (typeOf(value) === "object") {
    for (const key of schema.required ?? []) if (!(key in value)) errors.push(`${path}: missing ${key}`);
    for (const [key, item] of Object.entries(value)) {
      const sub = schema.properties?.[key];
      if (sub) errors.push(...validate(sub, item, `${path}.${key}`));
      else if (schema.additionalProperties === false) errors.push(`${path}: unexpected ${key}`);
      else if (schema.additionalProperties && typeof schema.additionalProperties === "object") {
        errors.push(...validate(schema.additionalProperties, item, `${path}.${key}`));
      }
    }
  }
  return errors;
}
