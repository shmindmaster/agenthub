// @ts-check
// Dependency-free readers for the config formats coding agents use: JSON with
// comments and trailing commas (VS Code, Cursor, Zed-style files) and the TOML
// subset Codex and Grok write for [mcp_servers.*].

/**
 * Parses JSON that may contain // and /* *\/ comments, a BOM, and trailing
 * commas. Comment markers inside strings are preserved.
 * @param {string} text
 * @returns {any}
 */
export function parseJsonc(text) {
  const source = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  let out = '';
  let i = 0;
  let inString = false;
  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];
    if (inString) {
      out += ch;
      if (ch === '\\') {
        out += next ?? '';
        i += 2;
        continue;
      }
      if (ch === '"') inString = false;
      i++;
      continue;
    }
    if (ch === '"') {
      inString = true;
      out += ch;
      i++;
      continue;
    }
    if (ch === '/' && next === '/') {
      while (i < source.length && source[i] !== '\n') i++;
      continue;
    }
    if (ch === '/' && next === '*') {
      i += 2;
      while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    out += ch;
    i++;
  }
  return JSON.parse(stripTrailingCommas(out));
}

/** @param {string} text */
function stripTrailingCommas(text) {
  let out = '';
  let inString = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      out += ch;
      if (ch === '\\') {
        out += text[i + 1] ?? '';
        i++;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }
    if (ch === ',') {
      let j = i + 1;
      while (j < text.length && /\s/.test(text[j])) j++;
      if (text[j] === '}' || text[j] === ']') continue;
    }
    out += ch;
  }
  return out;
}

export class TomlError extends Error {
  /** @param {string} message @param {number} line */
  constructor(message, line) {
    super(`line ${line}: ${message}`);
    this.line = line;
  }
}

/**
 * Parses the TOML that agent configs use: tables, arrays of tables, dotted
 * and quoted keys, basic/literal/multi-line strings, numbers, booleans,
 * dates (kept as strings), arrays and inline tables.
 * @param {string} text
 * @returns {Record<string, any>}
 */
export function parseToml(text) {
  const root = {};
  /** @type {TomlCursor} */
  const c = {
    src: text.charCodeAt(0) === 0xfeff ? text.slice(1) : text,
    pos: 0,
    root,
    current: root,
  };
  parseTomlDocument(c);
  return c.root;
}

/**
 * Shared mutable parse state for the TOML helpers below: the source text,
 * the read position, the document root, and the table that key/value pairs
 * are currently written into.
 * @typedef {Object} TomlCursor
 * @property {string} src
 * @property {number} pos
 * @property {Record<string, any>} root
 * @property {Record<string, any>} current
 */

/** Throws the parser's TomlError, stamped with the line at the cursor. @param {TomlCursor} c @param {string} message @returns {never} */
function tomlFail(c, message) {
  throw new TomlError(message, c.src.slice(0, c.pos).split('\n').length);
}

/** Skips spaces and tabs. @param {TomlCursor} c */
function skipTomlWhitespace(c) {
  while (c.pos < c.src.length && (c.src[c.pos] === ' ' || c.src[c.pos] === '\t')) c.pos++;
}

/** Skips whitespace, newlines and # comments. @param {TomlCursor} c */
function skipTomlWhitespaceAndComments(c) {
  for (;;) {
    while (c.pos < c.src.length && /[ \t\r\n]/.test(c.src[c.pos])) c.pos++;
    if (c.src[c.pos] === '#') {
      while (c.pos < c.src.length && c.src[c.pos] !== '\n') c.pos++;
      continue;
    }
    return;
  }
}

/** Consumes trailing whitespace or comment plus the line end. @param {TomlCursor} c */
function expectTomlLineEnd(c) {
  skipTomlWhitespace(c);
  if (c.src[c.pos] === '#') {
    while (c.pos < c.src.length && c.src[c.pos] !== '\n') c.pos++;
  }
  if (c.src[c.pos] === '\r') c.pos++;
  if (c.pos < c.src.length && c.src[c.pos] !== '\n') tomlFail(c, `unexpected '${c.src[c.pos]}'`);
  c.pos++;
}

/** Reads a "basic" string, resolving escapes. @param {TomlCursor} c @returns {string} */
function readTomlBasicString(c) {
  c.pos++;
  let s = '';
  while (c.pos < c.src.length && c.src[c.pos] !== '"') {
    if (c.src[c.pos] === '\n') tomlFail(c, 'newline in string');
    if (c.src[c.pos] === '\\') {
      s += readTomlEscape(c);
      continue;
    }
    s += c.src[c.pos++];
  }
  if (c.src[c.pos] !== '"') tomlFail(c, 'unterminated string');
  c.pos++;
  return s;
}

/** Reads what follows a backslash inside a string. @param {TomlCursor} c @returns {string} */
function readTomlEscape(c) {
  c.pos++;
  const esc = c.src[c.pos++];
  /** @type {Record<string, string>} */
  const simple = { b: '\b', t: '\t', n: '\n', f: '\f', r: '\r', '"': '"', '\\': '\\', e: '\x1b' };
  if (esc in simple) return simple[esc];
  if (esc === 'u' || esc === 'U') return readTomlUnicodeEscape(c, esc);
  if (esc === '\r' || esc === '\n' || esc === ' ' || esc === '\t') {
    while (c.pos < c.src.length && /[ \t\r\n]/.test(c.src[c.pos])) c.pos++;
    return '';
  }
  return tomlFail(c, `bad escape \\${esc}`);
}

/** Reads the hex digits of a \u or \U escape whose marker is already consumed. @param {TomlCursor} c @param {'u' | 'U'} esc @returns {string} */
function readTomlUnicodeEscape(c, esc) {
  const len = esc === 'u' ? 4 : 8;
  const hex = c.src.slice(c.pos, c.pos + len);
  c.pos += len;
  return String.fromCodePoint(parseInt(hex, 16));
}

/** Skips a single newline directly after a multi-line string delimiter. @param {TomlCursor} c */
function skipFirstTomlNewline(c) {
  if (c.src[c.pos] === '\r') c.pos++;
  if (c.src[c.pos] === '\n') c.pos++;
}

/** Reads a """multi-line""" basic string. @param {TomlCursor} c @returns {string} */
function readTomlMultilineBasicString(c) {
  c.pos += 3;
  skipFirstTomlNewline(c);
  let s = '';
  while (c.pos < c.src.length && !c.src.startsWith('"""', c.pos)) {
    if (c.src[c.pos] === '\\') {
      s += readTomlEscape(c);
      continue;
    }
    s += c.src[c.pos++];
  }
  c.pos += 3;
  while (c.src[c.pos] === '"') s += c.src[c.pos++];
  return s;
}

/** Reads a 'literal' string with no escapes. @param {TomlCursor} c @returns {string} */
function readTomlLiteralString(c) {
  c.pos++;
  const end = c.src.indexOf("'", c.pos);
  if (end < 0) tomlFail(c, 'unterminated literal string');
  const s = c.src.slice(c.pos, end);
  c.pos = end + 1;
  return s;
}

/** Reads a '''multi-line''' literal string. @param {TomlCursor} c @returns {string} */
function readTomlMultilineLiteralString(c) {
  c.pos += 3;
  skipFirstTomlNewline(c);
  const end = c.src.indexOf("'''", c.pos);
  if (end < 0) tomlFail(c, 'unterminated literal string');
  let s = c.src.slice(c.pos, end);
  c.pos = end + 3;
  while (c.src[c.pos] === "'") s += c.src[c.pos++];
  return s;
}

/** Reads one bare or quoted part of a (possibly dotted) key. @param {TomlCursor} c @returns {string} */
function readTomlKeyPart(c) {
  skipTomlWhitespace(c);
  if (c.src.startsWith('"', c.pos)) return readTomlBasicString(c);
  if (c.src.startsWith("'", c.pos)) return readTomlLiteralString(c);
  const start = c.pos;
  while (c.pos < c.src.length && /[A-Za-z0-9_-]/.test(c.src[c.pos])) c.pos++;
  if (start === c.pos) tomlFail(c, `expected a key, found '${c.src[c.pos] ?? 'end of file'}'`);
  return c.src.slice(start, c.pos);
}

/** Reads a dotted key as its parts, e.g. a."b c" -> ['a', 'b c']. @param {TomlCursor} c @returns {string[]} */
function readTomlKey(c) {
  const parts = [readTomlKeyPart(c)];
  skipTomlWhitespace(c);
  while (c.src[c.pos] === '.') {
    c.pos++;
    parts.push(readTomlKeyPart(c));
    skipTomlWhitespace(c);
  }
  return parts;
}

/** Reads any value: string, array, inline table, boolean, number or bare word. @param {TomlCursor} c @returns {any} */
function readTomlValue(c) {
  skipTomlWhitespace(c);
  if (c.src.startsWith('"""', c.pos)) return readTomlMultilineBasicString(c);
  if (c.src.startsWith("'''", c.pos)) return readTomlMultilineLiteralString(c);
  const ch = c.src[c.pos];
  if (ch === '"') return readTomlBasicString(c);
  if (ch === "'") return readTomlLiteralString(c);
  if (ch === '[') return readTomlArray(c);
  if (ch === '{') return readTomlInlineTable(c);
  return readTomlScalar(c);
}

/**
 * Reads an unquoted value: booleans, numbers (with _ separators, 0x/0o/0b
 * radixes, inf and nan), and anything else kept as the raw string (dates,
 * times and unknown tokens).
 * @param {TomlCursor} c @returns {any}
 */
function readTomlScalar(c) {
  const m = /^[^\s,\]}#]+(?: [0-9:.+\-Z]+)?/.exec(c.src.slice(c.pos));
  if (!m) return tomlFail(c, 'expected a value');
  const raw = m[0];
  c.pos += raw.length;
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  if (/^[+-]?(inf|nan)$/.test(raw)) return Number(raw.replace('inf', 'Infinity').replace('nan', 'NaN'));
  const num = raw.replace(/_/g, '');
  if (/^[+-]?(0x[0-9a-fA-F]+|0o[0-7]+|0b[01]+)$/.test(num)) return Number(num.replace(/^\+/, ''));
  if (/^[+-]?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(num)) return Number(num);
  return raw;
}

/** Reads [ an, array, possibly across lines and comments ]. @param {TomlCursor} c @returns {any[]} */
function readTomlArray(c) {
  c.pos++;
  /** @type {any[]} */
  const arr = [];
  for (;;) {
    skipTomlWhitespaceAndComments(c);
    if (c.src[c.pos] === ']') {
      c.pos++;
      return arr;
    }
    arr.push(readTomlValue(c));
    skipTomlWhitespaceAndComments(c);
    if (c.src[c.pos] === ',') {
      c.pos++;
      continue;
    }
    if (c.src[c.pos] === ']') {
      c.pos++;
      return arr;
    }
    tomlFail(c, 'expected , or ] in array');
  }
}

/** Reads { an = inline, table }, which may span lines and comments here. @param {TomlCursor} c @returns {Record<string, any>} */
function readTomlInlineTable(c) {
  c.pos++;
  /** @type {Record<string, any>} */
  const table = {};
  skipTomlWhitespaceAndComments(c);
  if (c.src[c.pos] === '}') {
    c.pos++;
    return table;
  }
  for (;;) {
    skipTomlWhitespaceAndComments(c);
    const key = readTomlKey(c);
    skipTomlWhitespace(c);
    if (c.src[c.pos] !== '=') tomlFail(c, 'expected = in inline table');
    c.pos++;
    assignTomlValue(c, table, key, readTomlValue(c));
    skipTomlWhitespaceAndComments(c);
    if (c.src[c.pos] === ',') {
      c.pos++;
      skipTomlWhitespaceAndComments(c);
      if (c.src[c.pos] === '}') {
        c.pos++;
        return table;
      }
      continue;
    }
    if (c.src[c.pos] === '}') {
      c.pos++;
      return table;
    }
    tomlFail(c, 'expected , or } in inline table');
  }
}

/** Assigns value at the (possibly dotted) key inside table, creating intermediate tables. @param {TomlCursor} c @param {Record<string, any>} table @param {string[]} key @param {any} value */
function assignTomlValue(c, table, key, value) {
  let t = table;
  for (const part of key.slice(0, -1)) {
    if (t[part] === undefined) t[part] = {};
    if (typeof t[part] !== 'object' || Array.isArray(t[part])) tomlFail(c, `key '${part}' is not a table`);
    t = t[part];
  }
  t[key[key.length - 1]] = value;
}

/** Points c.current at a [table] or [[array of tables]] target, creating intermediates. @param {TomlCursor} c @param {string[]} path @param {boolean} arrayOfTables */
function openTomlTable(c, path, arrayOfTables) {
  let t = c.root;
  path.forEach((part, index) => {
    const last = index === path.length - 1;
    if (last && arrayOfTables) {
      if (t[part] === undefined) t[part] = [];
      if (!Array.isArray(t[part])) tomlFail(c, `'${part}' is not an array of tables`);
      const entry = {};
      t[part].push(entry);
      t = entry;
      return;
    }
    if (t[part] === undefined) t[part] = {};
    const node = t[part];
    t = Array.isArray(node) ? node[node.length - 1] : node;
    if (typeof t !== 'object' || t === null) tomlFail(c, `'${part}' is not a table`);
  });
  c.current = t;
}

/** Reads a [table] or [[array of tables]] header line. @param {TomlCursor} c */
function readTomlHeader(c) {
  const arrayOfTables = c.src[c.pos + 1] === '[';
  c.pos += arrayOfTables ? 2 : 1;
  const path = readTomlKey(c);
  skipTomlWhitespace(c);
  if (c.src[c.pos] !== ']' || (arrayOfTables && c.src[c.pos + 1] !== ']')) tomlFail(c, 'unterminated table header');
  c.pos += arrayOfTables ? 2 : 1;
  openTomlTable(c, path, arrayOfTables);
  expectTomlLineEnd(c);
}

/** Parses the document body into c.root: headers plus key/value lines. @param {TomlCursor} c */
function parseTomlDocument(c) {
  while (c.pos < c.src.length) {
    skipTomlWhitespaceAndComments(c);
    if (c.pos >= c.src.length) break;
    if (c.src[c.pos] === '[') {
      readTomlHeader(c);
      continue;
    }
    const key = readTomlKey(c);
    skipTomlWhitespace(c);
    if (c.src[c.pos] !== '=') tomlFail(c, 'expected =');
    c.pos++;
    assignTomlValue(c, c.current, key, readTomlValue(c));
    expectTomlLineEnd(c);
  }
}
