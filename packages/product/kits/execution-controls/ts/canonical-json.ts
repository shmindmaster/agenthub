// execution-controls kit: canonical JSON and hashing.
//
// The canonical form is the RFC 8785 (JCS) form restricted to values that
// serialize identically in every language the fleet uses: objects, arrays,
// strings, booleans, null, and integers within +/-(2^53 - 1). Non-integer
// numbers are refused, so money, scores and ratios travel as strings. That one
// restriction is what lets the TypeScript and Python implementations agree
// byte for byte without porting the ECMAScript number printer.

import { createHash } from "node:crypto";

export class CanonicalJsonError extends Error {
  readonly path: string;
  constructor(message: string, path: string) {
    super(`${message} at ${path || "$"}`);
    this.name = "CanonicalJsonError";
    this.path = path;
  }
}

const MAX_SAFE = Number.MAX_SAFE_INTEGER;

function hasLoneSurrogate(value: string): boolean {
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(i + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return true;
      i += 1;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return true;
    }
  }
  return false;
}

function encode(value: unknown, path: string): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "string":
      if (hasLoneSurrogate(value)) throw new CanonicalJsonError("lone surrogate in string", path);
      return JSON.stringify(value);
    case "number":
      if (!Number.isInteger(value)) throw new CanonicalJsonError("non-integer number; encode it as a string", path);
      if (Math.abs(value) > MAX_SAFE) throw new CanonicalJsonError("integer outside the safe range", path);
      return Object.is(value, -0) ? "0" : String(value);
    case "object": {
      if (Array.isArray(value)) {
        return `[${value.map((item, index) => encode(item, `${path}[${index}]`)).join(",")}]`;
      }
      const proto = Object.getPrototypeOf(value);
      if (proto !== Object.prototype && proto !== null) {
        throw new CanonicalJsonError("only plain objects are canonicalizable", path);
      }
      const record = value as Record<string, unknown>;
      // JCS orders keys by UTF-16 code units, which is what the default
      // string comparison does.
      const keys = Object.keys(record).filter((key) => record[key] !== undefined).sort();
      const parts = keys.map((key) => {
        if (hasLoneSurrogate(key)) throw new CanonicalJsonError("lone surrogate in key", path);
        return `${JSON.stringify(key)}:${encode(record[key], `${path}.${key}`)}`;
      });
      return `{${parts.join(",")}}`;
    }
    default:
      throw new CanonicalJsonError(`unsupported type ${typeof value}`, path);
  }
}

/** Canonical JSON text of `value`. Keys whose value is `undefined` are omitted. */
export function canonicalJson(value: unknown): string {
  return encode(value, "");
}

export function sha256Hex(text: string): string {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

/** `sha256:` + hex digest of the canonical JSON of `value`. */
export function canonicalHash(value: unknown): string {
  return `sha256:${sha256Hex(canonicalJson(value))}`;
}

/** Hash of `record` with the named self-referencing field removed. */
export function hashWithout<T extends Record<string, unknown>>(record: T, field: keyof T & string): string {
  const { [field]: _omitted, ...rest } = record;
  return canonicalHash(rest);
}
