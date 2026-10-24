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
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  /** @type {Record<string, any>} */
  const root = {};
  let current = root;
  let pos = 0;

  const line = () => src.slice(0, pos).split('\n').length;
  const fail = (/** @type {string} */ message) => {
    throw new TomlError(message, line());
  };

  const skipWs = () => {
    while (pos < src.length && (src[pos] === ' ' || src[pos] === '\t')) pos++;
  };
  const skipWsNewlinesComments = () => {
    for (;;) {
      while (pos < src.length && /[ \t\r\n]/.test(src[pos])) pos++;
      if (src[pos] === '#') {
        while (pos < src.length && src[pos] !== '\n') pos++;
        continue;
      }
      return;
    }
  };
  const expectLineEnd = () => {
    skipWs();
    if (src[pos] === '#') {
      while (pos < src.length && src[pos] !== '\n') pos++;
    }
    if (src[pos] === '\r') pos++;
    if (pos < src.length && src[pos] !== '\n') fail(`unexpected '${src[pos]}'`);
    pos++;
  };

  const readBasicString = () => {
    pos++;
    let s = '';
    while (pos < src.length && src[pos] !== '"') {
      if (src[pos] === '\n') fail('newline in string');
      if (src[pos] === '\\') {
        s += readEscape();
        continue;
      }
      s += src[pos++];
    }
    if (src[pos] !== '"') fail('unterminated string');
    pos++;
    return s;
  };
  const readEscape = () => {
    pos++;
    const c = src[pos++];
    /** @type {Record<string, string>} */
    const simple = { b: '\b', t: '\t', n: '\n', f: '\f', r: '\r', '"': '"', '\\': '\\', e: '\x1b' };
    if (c in simple) return simple[c];
    if (c === 'u' || c === 'U') {
      const len = c === 'u' ? 4 : 8;
      const hex = src.slice(pos, pos + len);
      pos += len;
      return String.fromCodePoint(parseInt(hex, 16));
    }
    if (c === '\r' || c === '\n' || c === ' ' || c === '\t') {
      while (pos < src.length && /[ \t\r\n]/.test(src[pos])) pos++;
      return '';
    }
    return fail(`bad escape \\${c}`);
  };
  const readMultilineBasic = () => {
    pos += 3;
    if (src[pos] === '\r') pos++;
    if (src[pos] === '\n') pos++;
    let s = '';
    while (pos < src.length && !src.startsWith('"""', pos)) {
      if (src[pos] === '\\') {
        s += readEscape();
        continue;
      }
      s += src[pos++];
    }
    pos += 3;
    while (src[pos] === '"') s += src[pos++];
    return s;
  };
  const readLiteral = () => {
    pos++;
    const end = src.indexOf("'", pos);
    if (end < 0) fail('unterminated literal string');
    const s = src.slice(pos, end);
    pos = end + 1;
    return s;
  };
  const readMultilineLiteral = () => {
    pos += 3;
    if (src[pos] === '\r') pos++;
    if (src[pos] === '\n') pos++;
    const end = src.indexOf("'''", pos);
    if (end < 0) fail('unterminated literal string');
    let s = src.slice(pos, end);
    pos = end + 3;
    while (src[pos] === "'") s += src[pos++];
    return s;
  };

  const readKeyPart = () => {
    skipWs();
    if (src.startsWith('"', pos)) return readBasicString();
    if (src.startsWith("'", pos)) return readLiteral();
    const start = pos;
    while (pos < src.length && /[A-Za-z0-9_-]/.test(src[pos])) pos++;
    if (start === pos) fail(`expected a key, found '${src[pos] ?? 'end of file'}'`);
    return src.slice(start, pos);
  };
  const readKey = () => {
    const parts = [readKeyPart()];
    skipWs();
    while (src[pos] === '.') {
      pos++;
      parts.push(readKeyPart());
      skipWs();
    }
    return parts;
  };

  /** @returns {any} */
  const readValue = () => {
    skipWs();
    if (src.startsWith('"""', pos)) return readMultilineBasic();
    if (src.startsWith("'''", pos)) return readMultilineLiteral();
    const c = src[pos];
    if (c === '"') return readBasicString();
    if (c === "'") return readLiteral();
    if (c === '[') return readArray();
    if (c === '{') return readInlineTable();
    const m = /^[^\s,\]}#]+(?: [0-9:.+\-Z]+)?/.exec(src.slice(pos));
    if (!m) return fail('expected a value');
    const raw = m[0];
    pos += raw.length;
    if (raw === 'true') return true;
    if (raw === 'false') return false;
    if (/^[+-]?(inf|nan)$/.test(raw)) return Number(raw.replace('inf', 'Infinity').replace('nan', 'NaN'));
    const num = raw.replace(/_/g, '');
    if (/^[+-]?(0x[0-9a-fA-F]+|0o[0-7]+|0b[01]+)$/.test(num)) return Number(num.replace(/^\+/, ''));
    if (/^[+-]?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(num)) return Number(num);
    return raw;
  };
  const readArray = () => {
    pos++;
    /** @type {any[]} */
    const arr = [];
    for (;;) {
      skipWsNewlinesComments();
      if (src[pos] === ']') {
        pos++;
        return arr;
      }
      arr.push(readValue());
      skipWsNewlinesComments();
      if (src[pos] === ',') {
        pos++;
        continue;
      }
      if (src[pos] === ']') {
        pos++;
        return arr;
      }
      fail('expected , or ] in array');
    }
  };
  const readInlineTable = () => {
    pos++;
    /** @type {Record<string, any>} */
    const table = {};
    skipWsNewlinesComments();
    if (src[pos] === '}') {
      pos++;
      return table;
    }
    for (;;) {
      skipWsNewlinesComments();
      const key = readKey();
      skipWs();
      if (src[pos] !== '=') fail('expected = in inline table');
      pos++;
      assign(table, key, readValue());
      skipWsNewlinesComments();
      if (src[pos] === ',') {
        pos++;
        skipWsNewlinesComments();
        if (src[pos] === '}') {
          pos++;
          return table;
        }
        continue;
      }
      if (src[pos] === '}') {
        pos++;
        return table;
      }
      fail('expected , or } in inline table');
    }
  };

  /** @param {Record<string, any>} table @param {string[]} key @param {any} value */
  const assign = (table, key, value) => {
    let t = table;
    for (const part of key.slice(0, -1)) {
      if (t[part] === undefined) t[part] = {};
      if (typeof t[part] !== 'object' || Array.isArray(t[part])) fail(`key '${part}' is not a table`);
      t = t[part];
    }
    t[key[key.length - 1]] = value;
  };
  /** @param {string[]} path @param {boolean} arrayOfTables */
  const openTable = (path, arrayOfTables) => {
    /** @type {Record<string, any>} */
    let t = root;
    path.forEach((part, index) => {
      const last = index === path.length - 1;
      if (last && arrayOfTables) {
        if (t[part] === undefined) t[part] = [];
        if (!Array.isArray(t[part])) fail(`'${part}' is not an array of tables`);
        const entry = {};
        t[part].push(entry);
        t = entry;
        return;
      }
      if (t[part] === undefined) t[part] = {};
      const node = t[part];
      t = Array.isArray(node) ? node[node.length - 1] : node;
      if (typeof t !== 'object' || t === null) fail(`'${part}' is not a table`);
    });
    current = t;
  };

  while (pos < src.length) {
    skipWsNewlinesComments();
    if (pos >= src.length) break;
    if (src[pos] === '[') {
      const arrayOfTables = src[pos + 1] === '[';
      pos += arrayOfTables ? 2 : 1;
      const path = readKey();
      skipWs();
      if (src[pos] !== ']' || (arrayOfTables && src[pos + 1] !== ']')) fail('unterminated table header');
      pos += arrayOfTables ? 2 : 1;
      openTable(path, arrayOfTables);
      expectLineEnd();
      continue;
    }
    const key = readKey();
    skipWs();
    if (src[pos] !== '=') fail('expected =');
    pos++;
    assign(current, key, readValue());
    expectLineEnd();
  }
  return root;
}
