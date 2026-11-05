#!/usr/bin/env node
// Brave Search API client. Zero dependencies, Node 18+.
// Usage: node brave.mjs <command> "<query>" [--param value ...]
// The key is read from the environment and sent only in a request header.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const API_BASE = 'https://api.search.brave.com/res/v1';
const KEY_VARS = ['BRAVE_SEARCH_API_KEY', 'BRAVE_API_KEY'];
const DEFAULT_MAX_CHARS = 20000;

const COMMANDS = {
  context: { path: '/llm/context', arg: 'query' },
  web: { path: '/web/search', arg: 'query' },
  news: { path: '/news/search', arg: 'query' },
  images: { path: '/images/search', arg: 'query' },
  videos: { path: '/videos/search', arg: 'query' },
  suggest: { path: '/suggest/search', arg: 'query' },
  spellcheck: { path: '/spellcheck/search', arg: 'query' },
  places: { path: '/local/place_search', arg: 'optional-query' },
  pois: { path: '/local/pois', arg: 'ids' },
  descriptions: { path: '/local/descriptions', arg: 'ids' },
  answers: { path: '/chat/completions', arg: 'query', method: 'POST' },
};

const BOOLEAN_FLAGS = new Set(['raw', 'help', 'research', 'citations']);

const USAGE = `Usage: node brave.mjs <command> "<query>" [--param value ...]

Commands: ${Object.keys(COMMANDS).join(', ')}
  pois and descriptions take POI ids from "places" instead of a query.
  places accepts a query, a location, or both.

Any --param value becomes a query parameter (dashes become underscores), for
example --count 5 --freshness pw. --loc-lat and --loc-long become the
X-Loc-Lat and X-Loc-Long headers. --goggles @file reads the definition from a file.

Options:
  --raw             print the full API response instead of the trimmed view
  --max-chars N     cap the output (default ${DEFAULT_MAX_CHARS})
  --research        answers only: multi-search research mode
  --citations       answers only: stream with inline citations
  --timeout N       seconds before the request is abandoned

Key: set BRAVE_SEARCH_API_KEY (or BRAVE_API_KEY) in the environment.`;

class UserError extends Error {}

export function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--') || arg === '--') {
      positional.push(arg);
      continue;
    }
    const eq = arg.indexOf('=');
    const name = (eq === -1 ? arg.slice(2) : arg.slice(2, eq)).toLowerCase();
    let value;
    if (eq !== -1) {
      value = arg.slice(eq + 1);
    } else if (BOOLEAN_FLAGS.has(name)) {
      value = true;
    } else if (i + 1 < argv.length) {
      i += 1;
      value = argv[i];
    } else {
      throw new UserError(`--${name} needs a value.`);
    }
    (flags[name] ??= []).push(value);
  }
  return { positional, flags };
}

function headerName(flag) {
  return flag.split('-').map((part) => part[0].toUpperCase() + part.slice(1)).join('-');
}

function readGoggles(value) {
  return typeof value === 'string' && value.startsWith('@')
    ? readFileSync(value.slice(1), 'utf8')
    : value;
}

export function resolveBase(env) {
  const override = env.BRAVE_SEARCH_API_BASE;
  if (!override) return API_BASE;
  let url;
  try {
    url = new URL(override);
  } catch {
    throw new UserError('BRAVE_SEARCH_API_BASE is not a URL.');
  }
  const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  if (url.protocol !== 'http:' || !loopback) {
    throw new UserError('BRAVE_SEARCH_API_BASE is honoured only for http://127.0.0.1, localhost or [::1] test servers.');
  }
  return override.replace(/\/$/, '');
}

export function readKey(env) {
  for (const name of KEY_VARS) {
    if (env[name] && env[name].trim()) return env[name].trim();
  }
  throw new UserError(`No Brave key found. Set ${KEY_VARS[0]} (or ${KEY_VARS[1]}) in the environment; this script never prints or stores it.`);
}

export function buildRequest(command, positional, flags, env) {
  const spec = COMMANDS[command];
  if (!spec) throw new UserError(`Unknown command "${command}". Commands: ${Object.keys(COMMANDS).join(', ')}.`);
  const base = resolveBase(env);
  const params = new URLSearchParams();
  const headers = { Accept: 'application/json', 'X-Subscription-Token': readKey(env) };
  const text = positional.join(' ').trim();

  if (spec.arg === 'query') {
    if (!text) throw new UserError(`"${command}" needs a query.`);
    params.set('q', text);
  } else if (spec.arg === 'optional-query') {
    if (text) params.set('q', text);
  } else if (spec.arg === 'ids') {
    if (positional.length === 0) throw new UserError(`"${command}" needs one or more POI ids from "places".`);
    for (const id of positional) params.append('ids', id);
  }

  const skip = new Set(['raw', 'max-chars', 'timeout', 'research', 'citations', 'help']);
  for (const [name, values] of Object.entries(flags)) {
    if (skip.has(name)) continue;
    if (name.startsWith('loc-')) {
      headers[`X-${headerName(name)}`] = String(values[0]);
      continue;
    }
    const key = name.replace(/-/g, '_');
    for (const value of values) params.append(key, name === 'goggles' ? readGoggles(value) : String(value));
  }

  if (spec.method === 'POST') {
    const research = flags.research?.[0] === true;
    const citations = flags.citations?.[0] === true;
    const body = {
      model: 'brave',
      messages: [{ role: 'user', content: text }],
      stream: research || citations,
    };
    if (research) body.enable_research = true;
    if (citations) body.enable_citations = true;
    for (const [key, value] of params) {
      if (key === 'q') continue;
      body[key] = /^-?\d+$/.test(value) ? Number(value) : value;
    }
    headers['Content-Type'] = 'application/json';
    return { url: `${base}${spec.path}`, init: { method: 'POST', headers, body: JSON.stringify(body) }, streaming: body.stream };
  }
  const query = params.toString();
  return { url: `${base}${spec.path}${query ? `?${query}` : ''}`, init: { method: 'GET', headers }, streaming: false };
}

// Brave returns snippets with highlight tags and HTML entities; agents read them as plain text.
const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
export const clean = (value) => {
  if (typeof value === 'string') {
    return value
      .replace(/<\/?(?:strong|b|em|i)>/gi, '')
      .replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (m, e) => {
        if (e[0] === '#') {
          const code = e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
          return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : m;
        }
        return ENTITIES[e.toLowerCase()] ?? m;
      });
  }
  return Array.isArray(value) ? value.map(clean) : value;
};

const pick = (obj, paths) => {
  const out = {};
  for (const path of paths) {
    const value = path.split('.').reduce((acc, part) => (acc == null ? undefined : acc[part]), obj);
    if (value !== undefined && value !== null && !(Array.isArray(value) && value.length === 0)) {
      out[path.split('.').pop()] = clean(value);
    }
  }
  return out;
};

const list = (value) => (Array.isArray(value) ? value : []);

export function project(command, data) {
  switch (command) {
    case 'context': {
      const generic = list(data?.grounding?.generic);
      if (!generic.length && !data?.sources) return data;
      return {
        results: generic.map((g) => pick(g, ['url', 'title', 'snippets'])),
        sources: data.sources,
      };
    }
    case 'web': {
      const out = {};
      for (const bucket of ['web', 'discussions', 'news', 'videos']) {
        const results = list(data?.[bucket]?.results);
        if (results.length) {
          out[bucket] = results.map((r) => pick(r, ['title', 'url', 'description', 'age', 'extra_snippets', 'meta_url.hostname']));
        }
      }
      const faq = list(data?.faq?.results);
      if (faq.length) out.faq = faq.map((r) => pick(r, ['question', 'answer', 'url']));
      if (data?.infobox) out.infobox = pick(data.infobox, ['title', 'long_desc', 'url']);
      const locations = list(data?.locations?.results);
      if (locations.length) out.locations = locations.map((r) => pick(r, ['id', 'title']));
      if (data?.query?.altered) out.corrected_query = data.query.altered;
      return Object.keys(out).length ? out : data;
    }
    case 'news':
    case 'videos': {
      const results = list(data?.results);
      if (!results.length) return data;
      return results.map((r) => pick(r, ['title', 'url', 'description', 'age', 'meta_url.hostname', 'video.duration', 'video.creator']));
    }
    case 'images': {
      const results = list(data?.results);
      if (!results.length) return data;
      return results.map((r) => ({
        ...pick(r, ['title', 'source']),
        page: r.url,
        image: r.properties?.url,
        thumbnail: r.thumbnail?.src,
      }));
    }
    case 'places': {
      const results = list(data?.results);
      const out = {
        results: results.map((r) => pick(r, [
          'id', 'title', 'description', 'postal_address.displayAddress', 'coordinates', 'rating.ratingValue',
          'rating.reviewCount', 'contact.telephone', 'opening_hours.current_day', 'price_range', 'distance',
        ])),
      };
      for (const bucket of ['cities', 'regions', 'neighborhoods', 'addresses', 'streets']) {
        if (list(data?.[bucket]).length) out[bucket] = data[bucket];
      }
      if (data?.location) out.location = data.location;
      return results.length || Object.keys(out).length > 1 ? out : data;
    }
    default:
      return data;
  }
}

function tagged(text, tag) {
  const match = text.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
  return match ? match[1].trim() : undefined;
}

export function renderAnswer(rawText, streaming, research, raw) {
  if (!streaming) {
    const data = JSON.parse(rawText);
    return raw ? data : (data?.choices?.[0]?.message?.content ?? data);
  }
  let content = '';
  for (const line of rawText.split(/\r?\n/)) {
    if (!line.startsWith('data:')) continue;
    const payload = line.slice(5).trim();
    if (!payload || payload === '[DONE]') continue;
    try {
      content += JSON.parse(payload)?.choices?.[0]?.delta?.content ?? '';
    } catch {
      // A malformed chunk is skipped; the final text is checked below.
    }
  }
  if (raw || !research) return content;
  const parts = [tagged(content, 'answer') ?? content];
  const blind = tagged(content, 'blindspots');
  if (blind) parts.push(`Blind spots: ${blind}`);
  const usage = tagged(content, 'usage');
  if (usage) {
    try {
      parts.push(`Cost: ${JSON.parse(usage)['X-Request-Total-Cost']}`);
    } catch {
      parts.push(`Usage: ${usage}`);
    }
  }
  return parts.join('\n\n');
}

function explain(status, statusText, bodyText, headers) {
  let hint = '';
  if (status === 401 || status === 403) {
    hint = ' The key was rejected or the plan lacks this endpoint; check the subscription at https://api-dashboard.search.brave.com.';
  } else if (status === 429) {
    const reset = headers.get('x-ratelimit-reset');
    hint = ` Rate limited${reset ? `; window resets in ${reset}s` : ''}. Wait, then retry once.`;
  }
  return `Brave API ${status} ${statusText}: ${bodyText.slice(0, 400)}${hint}`;
}

export function finish(value, maxChars) {
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  if (text.length <= maxChars) return text;
  return `${text.slice(0, maxChars)}\n[truncated ${text.length - maxChars} chars; raise --max-chars or narrow the query]`;
}

async function main(argv, env) {
  const { positional, flags } = parseArgs(argv);
  if (flags.help || positional.length === 0) {
    console.log(USAGE);
    return positional.length === 0 && !flags.help ? 2 : 0;
  }
  const [command, ...rest] = positional;
  const request = buildRequest(command, rest, flags, env);
  const research = flags.research?.[0] === true;
  const seconds = Number(flags.timeout?.[0] ?? (research ? 300 : 30));
  const maxChars = Number(flags['max-chars']?.[0] ?? DEFAULT_MAX_CHARS);
  const raw = flags.raw?.[0] === true;

  let response;
  try {
    response = await fetch(request.url, { ...request.init, redirect: 'error', signal: AbortSignal.timeout(seconds * 1000) });
  } catch (error) {
    throw new UserError(`Request failed: ${error.cause?.code ?? error.name}. The key was not shown.`);
  }
  const bodyText = await response.text();
  if (!response.ok) throw new UserError(explain(response.status, response.statusText, bodyText, response.headers));

  const remaining = response.headers.get('x-ratelimit-remaining');
  if (remaining) console.error(`rate-limit remaining: ${remaining}`);

  let output;
  if (command === 'answers') {
    output = renderAnswer(bodyText, request.streaming, research, raw);
  } else {
    const data = JSON.parse(bodyText);
    output = raw ? data : project(command, data);
  }
  console.log(finish(output, maxChars));
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => { process.exitCode = code; },
    (error) => {
      console.error(error instanceof UserError ? error.message : `Unexpected error: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
